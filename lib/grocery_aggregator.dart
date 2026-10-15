import 'models.dart';
import 'ingredient_identity.dart';

class GroceryAggregator {
  static const aisles = IngredientIdentity.aisles;
  static const conversions = <String, (String, double)>{
    'oz': ('g', 28.349523125),
    'ounce': ('g', 28.349523125),
    'ounces': ('g', 28.349523125),
    'lb': ('g', 453.59237),
    'lbs': ('g', 453.59237),
    'pound': ('g', 453.59237),
    'pounds': ('g', 453.59237),
    'us cup': ('ml', 236.5882365),
    'us tbsp': ('ml', 14.78676478125),
    'us tsp': ('ml', 4.92892159375),
    'uk cup': ('ml', 284.130625),
    'uk tbsp': ('ml', 17.7581640625),
    'uk tsp': ('ml', 5.919388020833333),
    'metric cup': ('ml', 250),
    'metric tbsp': ('ml', 15),
    'metric tsp': ('ml', 5),
    'us fl oz': ('ml', 29.5735295625),
    'uk fl oz': ('ml', 28.4130625),
    'uk pint': ('ml', 568.26125),
    'kg': ('g', 1000),
    'kilogram': ('g', 1000),
    'kilograms': ('g', 1000),
    'grams': ('g', 1),
    'gram': ('g', 1),
    'l': ('ml', 1000),
    'liter': ('ml', 1000),
    'litre': ('ml', 1000),
    'liters': ('ml', 1000),
    'litres': ('ml', 1000),
    'millilitres': ('ml', 1),
    'milliliter': ('ml', 1),
    'millilitre': ('ml', 1),
    'each': ('whole', 1),
    'count': ('whole', 1),
    'milliliters': ('ml', 1),
    'tsp': ('ml', 5),
    'teaspoon': ('ml', 5),
    'teaspoons': ('ml', 5),
    'tbsp': ('ml', 15),
    'tablespoon': ('ml', 15),
    'tablespoons': ('ml', 15),
    'cloves': ('clove', 1),
    'pieces': ('whole', 1),
    'piece': ('whole', 1),
    'g': ('g', 1),
    'ml': ('ml', 1),
  };
  static String key(Ingredient i) =>
      '${i.canonicalId}|${i.quantitySpecified ? conversions[normalized(i.unit)]?.$1 ?? normalized(i.unit) : 'unspecified'}';
  static String canonicalName(String value) => IngredientIdentity.name(value);

  static String normalizeKey(String value) {
    final split = value.lastIndexOf('|');
    if (split < 0) return value;
    final unit = normalized(value.substring(split + 1));
    return '${canonicalName(value.substring(0, split))}|${conversions[unit]?.$1 ?? unit}';
  }

  static List<Ingredient> forPlan(MealPlan plan, List<PantryItem> pantry) {
    final checked = plan.checked.map(normalizeKey).toSet();
    plan.checked
      ..clear()
      ..addAll(checked);
    final generated = consolidateWithoutPantry(
      plan.shoppingRecipes,
      plan.servings,
      pantry,
    );
    final items = <String, Ingredient>{};
    for (final i in generated) {
      final k = key(i);
      items[k] = plan.shoppingOverrides[k] ?? i;
    }
    // Keep explicit edits even when a meal or pantry update removes its source.
    for (final e in plan.shoppingOverrides.entries) {
      items[e.key] = e.value;
    }
    return _consolidateIngredients([
      ...items.values,
      ...plan.manualShoppingItems,
    ]);
  }

  static List<Ingredient> consolidate(List<Recipe> recipes, int servings) =>
      _consolidateIngredients([
        for (final recipe in recipes)
          for (final ingredient in recipe.ingredients)
            Ingredient(
              name: ingredient.name,
              quantity: ingredient.quantity * servings / recipe.servings,
              unit: ingredient.unit,
              aisle: ingredient.aisle,
              isPerishable: ingredient.isPerishable,
              quantitySpecified: ingredient.quantitySpecified,
            ),
      ]);

  static List<Ingredient> _consolidateIngredients(
    List<Ingredient> ingredients,
  ) {
    final result = <String, Ingredient>{};
    for (final i in ingredients) {
      final unit = normalized(i.unit);
      final conversion = conversions[unit] ?? (unit, 1.0);
      final item = Ingredient(
        name: canonicalName(i.name),
        quantity: i.quantity * conversion.$2,
        unit: conversion.$1,
        aisle: IngredientIdentity.category(i.name, fallback: i.aisle),
        isPerishable: i.isPerishable,
        quantitySpecified: i.quantitySpecified,
      );
      final k = key(item);
      final old = result[k];
      result[k] = Ingredient(
        name: item.name,
        quantity: item.quantity + (old?.quantity ?? 0),
        unit: item.unit,
        // Pick the same supported category regardless of recipe order.
        aisle:
            old == null ||
                aisles.indexOf(item.aisle) < aisles.indexOf(old.aisle)
            ? item.aisle
            : old.aisle,
        isPerishable: item.isPerishable || (old?.isPerishable ?? false),
        quantitySpecified: item.quantitySpecified,
      );
    }
    int rank(String aisle) =>
        aisles.contains(aisle) ? aisles.indexOf(aisle) : 99;
    return result.values.toList()..sort((a, b) {
      final c = rank(a.aisle).compareTo(rank(b.aisle));
      if (c != 0) return c;
      final name = a.name.compareTo(b.name);
      return name == 0 ? a.unit.compareTo(b.unit) : name;
    });
  }

  static List<Ingredient> withoutPantry(
    List<Ingredient> groceries,
    List<PantryItem> pantry,
  ) {
    final remaining = <Ingredient>[];
    for (final grocery in groceries) {
      var needed = grocery.quantity;
      var covered = false;
      final name = canonicalName(grocery.name);
      for (final stored in pantry.where(
        (item) => canonicalName(item.name) == name,
      )) {
        if (!grocery.quantitySpecified) {
          covered = true;
          break;
        }
        if (!stored.quantitySpecified) continue;
        final pantryUnit = normalized(stored.unit);
        final conversion = conversions[pantryUnit] ?? (pantryUnit, 1.0);
        if (conversion.$1 != normalized(grocery.unit)) continue;
        needed -= stored.quantity * conversion.$2;
      }
      if (covered || (grocery.quantitySpecified && needed <= 0)) continue;
      remaining.add(
        Ingredient(
          name: grocery.name,
          quantity: needed,
          unit: grocery.unit,
          aisle: grocery.aisle,
          isPerishable: grocery.isPerishable,
          quantitySpecified: grocery.quantitySpecified,
        ),
      );
    }
    return remaining;
  }

  static List<Ingredient> consolidateWithoutPantry(
    List<Recipe> recipes,
    int servings,
    List<PantryItem> pantry,
  ) => withoutPantry(consolidate(recipes, servings), pantry);
}
