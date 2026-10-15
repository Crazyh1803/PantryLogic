import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:pantry_logic/caption_parser.dart';
import 'package:pantry_logic/database.dart';
import 'package:pantry_logic/grocery_aggregator.dart';
import 'package:pantry_logic/models.dart';
import 'package:pantry_logic/ingredient_identity.dart';
import 'package:pantry_logic/recipe_codec.dart';

Ingredient food(
  String name,
  double amount,
  String unit, {
  String aisle = 'Pantry',
}) => Ingredient(name: name, quantity: amount, unit: unit, aisle: aisle);
Recipe dinner(List<Ingredient> ingredients) => Recipe(
  title: 'Dinner',
  protein: 'beef',
  servings: 2,
  ingredients: ingredients,
  instructions: ['Cook until done.'],
);
Map<String, dynamic> wire(Object name, Object? quantity) => {
  'title': 'Dinner',
  'servings': 2,
  'protein': 'beef',
  'ingredients': [
    {'name': name, 'quantity': quantity, 'unit': 'g'},
  ],
  'instructions': ['Cook until done.'],
};

void main() {
  test('bulleted cooking steps stay in the method section', () {
    final recipe = parseCaption('''Beef dinner
Ingredients:
- 500 g ground beef
- 2 onions
Instructions:
- Heat the pan and cook the beef until browned.
- Add the onions and simmer for ten minutes before serving.''')!;
    expect(recipe.ingredients.map((i) => i.name), ['ground beef', 'onions']);
    expect(recipe.instructions, hasLength(2));
    expect(GroceryAggregator.consolidate([recipe], 1), hasLength(2));
  });
  test('ambiguous mixed bullets defer to structured ingestion', () {
    expect(
      parseCaption('''Dinner
- 500 g ground beef
- 2 onions
- Cook beef for ten minutes.
Serve with rice and enjoy this dinner together.'''),
      isNull,
    );
  });
  test('structured input rejects instruction names and malformed amounts', () {
    for (final name in [
      'Cook beef for 10 minutes',
      '1. Heat the pan',
      'Instructions',
      '',
      'rice\nStir well',
    ]) {
      expect(() => decodeRecipe(wire(name, 1)), throwsFormatException);
    }
    for (final amount in ['a bunch maybe', -1, double.infinity, double.nan]) {
      expect(() => decodeRecipe(wire('beef', amount)), throwsFormatException);
    }
    expect(() => decodeRecipe(wire(123, 1)), throwsFormatException);
    expect(
      decodeRecipe(wire('roast beef', 100)).ingredients.single.name,
      'roast beef',
    );
    expect(
      decodeRecipe(wire('salt', null)).ingredients.single.quantitySpecified,
      isFalse,
    );
    expect(decodeRecipe(wire('beef', '½')).ingredients.single.quantity, .5);
  });
  test(
    'aliases have stable IDs, deterministic categories and scaled totals',
    () {
      final ingredients = [
        food('ground beef', 500, 'g', aisle: 'Meats'),
        food('minced beef', .5, 'kg', aisle: 'Frozen'),
        food('Rinderhackfleisch', 1, 'lb'),
      ];
      expect(ingredients.map((i) => i.canonicalId).toSet(), {'ground beef'});
      final recipe = dinner(ingredients);
      final items = GroceryAggregator.consolidate([recipe, recipe], 4);
      expect(items.single.name, 'ground beef');
      expect(items.single.aisle, 'Meat');
      expect(items.single.quantity, closeTo(5814.36948, .00001));
      expect(
        GroceryAggregator.consolidate([
          dinner(ingredients.reversed.toList()),
        ], 2).single.aisle,
        'Meat',
      );
      expect(
        Ingredient.fromJson(ingredients.first.toJson()).canonicalId,
        'ground beef',
      );
      expect(food('ground turkey', 1, 'g').canonicalId, isNot('ground beef'));
    },
  );
  test(
    'aliases and categories work across produce, poultry, fish, dairy and staples',
    () {
      final groups = [
        ('courgette', 'zucchini', 'Produce'),
        ('aubergine', 'eggplant', 'Produce'),
        ('scallions', 'spring onion', 'Produce'),
        ('hähnchenbrust', 'chicken breasts', 'Meat'),
        ('turkey mince', 'ground turkey', 'Meat'),
        ('prawns', 'shrimp', 'Seafood'),
        ('greek yoghurt', 'greek yogurt', 'Dairy'),
        ('garbanzo beans', 'chickpeas', 'Pantry'),
        ('plain flour', 'all-purpose flour', 'Pantry'),
      ];
      for (final (first, second, aisle) in groups) {
        final item = GroceryAggregator.consolidate([
          dinner([
            food(first, 100, 'g', aisle: 'wrong'),
            food(second, .2, 'kg', aisle: 'Frozen'),
          ]),
        ], 2).single;
        expect(item.quantity, 300, reason: first);
        expect(item.aisle, aisle, reason: first);
        expect(
          food(first, 1, 'g').canonicalId,
          food(second, 1, 'g').canonicalId,
        );
      }
      expect(
        IngredientIdentity.id('coriander seeds'),
        isNot(IngredientIdentity.id('cilantro')),
      );
      expect(
        IngredientIdentity.id('canned tomatoes'),
        isNot(IngredientIdentity.id('tomato')),
      );
      expect(IngredientIdentity.category('beef stock'), 'Pantry');
      expect(IngredientIdentity.category('black pepper'), 'Spices');
      expect(IngredientIdentity.category('bell peppers'), 'Produce');
    },
  );
  test(
    'uncatalogued ingredients keep supported categories with deterministic conflict resolution',
    () {
      final a = food('romanesco', 1, 'whole', aisle: 'vegetables');
      final b = food('romanesco', 1, 'whole', aisle: 'Pantry');
      final first = GroceryAggregator.consolidate([
        dinner([a, b]),
      ], 2).single;
      final reversed = GroceryAggregator.consolidate([
        dinner([b, a]),
      ], 2).single;
      expect(first.aisle, 'Produce');
      expect(reversed.aisle, first.aisle);
    },
  );
  test(
    'compatible units merge; unknown cups, mass, volume and unspecified stay distinct',
    () {
      final items = GroceryAggregator.consolidate([
        dinner([
          food('milk', 1, 'litre'),
          food('milk', 500, 'millilitres'),
          food('milk', 1, 'cup'),
          food('milk', 1, 'g'),
          Ingredient(
            name: 'milk',
            quantity: 0,
            unit: 'as needed',
            quantitySpecified: false,
          ),
        ]),
      ], 2);
      expect(items, hasLength(4));
      expect(items.firstWhere((i) => i.unit == 'ml').quantity, 1500);
    },
  );
  test(
    'unspecified ingredients survive regeneration unless pantry covers them',
    () {
      final recipe = dinner([
        Ingredient(
          name: 'salt',
          quantity: 0,
          unit: 'as needed',
          quantitySpecified: false,
        ),
      ]);
      final plan = MealPlan(
        start: DateTime.utc(2026, 10, 12),
        meals: [recipe],
        servings: 2,
      );
      expect(GroceryAggregator.forPlan(plan, const []).single.name, 'salt');
      expect(
        GroceryAggregator.forPlan(plan, [
          PantryItem(name: 'salt', quantity: 10, unit: 'g'),
        ]),
        isEmpty,
      );
    },
  );
  test(
    'manual additions merge with generated items without losing quantity',
    () {
      final plan = MealPlan(
        start: DateTime.utc(2026, 10, 12),
        meals: [
          dinner([food('minced beef', 500, 'g')]),
        ],
        servings: 2,
        manualShoppingItems: [food('Rinderhackfleisch', .25, 'kg')],
      );
      expect(GroceryAggregator.forPlan(plan, const []).single.quantity, 750);
      expect(GroceryAggregator.forPlan(plan, const []).single.quantity, 750);
      expect(plan.manualShoppingItems.single.quantity, .25);
    },
  );
  test('pantry matches aliases using compatible quantities', () {
    final remaining = GroceryAggregator.consolidateWithoutPantry(
      [
        dinner([food('minced beef', 1, 'kg')]),
      ],
      2,
      [PantryItem(name: 'Rinderhackfleisch', quantity: 250, unit: 'g')],
    );
    expect(remaining.single.quantity, 750);
  });
  test(
    'regeneration is idempotent and edits/checks survive persistence and backup',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      final copy = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      addTearDown(copy.close);
      final recipe = await db.saveRecipe(
        dinner([food('minced beef', 500, 'g')]),
      );
      final plan = MealPlan(
        start: DateTime.utc(2026, 10, 12),
        meals: [recipe, recipe],
        servings: 2,
        shoppingDays: {0},
        checked: {'Rinderhackfleisch|kg'},
        shoppingOverrides: {'ground beef|g': food('ground beef', 750, 'g')},
        manualShoppingItems: [food('bread', 1, 'whole')],
      );
      final first = GroceryAggregator.forPlan(
        plan,
        const [],
      ).map((i) => i.toJson()).toList();
      expect(plan.checked, {'ground beef|g'});
      expect(
        GroceryAggregator.forPlan(
          plan,
          const [],
        ).map((i) => i.toJson()).toList(),
        first,
      );
      for (var n = 0; n < 2; n++) {
        await db.savePlan(plan);
      }
      final saved = (await db.plans()).single;
      expect(
        GroceryAggregator.forPlan(
          saved,
          const [],
        ).map((i) => i.toJson()).toList(),
        first,
      );
      expect(saved.checked, {'ground beef|g'});
      await copy.restore(await db.export());
      final restored = (await copy.plans()).single;
      expect(
        jsonEncode(restored.shoppingOverrides),
        jsonEncode(saved.shoppingOverrides),
      );
      expect(restored.manualShoppingItems.single.name, 'bread');
      expect(
        GroceryAggregator.forPlan(
          restored,
          const [],
        ).map((i) => i.toJson()).toList(),
        first,
      );
      saved.shoppingDays.clear();
      expect(GroceryAggregator.forPlan(saved, const []), hasLength(2));
    },
  );
}
