// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pantry_logic/ai_service.dart';
import 'package:pantry_logic/providers.dart';
import 'package:pantry_logic/caption_parser.dart';
import 'package:pantry_logic/recipe_codec.dart';
import 'package:pantry_logic/measurements.dart';
import 'package:pantry_logic/preferences.dart';
import 'package:pantry_logic/models.dart';
import 'package:pantry_logic/grocery_aggregator.dart';

void check(bool condition, String label) {
  if (!condition) throw StateError(label);
  print('PASS: $label');
}

Recipe recipe(int id, String protein) => Recipe(
  id: id,
  title: '$protein $id',
  protein: protein,
  cooldownDays: 0,
  useDefaultCooldown: false,
  ingredients: [Ingredient(name: 'test', quantity: 1, unit: 'g')],
  instructions: ['Cook'],
);
Future<void> main() async {
  final fixture = File.fromUri(
    Platform.script.resolve('kabob_caption.txt'),
  ).readAsStringSync();
  final kabob = parseCaption(fixture)!;
  check(
    kabob.ingredients.length == 13 && kabob.protein == 'beef',
    'Exact kabob caption imports all 13 ingredients',
  );
  check(
    kabob.ingredients[6].quantity == 0.5 &&
        kabob.ingredients[9].quantity == 0.25,
    'Unicode fractions retained',
  );
  check(
    kabob.ingredients.where((i) => !i.quantitySpecified).length == 3,
    'Pepper and optional serving ingredients remain unquantified',
  );
  check(
    kabob.reviewNotes.any(
      (n) => n.contains('cranberries') && n.contains('raisins'),
    ),
    'Source conflict flagged, not silently rewritten',
  );
  check(
    Recipe.fromJson(kabob.toJson()).reviewNotes.length ==
        kabob.reviewNotes.length,
    'Review notes survive serialization',
  );
  final neverCall = ProviderService(
    provider: 'Gemini',
    apiKey: '',
    model: '',
    client: MockClient(
      (_) async => throw StateError('Unexpected network request'),
    ),
  );
  check(
    (await RecipeImporter(neverCall).parse(fixture)).title == kabob.title,
    'Structured pasted caption imports without any AI key or network',
  );
  final normalized = decodeRecipe({
    'title': 'Example',
    'protein': 'Beef',
    'servings': 2.0,
    'ingredients': [
      {'name': 'flour', 'quantity': '1 ½', 'unit': 'US cup'},
      {'name': 'salt', 'quantity': null, 'unit': 'as needed'},
    ],
    'instructions': [
      {'text': 'Mix and cook.'},
    ],
  });
  check(
    normalized.servings == 2 && normalized.ingredients.first.quantity == 1.5,
    'AI numeric representations and structured steps normalized',
  );
  check(
    GroceryAggregator.consolidate([
          kabob,
        ], 1).where((i) => !i.quantitySpecified).length ==
        3,
    'Shopping list retains unspecified items',
  );
  final cup = Ingredient(name: 'flour', quantity: 1, unit: 'US cup');
  check(
    Measurements.format(cup, system: 'us', volumeStyle: 'kitchen') ==
        '1 US cup',
    'One cup stays a cup, not tablespoons',
  );
  check(
    Measurements.format(
          Ingredient(name: 'oil', quantity: 14.78676478125, unit: 'ml'),
          system: 'us',
          volumeStyle: 'kitchen',
        ) ==
        '1 US tbsp',
    'Small volume selects tablespoon',
  );
  check(
    Measurements.format(
          Ingredient(name: 'salt', quantity: 2.464460796875, unit: 'ml'),
          system: 'us',
          volumeStyle: 'kitchen',
        ) ==
        '½ US tsp',
    'Very small volume selects fractional teaspoon',
  );
  check(
    Measurements.format(cup, system: 'metric', volumeStyle: 'ml') ==
        '236.59 mL',
    'US cup converts to metric volume',
  );
  check(
    Measurements.format(
          Ingredient(name: 'beef', quantity: 1, unit: 'lb'),
          system: 'metric',
          volumeStyle: 'kitchen',
        ) ==
        '453.59 g',
    'Pound converts to grams',
  );
  check(
    Measurements.format(
          Ingredient(name: 'water', quantity: 284.130625, unit: 'ml'),
          system: 'uk',
          volumeStyle: 'kitchen',
        ) ==
        '1 UK imperial cup',
    'Imperial cup differs from US cup',
  );
  final mon = DateTime.utc(2026, 9, 14);
  final library = [
    recipe(1, 'beef'),
    recipe(2, 'beef'),
    for (var i = 3; i < 18; i++) recipe(i, 'vegetarian'),
  ];
  final prefs = Preferences()
    ..days = 3
    ..cooldown = 0
    ..weeklyLimits = {
      'beef': 1,
      'chicken': 0,
      'fish': 0,
      'vegetarian': null,
      'other': 0,
    };
  final first = MealPlan(
    start: mon,
    meals: FlexiblePlanner.plan(library, [], [], mon, prefs, []),
    servings: 2,
  );
  check(
    first.meals.where((r) => r.protein == 'beef').length == 1,
    'Three-day menu uses weekly beef allowance once',
  );
  final later = FlexiblePlanner.plan(
    library,
    [],
    [first],
    mon.add(const Duration(days: 3)),
    prefs,
    [],
  );
  check(
    later.every((r) => r.protein != 'beef'),
    'Later menu in same calendar week cannot reuse beef allowance',
  );
  final logs = [CookedMeal(1, first.meals.first.id!, mon)];
  check(
    FlexiblePlanner.weeklyCounts(library, logs, [first], mon)['beef'] == 1,
    'Logging a planned dinner does not double-count allowance',
  );
  final next = FlexiblePlanner.plan(
    library,
    [],
    [first],
    mon.add(const Duration(days: 7)),
    prefs,
    [],
  );
  check(
    next.any((r) => r.protein == 'beef'),
    'Weekly allowance resets on Monday',
  );
  prefs.days = 2;
  final crossing = FlexiblePlanner.plan(
    library,
    [],
    [first],
    mon.add(const Duration(days: 6)),
    prefs,
    [],
  );
  check(
    crossing[0].protein != 'beef' && crossing[1].protein == 'beef',
    'Sunday–Monday menu uses correct calendar buckets',
  );
  final updated = FlexiblePlanner.plan(library, [], [first], mon, prefs, []);
  check(
    updated.any((r) => r.protein == 'beef'),
    'Replacing a menu releases its old reservations',
  );
  final counts = FlexiblePlanner.weeklyCounts(
    library,
    [],
    [first],
    mon,
    excludingDate: mon,
  );
  check(counts['beef'] == 0, 'Replacement excludes the meal being replaced');
  check(
    Preferences.decode(prefs.encode()).weeklyLimits['beef'] == 1,
    'Weekly limits persist',
  );
  var attempts = 0;
  final result = await guardedHttp(() async {
    attempts++;
    return http.Response('{}', attempts < 3 ? 503 : 200);
  }, retryDelay: Duration.zero);
  check(
    result.statusCode == 200 && attempts == 3,
    '503 is retried twice with bounded retry loop',
  );
  attempts = 0;
  await guardedHttp(() async {
    attempts++;
    return http.Response('{}', 400);
  }, retryDelay: Duration.zero);
  check(attempts == 1, '400 is not retried');
  final msg = providerError(
    'Claude',
    http.Response(
      jsonEncode({
        'error': {'message': 'Invalid model my-secret sk-another-secret'},
      }),
      400,
    ),
    'my-secret',
    'custom',
  );
  check(
    msg.contains('Invalid model') &&
        !msg.contains('my-secret') &&
        !msg.contains('sk-another-secret'),
    'Server error detail retained and keys redacted',
  );
  final gemini = ProviderService(
    provider: 'Gemini',
    apiKey: 'test',
    model: 'models/custom-model',
    client: MockClient((r) async {
      check(
        r.url.path.endsWith('/custom-model:generateContent'),
        'Custom Gemini model is honored, including models/ prefix',
      );
      return http.Response(
        jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': jsonEncode(recipe(1, 'beef').toJson())},
                ],
              },
            },
          ],
        }),
        200,
      );
    }),
  );
  await gemini.parseRecipe('test');
  final claude = ProviderService(
    provider: 'Claude',
    apiKey: 'test',
    model: 'custom-claude',
    client: MockClient((r) async {
      final body = jsonDecode(r.body);
      check(
        body['tool_choice']['name'] == 'save_recipe' &&
            body['tools'][0]['input_schema']['additionalProperties'] == false,
        'Claude requests a structured recipe tool result',
      );
      return http.Response(
        jsonEncode({
          'content': [
            {
              'type': 'tool_use',
              'name': 'save_recipe',
              'input': recipe(1, 'beef').toJson(),
            },
          ],
        }),
        200,
      );
    }),
  );
  check(
    (await claude.parseRecipe('test')).protein == 'beef',
    'Claude tool result is importable',
  );
  final openai = ProviderService(
    provider: 'OpenAI',
    apiKey: 'test',
    model: 'custom-openai',
    client: MockClient((r) async {
      final b = jsonDecode(r.body);
      check(
        b['text']['format']['type'] == 'json_schema' &&
            b['text']['format']['strict'] == true,
        'OpenAI uses strict structured outputs',
      );
      return http.Response(
        jsonEncode({
          'output': [
            {
              'type': 'message',
              'content': [
                {'type': 'output_text', 'text': jsonEncode(kabob.toJson())},
              ],
            },
          ],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }),
  );
  check(
    (await openai.parseRecipe('test')).ingredients.length == 13,
    'OpenAI result accepts complete caption recipe',
  );
  final models = ProviderService(
    provider: 'Gemini',
    apiKey: 'test',
    model: 'anything',
    client: MockClient(
      (r) async => http.Response(
        jsonEncode({
          'models': [
            {
              'name': 'models/actual-model',
              'supportedGenerationMethods': ['generateContent'],
            },
            {
              'name': 'models/embedding',
              'supportedGenerationMethods': ['embedContent'],
            },
          ],
        }),
        200,
      ),
    ),
  );
  check(
    (await models.availableModels()).single == 'actual-model',
    'Model picker uses available generation models',
  );
}
