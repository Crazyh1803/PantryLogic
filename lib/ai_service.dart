import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:google_generative_ai/google_generative_ai.dart' as google;
import 'models.dart';
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
  Future<Recipe> compose({
    required String protein,
    required List<String> excludedTitles,
    required List<String> freshIngredients,
    required String profile,
  });
}

class GeminiDirectService implements AIService {
  final String apiKey, model;
  final http.Client client;
  GeminiDirectService({
    required this.apiKey,
    this.model = 'gemini-flash-latest',
    http.Client? client,
  }) : client = client ?? http.Client();
  static google.Schema sdkSchema(Map<String, dynamic> json) => google.Schema(
    google.SchemaType.values.firstWhere((t) => t.name == json['type']),
    enumValues: json['enum'] == null
        ? null
        : List<String>.from(json['enum'] as List),
    items: json['items'] == null
        ? null
        : sdkSchema(Map<String, dynamic>.from(json['items'] as Map)),
    properties: json['properties'] == null
        ? null
        : {
            for (final e in (json['properties'] as Map).entries)
              e.key as String: sdkSchema(
                Map<String, dynamic>.from(e.value as Map),
              ),
          },
    requiredProperties: json['required'] == null
        ? null
        : List<String>.from(json['required'] as List),
  );
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
    final transport = _GeminiTransport(client, apiKey, selectedModel);
    final sdk = google.GenerativeModel(
      model: selectedModel,
      apiKey: apiKey.trim(),
      httpClient: transport,
      systemInstruction: google.Content.system(recipeInstructions),
      generationConfig: google.GenerationConfig(
        responseMimeType: 'application/json',
        responseSchema: sdkSchema(recipeSchema),
      ),
    );
    final response = await sdk
        .generateContent([
          google.Content.multi([
            google.TextPart(prompt),
            if (image != null) google.DataPart(mimeType ?? 'image/jpeg', image),
          ]),
        ])
        .timeout(const Duration(seconds: 90));
    final output = response.text;
    if (output == null || output.trim().isEmpty) {
      throw const FormatException('No complete recipe found.');
    }
    return decodeRecipe(output);
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
  Future<Recipe> compose({
    required String protein,
    required List<String> excludedTitles,
    required List<String> freshIngredients,
    required String profile,
  }) async {
    final recipe = await request(
      'Compose one new $protein dinner. Household preferences: $profile. Do not repeat or rename these dishes: ${jsonEncode(excludedTitles)}. Prefer using these perishables: ${jsonEncode(freshIngredients)}.',
    );
    if (recipe.protein != protein ||
        excludedTitles.any((t) => normalized(t) == normalized(recipe.title))) {
      throw const FormatException(
        'Generated recipe broke the requested constraints. Please retry.',
      );
    }
    return recipe;
  }
}

class _GeminiTransport extends http.BaseClient {
  final http.Client inner;
  final String apiKey, model;
  _GeminiTransport(this.inner, this.apiKey, this.model);
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final bytes = await request.finalize().toBytes();
    final response = await guardedHttp(() async {
      final copy = http.Request(request.method, request.url)
        ..headers.addAll(request.headers)
        ..bodyBytes = bytes;
      return http.Response.fromStream(
        await inner.send(copy),
      ).timeout(const Duration(seconds: 75));
    });
    if (response.statusCode != 200) {
      throw AiRequestException(
        response.statusCode,
        providerError('Gemini', response, apiKey, model),
      );
    }
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
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
