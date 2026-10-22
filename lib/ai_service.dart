import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'models.dart';
import 'grocery_aggregator.dart';
import 'recipe_codec.dart';
import 'features/recipes/services/recipe_ingestion_service.dart';
import 'core/errors/ai_exception_handler.dart';

Future<http.Response> guardedHttp(
  Future<http.Response> Function() call, {
  Duration retryDelay = const Duration(seconds: 1),
}) async {
  try {
    for (var attempt = 0; ; attempt++) {
      final response = await call();
      if (![500, 502, 503, 504, 529].contains(response.statusCode) ||
          attempt >= 2) {
        return response;
      }
      await Future<void>.delayed(retryDelay * (attempt + 1));
    }
  } on TimeoutException {
    throw const FormatException(
      'AI request timed out. Check your connection or try another provider.',
    );
  } on SocketException {
    throw const FormatException(
      'Cannot reach the AI server. Check internet access, VPN and DNS. Your saved key has not been removed.',
    );
  } on http.ClientException {
    throw const FormatException(
      'AI network connection failed. Check internet access, VPN and DNS.',
    );
  }
}

String providerError(
  String provider,
  http.Response response,
  String key,
  String model,
) {
  String detail = '';
  try {
    final error = (jsonDecode(response.body) as Map)['error'];
    if (error is Map) {
      detail = (error['message'] ?? error['status'] ?? '').toString();
    }
  } catch (_) {}
  if (key.isNotEmpty) detail = detail.replaceAll(key, '[redacted]');
  detail = detail.replaceAll(
    RegExp(r'AIza[A-Za-z0-9_-]+|sk-[A-Za-z0-9_-]+'),
    '[redacted]',
  );
  if (detail.length > 600) detail = detail.substring(0, 600);
  final hint = switch (response.statusCode) {
    400 =>
      'The request was rejected. Check the detail below and choose a model from Load available models.',
    401 ||
    403 => 'Check API key permissions, account billing and regional access.',
    404 =>
      'This model is unavailable for this key. Choose another model; no particular model is required.',
    429 => 'Rate limit or quota reached. Check API billing and retry later.',
    503 || 529 =>
      'The service is overloaded. Retried twice; try later or choose another model/provider.',
    _ => 'The provider could not complete this request.',
  };
  return '$provider HTTP ${response.statusCode} ($model): $hint${detail.isEmpty ? '' : '\n$detail'}';
}

abstract class AIService {
  Future<Recipe> parseRecipe(String text, {Uint8List? image, String? mimeType});
  Future<List<Ingredient>> detectPantry(Uint8List image, {String? mimeType});
  Future<Recipe> compose({
    required String protein,
    required List<String> excludedTitles,
    required List<String> freshIngredients,
    required String profile,
    List<String> pantryOnlyIngredients = const [],
  });
}

void validatePantryOnlyRecipe(Recipe recipe, List<String> pantryNames) {
  if (pantryNames.isEmpty) return;
  final allowed = pantryNames.map(GroceryAggregator.canonicalName).toSet();
  const alwaysAllowed = {'water', 'salt'};
  final unavailable =
      recipe.ingredients
          .map((item) => GroceryAggregator.canonicalName(item.name))
          .where(
            (name) =>
                !alwaysAllowed.contains(name) &&
                !allowed.contains(name) &&
                !allowed.any(
                  (pantryName) => ingredientNamesMatch(name, pantryName),
                ),
          )
          .toSet()
          .toList()
        ..sort();
  if (unavailable.isNotEmpty) {
    throw FormatException(
      'The generated recipe used ingredients outside your pantry: ${unavailable.join(', ')}.',
    );
  }
}

bool ingredientNamesMatch(String first, String second) {
  final a = GroceryAggregator.canonicalName(first).split(' ').toSet();
  final b = GroceryAggregator.canonicalName(second).split(' ').toSet();
  if (a.containsAll(b) || b.containsAll(a)) return true;
  const proteinFamilies = [
    {'beef', 'steak'},
    {'fish', 'salmon', 'tuna', 'cod', 'trout', 'tilapia', 'haddock', 'hake'},
    {
      'shellfish',
      'shrimp',
      'prawn',
      'crab',
      'lobster',
      'mussel',
      'clam',
      'scallop',
    },
  ];
  return proteinFamilies.any(
    (family) =>
        a.intersection(family).isNotEmpty && b.intersection(family).isNotEmpty,
  );
}

bool pantrySupportsProtein(List<String> pantryNames, String protein) {
  final text = normalized(pantryNames.join(' '));
  return switch (protein) {
    'chicken' => RegExp(r'\bchicken\b').hasMatch(text),
    'beef' => RegExp(r'\b(?:beef|steak)\b').hasMatch(text),
    'fish' => RegExp(
      r'\b(?:fish|salmon|tuna|cod|trout|tilapia|haddock|hake|shrimp|prawn|crab|lobster|mussel|clam|scallop)\b',
    ).hasMatch(text),
    _ => true,
  };
}

class GeminiDirectService implements AIService {
  final String apiKey, model;
  final http.Client client;
  GeminiDirectService({
    required this.apiKey,
    this.model = 'gemini-flash-latest',
    http.Client? client,
  }) : client = client ?? http.Client();
  // Gemini's responseSchema uses its OpenAPI subset, not the full JSON schema
  // shared with the other providers.
  static Map<String, dynamic> _responseSchema(Map<String, dynamic> json) => {
    'type': (json['type'] as String).toUpperCase(),
    if (json['enum'] != null) 'enum': json['enum'],
    if (json['items'] != null)
      'items': _responseSchema(Map<String, dynamic>.from(json['items'] as Map)),
    if (json['properties'] != null)
      'properties': {
        for (final entry in (json['properties'] as Map).entries)
          entry.key as String: _responseSchema(
            Map<String, dynamic>.from(entry.value as Map),
          ),
      },
    if (json['required'] != null) 'required': json['required'],
  };
  Future<Recipe> request(
    String prompt, {
    Uint8List? image,
    String? mimeType,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw const FormatException('Add an API key in Settings first.');
    }
    final selectedModel = model.trim().replaceFirst(RegExp(r'^models/'), '');
    if (!RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(selectedModel)) {
      throw const AiRequestException(400, 'Invalid model identifier.');
    }
    if (image != null && image.length > 10 * 1024 * 1024) {
      throw const FormatException('Choose an image smaller than 10 MB.');
    }
    final response = await guardedHttp(
      () async => await client
          .post(
            Uri.https(
              'generativelanguage.googleapis.com',
              '/v1beta/models/$selectedModel:generateContent',
            ),
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': apiKey.trim(),
            },
            body: jsonEncode({
              'systemInstruction': {
                'parts': [
                  {'text': recipeInstructions},
                ],
              },
              'contents': [
                {
                  'role': 'user',
                  'parts': [
                    {'text': prompt},
                    if (image != null)
                      {
                        'inlineData': {
                          'mimeType': mimeType ?? 'image/jpeg',
                          'data': base64Encode(image),
                        },
                      },
                  ],
                },
              ],
              'generationConfig': {
                'responseMimeType': 'application/json',
                'responseSchema': _responseSchema(recipeSchema),
              },
            }),
          )
          .timeout(const Duration(seconds: 75)),
    );
    if (response.statusCode != 200) {
      throw AiRequestException(
        response.statusCode,
        providerError('Gemini', response, apiKey, selectedModel),
      );
    }
    // Read only recipe output. Reasoning text and new API metadata must not be
    // passed to the recipe decoder or rejected by an outdated SDK enum parser.
    try {
      final body = jsonDecode(response.body) as Map;
      final feedback = body['promptFeedback'];
      if (feedback is Map &&
          feedback['blockReason'] != null &&
          feedback['blockReason'] != 'BLOCK_REASON_UNSPECIFIED') {
        throw const AiResponseException(AiResponseProblem.blocked);
      }
      final candidates = body['candidates'] as List? ?? [];
      if (candidates.isEmpty) {
        throw const AiResponseException(AiResponseProblem.empty);
      }
      final candidate = candidates.first as Map;
      final finish = candidate['finishReason'];
      if (finish == 'MAX_TOKENS') {
        throw const AiResponseException(AiResponseProblem.truncated);
      }
      if (finish != null &&
          finish != 'STOP' &&
          finish != 'FINISH_REASON_UNSPECIFIED') {
        throw const AiResponseException(AiResponseProblem.blocked);
      }
      final content = candidate['content'] as Map?;
      final parts = content?['parts'] as List? ?? [];
      final output = parts
          .whereType<Map>()
          .where((part) => part['thought'] != true && part['text'] is String)
          .map((part) => part['text'] as String)
          .join();
      if (output.trim().isEmpty) {
        throw const AiResponseException(AiResponseProblem.empty);
      }
      return decodeRecipe(output);
    } on AiResponseException {
      rethrow;
    } on FormatException {
      throw const AiResponseException(AiResponseProblem.invalid);
    } on TypeError {
      throw const AiResponseException(AiResponseProblem.invalid);
    }
  }

  @override
  Future<Recipe> parseRecipe(
    String text, {
    Uint8List? image,
    String? mimeType,
  }) => request(
    'Extract this recipe faithfully. Do not guess missing source content.\nSOURCE:\n$text',
    image: image,
    mimeType: mimeType,
  );
  @override
  Future<List<Ingredient>> detectPantry(
    Uint8List image, {
    String? mimeType,
  }) async {
    final result = await request(
      'Identify only food ingredients clearly visible in this pantry photo. Return a recipe titled "Pantry scan", protein "other", servings 1, one instruction "Review detected items", and put every visible food item in ingredients. Use a package quantity and unit only when clearly readable; otherwise use quantity 0 and unit "as needed". Do not include shelves, appliances, containers, or guessed hidden contents.',
      image: image,
      mimeType: mimeType,
    );
    return result.ingredients;
  }

  @override
  Future<Recipe> compose({
    required String protein,
    required List<String> excludedTitles,
    required List<String> freshIngredients,
    required String profile,
    List<String> pantryOnlyIngredients = const [],
  }) async {
    final recipe = await request(
      'Compose one new $protein dinner. Household preferences: $profile. Do not repeat, rename, imitate, or reuse the core concept of these dishes: ${jsonEncode(excludedTitles)}. Prefer using these ingredients: ${jsonEncode(freshIngredients)}.${pantryOnlyIngredients.isEmpty ? '' : ' STRICT REQUIREMENT: every ingredient, including oils, seasonings, and garnishes, must come from this pantry list and no other ingredient may be used: ${jsonEncode(pantryOnlyIngredients)}. Water and salt are the only exceptions and may be used even when absent from the list.'}',
    );
    if (recipe.protein != protein ||
        excludedTitles.any((t) => normalized(t) == normalized(recipe.title))) {
      throw const FormatException(
        'Generated recipe broke the requested constraints. Please retry.',
      );
    }
    validatePantryOnlyRecipe(recipe, pantryOnlyIngredients);
    return recipe;
  }
}

/// Compatibility entry point for callers with one source field.
class RecipeImporter {
  final AIService ai;
  RecipeImporter(this.ai);
  Future<Recipe> parse(String input, {Uint8List? image, String? mimeType}) {
    final uri = Uri.tryParse(input.trim());
    final isUrl =
        uri != null &&
        ['http', 'https'].contains(uri.scheme) &&
        uri.host.isNotEmpty &&
        !input.trim().contains(RegExp(r'\s'));
    return RecipeIngestionService(ai).ingest(
      url: isUrl ? input : '',
      blurb: isUrl ? '' : input,
      image: image,
      mimeType: mimeType,
    );
  }
}
