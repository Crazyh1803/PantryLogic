// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pantry_logic/ai_service.dart';
import 'package:pantry_logic/models.dart';
import 'package:pantry_logic/providers.dart';
import 'package:pantry_logic/seed.dart';

Future<void> main() async {
  final recipe = seedRecipes().first;
  final client = MockClient((request) async {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    if (request.headers['x-goog-api-key'] != 'test-key' ||
        body['generationConfig']['responseMimeType'] != 'application/json') {
      throw StateError('Invalid request');
    }
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
  });
  final ai = GeminiDirectService(apiKey: 'test-key', client: client);
  final parsed = await ai.parseRecipe('Test source');
  if (parsed.title != recipe.title) throw StateError('Recipe parse mismatch');
  print('PASS: Gemini structured request and response parsing');
  final detected = await ai.detectPantry(
    Uint8List.fromList([1, 2, 3]),
    mimeType: 'image/jpeg',
  );
  if (detected.length != recipe.ingredients.length) {
    throw StateError('Pantry image extraction mismatch');
  }
  print('PASS: pantry image uses the structured provider path');
  final fallback = FallbackService([
    ProviderService(
      provider: 'Gemini',
      apiKey: 'test-key',
      model: 'gemini-flash-latest',
      client: client,
    ),
  ]);
  final pantryComposed = await fallback.compose(
    protein: recipe.protein,
    excludedTitles: const [],
    freshIngredients: const [],
    profile: '',
    pantryOnlyIngredients: recipe.ingredients.map((item) => item.name).toList(),
  );
  if (pantryComposed.title != recipe.title) {
    throw StateError('Fallback pantry-only composition mismatch');
  }
  print('PASS: fallback preserves pantry-only composition constraints');
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
  validatePantryOnlyRecipe(
    recipe,
    recipe.ingredients.map((i) => i.name).toList(),
  );
  validatePantryOnlyRecipe(
    Recipe(
      title: 'Simple chicken',
      protein: 'chicken',
      ingredients: [
        Ingredient(name: 'chicken breast', quantity: 1, unit: 'whole'),
        Ingredient(name: 'salt', quantity: 1, unit: 'tsp'),
        Ingredient(name: 'water', quantity: 100, unit: 'ml'),
      ],
      instructions: ['Cook.'],
    ),
    ['chicken'],
  );
  validatePantryOnlyRecipe(
    Recipe(
      title: 'Pantry names',
      protein: 'fish',
      ingredients: [
        Ingredient(name: 'chicken', quantity: 1, unit: 'whole'),
        Ingredient(name: 'oil', quantity: 1, unit: 'tbsp'),
        Ingredient(name: 'salmon fillet', quantity: 1, unit: 'whole'),
      ],
      instructions: ['Cook.'],
    ),
    ['chicken breast', 'olive oil', 'fish'],
  );
  rejected = false;
  try {
    validatePantryOnlyRecipe(recipe, ['an unrelated ingredient']);
  } on FormatException {
    rejected = true;
  }
  if (!rejected) throw StateError('Out-of-pantry recipe accepted');
  print('PASS: pantry-only generated recipe is validated locally');
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
  print('AI adapter checks passed (mocked; no live API key used).');
}
