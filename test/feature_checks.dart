// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pantry_logic/models.dart';
import 'package:pantry_logic/preferences.dart';
import 'package:pantry_logic/providers.dart';
import 'package:pantry_logic/grocery_aggregator.dart';
import 'package:pantry_logic/seed.dart';
import 'package:pantry_logic/side_seeds.dart';

void check(bool value, String label) {
  if (!value) throw StateError(label);
  print('PASS: $label');
}

Future<void> main() async {
  final prefs = Preferences()
    ..days = 3
    ..cadence = List.filled(7, 'flexible');
  final recipes = seedRecipes().indexed
      .map((e) => e.$2.withId(e.$1 + 1))
      .toList();
  final start = DateTime.utc(2026, 9, 14);
  final meals = FlexiblePlanner.plan(recipes, [], [], start, prefs, []);
  check(meals.length == 3, 'Variable menu length');
  prefs.family.add(FamilyMember('1', 'Dan', 'rice', 'chicken'));
  final filtered = FlexiblePlanner.plan(recipes, [], [], start, prefs, ['1']);
  check(
    filtered.every((r) => prefs.accepts(r, ['1'])),
    'Selected family dislikes applied',
  );
  check(
    Preferences.decode(prefs.encode()).family.single.name == 'Dan',
    'Preferences round trip',
  );
  final recipe = Recipe.fromJson({
    ...recipes.first.toJson(),
    'use_default_cooldown': true,
  });
  final history = [
    CookedMeal(1, recipe.id!, start.subtract(const Duration(days: 6))),
  ];
  prefs.cooldown = 10;
  check(
    !FlexiblePlanner.available(recipe, start, prefs, history, []),
    'Global cooldown enforced',
  );
  prefs.cooldown = 5;
  check(
    FlexiblePlanner.available(recipe, start, prefs, history, []),
    'Global cooldown configurable',
  );
  final explicit = Recipe.fromJson({
    ...recipe.toJson(),
    'use_default_cooldown': false,
    'cooldown_days': 12,
  });
  check(
    !FlexiblePlanner.available(explicit, start, prefs, history, []),
    'Recipe override takes priority',
  );
  final side = starterSides().first.withId(99);
  prefs.sideCooldown = 2;
  check(prefs.effectiveCooldown(side) == 2, 'Side cooldown independent');
  final plan = MealPlan(
    start: start,
    meals: meals,
    servings: 4,
    sides: {1: side},
    shoppingDays: {1},
    people: ['1'],
    guests: 3,
    cooldownOverrides: {1},
  );
  final decoded = MealPlan.decode(1, jsonEncode(plan.toJson()));
  check(
    decoded.shoppingRecipes.length == 2 &&
        decoded.guests == 3 &&
        decoded.cooldownOverrides.contains(1),
    'Shopping subset includes sides and preserves participants/override',
  );
  final legacy = MealPlan.decode(
    1,
    jsonEncode({
      'start': dateLabel(start),
      'meals': meals.map((r) => r.toJson()).toList(),
      'servings': 2,
    }),
  );
  check(
    legacy.shoppingDays.length == 3 && legacy.sides.isEmpty,
    'Legacy plan compatibility',
  );
  check(
    !birthdayDue(DateTime(2026, 5, 14), 2025) &&
        birthdayDue(DateTime(2026, 5, 15), 2025) &&
        birthdayDue(DateTime(2026, 9, 15), 2025) &&
        !birthdayDue(DateTime(2026, 9, 15), 2026),
    'Birthday boundary, catch-up and once annually',
  );
  final units = Recipe(
    title: 'Units',
    protein: 'other',
    ingredients: [
      Ingredient(name: 'flour', quantity: 1, unit: 'lb'),
      Ingredient(name: 'flour', quantity: 100, unit: 'g'),
      Ingredient(name: 'flour', quantity: 1, unit: 'US cup'),
    ],
    instructions: ['Mix'],
  );
  final groceries = GroceryAggregator.consolidate([units], 2);
  check(
    groceries.length == 2 &&
        (groceries.firstWhere((i) => i.unit == 'g').quantity - 553.59237)
                .abs() <
            0.0001,
    'Imperial weight conversion; dimensions stay separate',
  );
  for (final provider in ['OpenAI', 'Claude', 'Grok']) {
    final ai = ProviderService(
      provider: provider,
      apiKey: 'test-secret',
      model: providerModels[provider]!,
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map;
        check(
          !request.url.toString().contains('test-secret'),
          '$provider key is not in URL',
        );
        check(jsonEncode(body).contains('base64'), '$provider image included');
        final output = jsonEncode(recipe.toJson());
        final response = provider == 'OpenAI'
            ? {
                'output': [
                  {
                    'type': 'message',
                    'content': [
                      {'type': 'output_text', 'text': output},
                    ],
                  },
                ],
              }
            : provider == 'Claude'
            ? {
                'content': [
                  {'type': 'text', 'text': output},
                ],
              }
            : {
                'choices': [
                  {
                    'message': {'content': output},
                  },
                ],
              };
        return http.Response(jsonEncode(response), 200);
      }),
    );
    check(
      (await ai.parseRecipe(
            'recipe',
            image: Uint8List.fromList([1, 2, 3]),
          )).title ==
          recipe.title,
      '$provider recipe response',
    );
  }
  var backups = 0;
  final first = ProviderService(
    provider: 'Gemini',
    apiKey: 'test',
    model: 'missing',
    client: MockClient((_) async => http.Response('{}', 404)),
  );
  final second = ProviderService(
    provider: 'Grok',
    apiKey: 'test',
    model: 'test',
    client: MockClient((_) async {
      backups++;
      return http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': jsonEncode(recipe.toJson())},
            },
          ],
        }),
        200,
      );
    }),
  );
  check(
    (await FallbackService([first, second]).parseRecipe('recipe')).title ==
            recipe.title &&
        backups == 1,
    'Fallback after unavailable model',
  );
  try {
    await FallbackService([first]).parseRecipe('recipe');
    throw StateError('Expected error');
  } on FormatException catch (e) {
    check(
      e.message.contains('model') && backups == 1,
      'Disabled fallback preserves model error',
    );
  }
}
