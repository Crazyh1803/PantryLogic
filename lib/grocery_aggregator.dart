import 'models.dart';

class GroceryAggregator {
  static const aisles = [
    'Produce',
    'Meat',
    'Seafood',
    'Dairy',
    'Bakery',
    'Pantry',
    'Spices',
    'Frozen',
  ];
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
      '${canonicalName(i.name)}|${i.quantitySpecified ? normalized(i.unit) : 'unspecified'}';
  static String canonicalName(String value) {
    final n = normalized(value)
        .replaceAll(RegExp(r'\b(fresh|large|small|medium|ripe)\b'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    const aliases = {
      'tomatoes': 'tomato',
      'onions': 'onion',
      'peppers': 'pepper',
      'cucumbers': 'cucumber',
      'carrots': 'carrot',
      'potatoes': 'potato',
      'mushrooms': 'mushroom',
      'lemons': 'lemon',
      'limes': 'lime',
    };
    return aliases[n] ?? n;
  }
  static List<Ingredient> consolidate(List<Recipe> recipes, int servings) {
    final result = <String, Ingredient>{};
    for (final r in recipes) {
      for (final i in r.ingredients) {
        final unit = normalized(i.unit);
        final conversion = conversions[unit] ?? (unit, 1.0);
        final item = Ingredient(
          name: canonicalName(i.name),
          quantity: i.quantity * conversion.$2 * servings / r.servings,
          unit: conversion.$1,
          aisle: i.aisle,
          isPerishable: i.isPerishable,
          quantitySpecified: i.quantitySpecified,
        );
        final k = key(item);
        final old = result[k];
        result[k] = Ingredient(
          name: item.name,
          quantity: item.quantity + (old?.quantity ?? 0),
          unit: item.unit,
          aisle: old?.aisle ?? item.aisle,
          isPerishable: item.isPerishable || (old?.isPerishable ?? false),
          quantitySpecified: item.quantitySpecified,
        );
      }
    }
    int rank(String aisle) =>
        aisles.contains(aisle) ? aisles.indexOf(aisle) : 99;
    return result.values.toList()..sort((a, b) {
      final c = rank(a.aisle).compareTo(rank(b.aisle));
      return c == 0 ? a.name.compareTo(b.name) : c;
    });
  }
}
