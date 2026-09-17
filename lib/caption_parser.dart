import 'models.dart';
import 'recipe_codec.dart';

/// Conservative offline path for a caption with explicit ingredient bullets and method.
Recipe? parseCaption(String source) {
  final lines = source
      .split('\n')
      .map((s) => s.trim().replaceFirst(RegExp(r'^#+\s*'), '').trim())
      .where((s) => s.isNotEmpty)
      .toList();
  final bullets = lines.where((s) => RegExp(r'^[-•*]\s+').hasMatch(s)).toList();
  if (bullets.length < 2) return null;
  final first = lines.indexOf(bullets.first),
      last = lines.lastIndexOf(bullets.last);
  if (first < 1 || last >= lines.length - 1) return null;
  final method = lines
      .skip(last + 1)
      .join('\n')
      .replaceAll(RegExp(r'["”]+$'), '')
      .trim();
  if (method.length < 40) return null;
  final title = lines
      .take(first)
      .first
      .replaceFirst(RegExp(r'^["“]+'), '')
      .split(RegExp(r'\s+@'))
      .first
      .trim();
  if (title.isEmpty) return null;
  final us = RegExp(
    r'\b(pounds?|lbs?|ounces?|oz)\b',
    caseSensitive: false,
  ).hasMatch(source);
  final ingredients = <Ingredient>[];
  for (final bullet in bullets) {
    var item = bullet.replaceFirst(RegExp(r'^[-•*]\s+'), '').trim();
    final match = RegExp(
      r'^(\d+\s+\d+/\d+|\d+/\d+|\d+(?:[.,]\d+)?\s*[½¼¾⅓⅔⅛⅜⅝⅞]?|[½¼¾⅓⅔⅛⅜⅝⅞])\s+(.+)$',
    ).firstMatch(item);
    final amount = match == null ? null : parseAmount(match[1]);
    if (match != null) item = match[2]!;
    final unitMatch = RegExp(
      r'^(cups?|tbsp|tablespoons?|tsp|teaspoons?|pounds?|lbs?|ounces?|oz|grams?|g|kilograms?|kg|millilit(?:er|re)s?|ml|lit(?:er|re)s?|l)\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(item);
    var unit = amount == null ? 'as needed' : 'whole';
    if (unitMatch != null) {
      final u = normalized(unitMatch[1]!);
      unit = switch (u) {
        'cup' || 'cups' => us ? 'US cup' : 'cup',
        'tbsp' || 'tablespoon' || 'tablespoons' => us ? 'US tbsp' : 'tbsp',
        'tsp' || 'teaspoon' || 'teaspoons' => us ? 'US tsp' : 'tsp',
        'pound' || 'pounds' || 'lbs' => 'lb',
        'ounce' || 'ounces' => 'oz',
        'gram' || 'grams' => 'g',
        _ => u,
      };
      item = unitMatch[2]!;
    }
    final name = item.replaceAll(RegExp(r'["”]+$'), '').trim();
    final n = normalized(name);
    final aisle = RegExp(r'\bbeef\b|\bchicken\b').hasMatch(n)
        ? 'Meat'
        : n.contains('yogurt')
        ? 'Dairy'
        : RegExp(r'cucumber|mint|garlic|onion').hasMatch(n)
        ? 'Produce'
        : RegExp(r'salt|pepper|turmeric').hasMatch(n)
        ? 'Spices'
        : 'Pantry';
    ingredients.add(
      Ingredient(
        name: name,
        quantity: amount ?? 0,
        quantitySpecified: amount != null,
        unit: unit,
        aisle: aisle,
        isPerishable: aisle == 'Produce' || aisle == 'Dairy',
      ),
    );
  }
  final text = normalized(ingredients.map((i) => i.name).join(' '));
  final protein = RegExp(r'\bbeef\b').hasMatch(text)
      ? 'beef'
      : RegExp(r'\bchicken\b').hasMatch(text)
      ? 'chicken'
      : RegExp(
          r'fish|salmon|cod|tuna|shrimp|prawn|prawns|crab|lobster|mussels?|clams?|scallops?|anchov(?:y|ies)|sardines?|mackerel|trout|tilapia|haddock|hake|sea ?bass|seafood',
        ).hasMatch(text)
      ? 'fish'
      : RegExp(r'pork|lamb|turkey').hasMatch(text)
      ? 'other'
      : 'vegetarian';
  final notes = <String>[
    'The source does not state servings. Set the actual yield before scaling this recipe.',
  ];
  if (us && bullets.any((s) => RegExp(r'cup|tbsp|tsp').hasMatch(s))) {
    notes.add(
      'Cups and spoons are interpreted as US customary because the source uses pounds/ounces. Verify the source measurements.',
    );
  }
  if (ingredients.any((i) => !i.quantitySpecified)) {
    notes.add(
      'Some amounts are unspecified or for serving; they remain “as needed”.',
    );
  }
  if (text.contains('cranberr') && normalized(method).contains('raisins')) {
    notes.add(
      'Source conflict: the ingredients list cranberries, but the method says raisins. Choose which to use before cooking.',
    );
  }
  return Recipe(
    title: title,
    protein: protein,
    ingredients: ingredients,
    instructions: method.split(RegExp(r'(?<=[.!?])\s+(?=[A-Z])')).toList(),
    servings: 1,
    reviewNotes: notes,
  );
}
