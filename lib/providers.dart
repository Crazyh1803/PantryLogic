import 'dart:convert';
import 'dart:typed_data';
import 'ai_service.dart';
import 'models.dart';
import 'recipe_codec.dart';
import 'core/errors/ai_exception_handler.dart';

const providerModels = {
  'Gemini': 'gemini-flash-latest',
  'OpenAI': 'gpt-5.6-luna',
  'Claude': 'claude-sonnet-5',
  'Grok': 'grok-4.6',
};
const providerLinks = {
  'Gemini': 'https://aistudio.google.com/apikey',
  'OpenAI': 'https://platform.openai.com/api-keys',
  'Claude': 'https://platform.claude.com/settings/keys',
  'Grok': 'https://console.x.ai/',
};

class ProviderService extends GeminiDirectService {
  final String provider;
  ProviderService({
    required this.provider,
    required super.apiKey,
    required super.model,
    super.client,
  });
  Future<List<String>> availableModels() async {
    if (apiKey.trim().isEmpty) {
      throw FormatException('Enter your $provider key first.');
    }
    final host = switch (provider) {
      'Gemini' => 'generativelanguage.googleapis.com',
      'Claude' => 'api.anthropic.com',
      'OpenAI' => 'api.openai.com',
      _ => 'api.x.ai',
    };
    final headers = <String, String>{};
    if (provider == 'Gemini') {
      headers['x-goog-api-key'] = apiKey.trim();
    } else if (provider == 'Claude') {
      headers.addAll({
        'x-api-key': apiKey.trim(),
        'anthropic-version': '2023-06-01',
      });
    } else {
      headers['Authorization'] = 'Bearer ${apiKey.trim()}';
    }
    final models = <String>{};
    String? cursor;
    for (var page = 0; page < 10; page++) {
      final query = <String, String>{
        if (provider == 'Gemini') 'pageSize': '100',
        if (provider == 'Claude') 'limit': '100',
        (provider == 'Gemini' ? 'pageToken' : 'after_id'): ?cursor,
      };
      final response = await guardedHttp(
        () => client
            .get(
              Uri.https(
                host,
                provider == 'Gemini' ? '/v1beta/models' : '/v1/models',
                query,
              ),
              headers: headers,
            )
            .timeout(const Duration(seconds: 30)),
      );
      if (response.statusCode != 200) {
        throw AiRequestException(
          response.statusCode,
          providerError(provider, response, apiKey, model),
        );
      }
      final body = jsonDecode(response.body) as Map;
      for (final item
          in (body[provider == 'Gemini' ? 'models' : 'data'] as List? ?? [])) {
        if (provider == 'Gemini' &&
            !(item['supportedGenerationMethods'] as List? ?? []).contains(
              'generateContent',
            )) {
          continue;
        }
        final id = (item[provider == 'Gemini' ? 'name' : 'id'] ?? '')
            .toString()
            .replaceFirst(RegExp(r'^models/'), '');
        if (id.isNotEmpty) models.add(id);
      }
      cursor = provider == 'Gemini'
          ? body['nextPageToken'] as String?
          : provider == 'Claude' && body['has_more'] == true
          ? body['last_id'] as String?
          : null;
      if (cursor == null || cursor.isEmpty) break;
    }
    return models.toList()..sort();
  }

  @override
  Future<Recipe> request(
    String prompt, {
    Uint8List? image,
    String? mimeType,
  }) async {
    if (provider == 'Gemini') {
      return super.request(prompt, image: image, mimeType: mimeType);
    }
    if (apiKey.trim().isEmpty) {
      throw FormatException('Add your $provider API key in Settings.');
    }
    if (image != null && image.length > 7 * 1024 * 1024) {
      throw const FormatException(
        'For this provider, use an image smaller than 7 MB.',
      );
    }
    const system = recipeInstructions;
    final encoded = image == null ? null : base64Encode(image);
    final mime = mimeType ?? 'image/jpeg';
    late String url;
    final headers = {'Content-Type': 'application/json'};
    late Map<String, dynamic> body;
    if (provider == 'Claude') {
      url = 'https://api.anthropic.com/v1/messages';
      headers.addAll({
        'x-api-key': apiKey.trim(),
        'anthropic-version': '2023-06-01',
      });
      body = {
        'model': model,
        'max_tokens': 8192,
        'tools': [
          {
            'name': 'save_recipe',
            'description': 'Return the extracted or composed recipe',
            'input_schema': recipeSchema,
          },
        ],
        'tool_choice': {'type': 'tool', 'name': 'save_recipe'},
        'system': system,
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': prompt},
              if (encoded != null)
                {
                  'type': 'image',
                  'source': {
                    'type': 'base64',
                    'media_type': mime,
                    'data': encoded,
                  },
                },
            ],
          },
        ],
      };
    } else if (provider == 'OpenAI') {
      url = 'https://api.openai.com/v1/responses';
      headers['Authorization'] = 'Bearer ${apiKey.trim()}';
      body = {
        'model': model,
        'store': false,
        'text': {
          'format': {
            'type': 'json_schema',
            'name': 'recipe',
            'strict': true,
            'schema': recipeSchema,
          },
        },
        'instructions': system,
        'input': [
          {
            'role': 'user',
            'content': [
              {'type': 'input_text', 'text': prompt},
              if (encoded != null)
                {
                  'type': 'input_image',
                  'image_url': 'data:$mime;base64,$encoded',
                },
            ],
          },
        ],
      };
    } else if (provider == 'Grok') {
      url = 'https://api.x.ai/v1/chat/completions';
      headers['Authorization'] = 'Bearer ${apiKey.trim()}';
      body = {
        'model': model,
        'messages': [
          {'role': 'system', 'content': system},
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': prompt},
              if (encoded != null)
                {
                  'type': 'image_url',
                  'image_url': {'url': 'data:$mime;base64,$encoded'},
                },
            ],
          },
        ],
      };
    } else {
      throw const FormatException('Unknown AI provider.');
    }
    final response = await guardedHttp(
      () => client
          .post(Uri.parse(url), headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 75)),
    );
    if (response.statusCode != 200) {
      throw AiRequestException(
        response.statusCode,
        providerError(provider, response, apiKey, model),
      );
    }
    try {
      final j = jsonDecode(response.body) as Map;
      String output;
      if (provider == 'Claude') {
        final tools = (j['content'] as List).where(
          (p) => p['type'] == 'tool_use' && p['name'] == 'save_recipe',
        );
        if (tools.isNotEmpty) return decodeRecipe(tools.first['input']);
        if (j['stop_reason'] == 'max_tokens') {
          throw const FormatException(
            'Claude output was truncated; use a shorter recipe or another model.',
          );
        }
        output = (j['content'] as List)
            .where((p) => p['type'] == 'text')
            .map((p) => p['text'])
            .join();
      } else if (provider == 'OpenAI') {
        if (j['status'] == 'incomplete') {
          throw const FormatException(
            'OpenAI returned an incomplete response. Try a shorter source or another model.',
          );
        }
        final refusals = (j['output'] as List)
            .where((p) => p['type'] == 'message')
            .expand((p) => p['content'] as List)
            .where((p) => p['type'] == 'refusal');
        if (refusals.isNotEmpty) {
          throw const FormatException(
            'OpenAI declined this request. Try another source or provider.',
          );
        }
        output = (j['output'] as List)
            .where((p) => p['type'] == 'message')
            .expand((p) => p['content'] as List)
            .where((p) => p['type'] == 'output_text')
            .map((p) => p['text'])
            .join();
      } else {
        output = j['choices'][0]['message']['content'] as String;
      }
      output = output
          .trim()
          .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
          .replaceFirst(RegExp(r'\s*```$'), '');
      return decodeRecipe(output);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw FormatException(
        '$provider did not return a complete recipe. Try clearer source text or another provider.',
      );
    }
  }
}

class FallbackService implements AIService {
  final List<ProviderService> services;
  FallbackService(this.services);
  Future<Recipe> attempt(
    Future<Recipe> Function(ProviderService) action,
  ) async {
    final errors = <Exception>[];
    for (final service in services) {
      try {
        return await action(service);
      } on Exception catch (e) {
        errors.add(e);
      }
    }
    throw AiFallbackException(
      errors.isEmpty
          ? const FormatException('Add an API key in Settings first.')
          : errors.first,
    );
  }

  @override
  Future<Recipe> parseRecipe(
    String text, {
    Uint8List? image,
    String? mimeType,
  }) => attempt((s) => s.parseRecipe(text, image: image, mimeType: mimeType));
  @override
  Future<Recipe> compose({
    required String protein,
    required List<String> excludedTitles,
    required List<String> freshIngredients,
    required String profile,
  }) => attempt(
    (s) => s.compose(
      protein: protein,
      excludedTitles: excludedTitles,
      freshIngredients: freshIngredients,
      profile: profile,
    ),
  );
}
