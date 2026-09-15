// ignore_for_file: avoid_print
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pantry_logic/ai_service.dart';
import 'package:pantry_logic/seed.dart';

Future<void> main() async {
  final recipe = seedRecipes().first;
  final ai = GeminiDirectService(
    apiKey: 'test-key',
    client: MockClient((request) async {
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (request.headers['x-goog-api-key'] != 'test-key' ||
          body['generationConfig']['responseMimeType'] != 'application/json')
        throw StateError('Invalid request');
      return http.Response(
        jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': jsonEncode(recipe.toJson())},
                ],
              },
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
  final parsed = await ai.parseRecipe('Test source');
  if (parsed.title != recipe.title) throw StateError('Recipe parse mismatch');
  print('PASS: Gemini structured request and response parsing');
  bool rejected = false;
  try {
    await ai.compose(
      protein: 'fish',
      excludedTitles: [],
      freshIngredients: [],
      profile: '',
    );
  } on FormatException {
    rejected = true;
  }
  if (!rejected) throw StateError('Wrong protein accepted');
  print('PASS: invalid generated protein rejected');
  rejected = false;
  try {
    await ai.compose(
      protein: 'chicken',
      excludedTitles: [recipe.title],
      freshIngredients: [],
      profile: '',
    );
  } on FormatException {
    rejected = true;
  }
  if (!rejected) throw StateError('Repeated title accepted');
  print('PASS: duplicate generated recipe rejected');
  for (final code in [403, 429, 500]) {
    final failing = GeminiDirectService(
      apiKey: 'test',
      client: MockClient((_) async => http.Response('{}', code)),
    );
    rejected = false;
    try {
      await failing.parseRecipe('Test');
    } on FormatException {
      rejected = true;
    }
    if (!rejected) throw StateError('HTTP $code accepted');
    print('PASS: HTTP $code returns actionable error');
  }
  print('6 AI adapter checks passed (mocked; no live API key used).');
}
