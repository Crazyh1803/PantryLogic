import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pantry_logic/ai_service.dart';
import 'package:pantry_logic/core/errors/ai_exception_handler.dart';
import 'package:pantry_logic/seed.dart';

void main() {
  final recipe = seedRecipes().first;
  Map<String, Object?> candidate({
    String finish = 'STOP',
    List<Object?>? parts,
  }) => {
    'finishReason': finish,
    'content': {
      'parts':
          parts ??
          [
            {'text': jsonEncode(recipe.toJson())},
          ],
    },
  };
  GeminiDirectService service(Object body) => GeminiDirectService(
    apiKey: 'test-key',
    client: MockClient((_) async => http.Response(jsonEncode(body), 200)),
  );

  test(
    'Gemini ignores thought parts and new metadata when decoding a recipe',
    () async {
      final ai = service({
        'candidates': [
          candidate(
            parts: [
              {'text': 'Reasoning is not recipe JSON.', 'thought': true},
              {
                'text': jsonEncode(recipe.toJson()),
                'thoughtSignature': 'opaque',
              },
            ],
          ),
        ],
        'usageMetadata': {'newMetadataField': true},
        'modelVersion': 'new-model-version',
      });
      expect((await ai.parseRecipe('Recipe text')).title, recipe.title);
    },
  );

  test(
    'Gemini preserves structured schema and image bytes in direct request',
    () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final ai = GeminiDirectService(
        apiKey: ' test-key ',
        model: 'models/gemini-flash-latest',
        client: MockClient((request) async {
          expect(
            request.url.path,
            '/v1beta/models/gemini-flash-latest:generateContent',
          );
          expect(request.url.query, isEmpty);
          expect(request.headers['x-goog-api-key'], 'test-key');
          final body = jsonDecode(request.body) as Map;
          expect(
            body['generationConfig']['responseMimeType'],
            'application/json',
          );
          final schema = body['generationConfig']['responseSchema'];
          expect(schema['type'], 'OBJECT');
          expect(
            schema['properties']['ingredients']['items']['type'],
            'OBJECT',
          );
          expect(schema.containsKey('additionalProperties'), isFalse);
          expect(body['contents'][0]['parts'][1]['inlineData'], {
            'mimeType': 'image/png',
            'data': base64Encode(bytes),
          });
          return http.Response(
            jsonEncode({
              'candidates': [candidate()],
            }),
            200,
          );
        }),
      );
      expect(
        (await ai.parseRecipe(
          'Screenshot',
          image: bytes,
          mimeType: 'image/png',
        )).title,
        recipe.title,
      );
    },
  );

  final failures = <String, (Object, AiResponseProblem)>{
    'truncated JSON': (
      {
        'candidates': [
          candidate(
            finish: 'MAX_TOKENS',
            parts: [
              {'text': '{"title":'},
            ],
          ),
        ],
      },
      AiResponseProblem.truncated,
    ),
    'blocked prompt without legacy safety ratings': (
      {
        'promptFeedback': {'blockReason': 'SAFETY'},
      },
      AiResponseProblem.blocked,
    ),
    'new response block reason': (
      {
        'candidates': [candidate(finish: 'IMAGE_SAFETY')],
      },
      AiResponseProblem.blocked,
    ),
    'empty candidates': ({'candidates': []}, AiResponseProblem.empty),
    'thought-only response': (
      {
        'candidates': [
          candidate(
            parts: [
              {'text': 'thinking', 'thought': true},
            ],
          ),
        ],
      },
      AiResponseProblem.empty,
    ),
    'malformed recipe': (
      {
        'candidates': [
          candidate(
            parts: [
              {'text': 'not JSON'},
            ],
          ),
        ],
      },
      AiResponseProblem.invalid,
    ),
    'malformed response envelope': (
      {'candidates': 'wrong type'},
      AiResponseProblem.invalid,
    ),
  };
  for (final entry in failures.entries) {
    test(
      'Gemini distinguishes ${entry.key} from generic parsing errors',
      () async {
        try {
          await service(entry.value.$1).parseRecipe('Recipe text');
          fail('Expected a response failure');
        } on AiResponseException catch (error) {
          expect(error.problem, entry.value.$2);
          final failure = AiExceptionHandler.describe(
            AiFallbackException(error),
          );
          expect(failure.message, isNot(contains("couldn't parse")));
          expect(failure.message, isNot(contains('test-key')));
        }
      },
    );
  }

  test('Gemini preserves account errors and redacts the key', () async {
    final ai = GeminiDirectService(
      apiKey: 'test-key',
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {'message': 'API key not valid: test-key'},
          }),
          400,
        ),
      ),
    );
    try {
      await ai.parseRecipe('Recipe text');
      fail('Expected account error');
    } on AiRequestException catch (error) {
      expect(error.detail, isNot(contains('test-key')));
      expect(AiExceptionHandler.describe(error).action, AiErrorAction.settings);
      expect(
        AiExceptionHandler.describe(error).message,
        contains('Invalid API key'),
      );
    }
  });

  test('quota errors do not promise a thirty-second recovery', () {
    final failure = AiExceptionHandler.describe(
      const AiRequestException(429, 'quota'),
    );
    expect(failure.message, contains('quota'));
    expect(failure.message, isNot(contains('30 seconds')));
  });
}
