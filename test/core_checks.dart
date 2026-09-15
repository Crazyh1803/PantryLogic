// Can also run with: dart test/core_checks.dart (no Flutter runner required).
// ignore_for_file: avoid_relative_lib_imports, avoid_print
import '../lib/models.dart';
import '../lib/planning_engine.dart';
import '../lib/grocery_aggregator.dart';
import '../lib/seed.dart';

int checks = 0;
void check(bool condition, String label) {
  if (!condition) throw StateError('FAILED: $label');
  checks++;
  print('PASS: $label');
}

void main() {
  final start = DateTime.utc(2026, 9, 14);
  final library = seedRecipes().indexed
      .map((r) => r.$2.withId(r.$1 + 1))
      .toList();
  final recipe = library.first;
  check(
    !PlanningEngine.eligible(recipe, start, {
      recipe.id!: start.subtract(const Duration(days: 17)),
    }),
    '17 days remains blocked',
  );
  check(
    PlanningEngine.eligible(recipe, start, {
      recipe.id!: start.subtract(const Duration(days: 18)),
    }),
    'exactly 18 days is eligible',
  );
  final last = PlanningEngine.lastCooked([
    CookedMeal(1, recipe.id!, start.subtract(const Duration(days: 2))),
    CookedMeal(2, recipe.id!, start.subtract(const Duration(days: 50))),
  ], start);
  check(
    last[recipe.id] == start.subtract(const Duration(days: 2)),
    'newest history wins regardless of ordering',
  );
  final long = Recipe.fromJson({...recipe.toJson(), 'cooldown_days': 60});
  check(
    !PlanningEngine.eligible(long, start, {
      recipe.id!: start.subtract(const Duration(days: 45)),
    }),
    'cooldown longer than 30 days is enforced',
  );
  final plan = PlanningEngine.plan(library, [], start);
  check(
    plan.length == 7 && plan.map((r) => r.id).toSet().length == 7,
    'seven distinct meals',
  );
  check(
    plan[0].protein == 'chicken' &&
        plan[4].protein == 'chicken' &&
        plan[2].protein == 'beef' &&
        plan[3].protein == 'fish',
    'fixed protein cadence',
  );
  check(
    plan.any((r) => r.title == 'Ground beef tacos'),
    'never-cooked recurring anchor is included',
  );
  bool conflict = false;
  try {
    PlanningEngine.plan(library.take(4).toList(), [], start);
  } on PlanningException {
    conflict = true;
  }
  check(conflict, 'insufficient library fails explicitly');
  conflict = false;
  try {
    PlanningEngine.plan(
      library,
      [],
      start.add(const Duration(days: 7)),
      reservations: [MealPlan(start: start, meals: plan, servings: 2)],
    );
  } on PlanningException {
    conflict = true;
  }
  check(conflict, 'adjacent saved plan reserves recipes within cooldown');
  final a = Recipe(
    title: 'A',
    protein: 'vegetarian',
    ingredients: [
      Ingredient(name: ' Rice ', quantity: .5, unit: 'kg'),
      Ingredient(name: 'olive oil', quantity: 1, unit: 'tbsp'),
      Ingredient(name: 'rice', quantity: 1, unit: 'cup'),
    ],
    instructions: ['Cook.'],
  );
  final b = Recipe(
    title: 'B',
    protein: 'vegetarian',
    ingredients: [
      Ingredient(name: 'rice', quantity: 250, unit: 'g'),
      Ingredient(name: 'olive oil', quantity: 2, unit: 'tsp'),
    ],
    instructions: ['Cook.'],
  );
  final items = GroceryAggregator.consolidate([a, b], 4);
  check(
    items.firstWhere((i) => i.name == 'rice' && i.unit == 'g').quantity == 1500,
    'kg and g merge and servings scale',
  );
  check(
    items.firstWhere((i) => i.name == 'olive oil').quantity == 50,
    'spoon volumes merge deterministically',
  );
  check(
    items.any((i) => i.name == 'rice' && i.unit == 'cup' && i.quantity == 2),
    'incompatible units stay separate',
  );
  check(
    Recipe.fromJson(recipe.toJson()).title == recipe.title,
    'recipe JSON round trip',
  );
  check(
    MealPlan.decode(
      1,
      '{"start":"2026-09-14","meals":[],"servings":2,"checked":["rice|g"]}',
    ).checked.contains('rice|g'),
    'checklist JSON round trip',
  );
  print('$checks checks passed.');
}
