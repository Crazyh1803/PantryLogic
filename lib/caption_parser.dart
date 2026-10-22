import 'models.dart';
import 'ingredient_identity.dart';
import 'recipe_codec.dart';

/// Conservative offline path for explicit recipe sections or ingredient bullets.
Recipe? parseCaption(String source) {
  final lines = source
      .split('\n')
      .map((s) => s.trim().replaceFirst(RegExp(r'^#+\s*'), '').trim())
      .where((s) => s.isNotEmpty)
      .toList();
  bool bullet(String s) => RegExp(r'^[-•*]\s+').hasMatch(s);
  bool heading(String s) => RegExp(
    r'^(?:instructions|directions|method|preparation|steps)(?:\s*:)?$',
    caseSensitive: false,
  ).hasMatch(s);
  final ingredientHeading = lines.indexWhere(
    (line) => RegExp(r'^ingredients\s*:$', caseSensitive: false).hasMatch(line),
  );
  final sectionMethod = ingredientHeading < 0
      ? -1
      : lines.indexWhere(heading, ingredientHeading + 1);
  final explicitSections =
      ingredientHeading >= 1 && sectionMethod > ingredientHeading;
  final first = explicitSections
      ? ingredientHeading + 1
      : lines.indexWhere(bullet);
  if (first < 1) return null;
  final bullets = <String>[];
  var end = first;
  if (explicitSections) {
    // Only accept an unambiguous bounded list. Subsections need AI interpretation.
    bullets.addAll(lines.sublist(first, sectionMethod));
    if (bullets.any((line) => line.endsWith(':'))) return null;
    end = sectionMethod;
  } else {
    while (end < lines.length &&
        bullet(lines[end]) &&
        !heading(lines[end].replaceFirst(RegExp(r'^[-•*]\s+'), ''))) {
      bullets.add(lines[end++]);
    }
  }
  if (bullets.length < 2 || end >= lines.length) return null;
  // A second ingredient group is ambiguous here; let structured ingestion
  // interpret it rather than silently treating sauce ingredients as steps.
  for (var index = end; index < lines.length - 1; index++) {
    final line = lines[index];
    if (!bullet(line) &&
        !heading(line) &&
        line.endsWith(':') &&
        bullet(lines[index + 1])) {
      return null;
    }
  }
  final sourceHeading = lines.indexWhere(
    (line) =>
        RegExp(r'^source(?: url)?\s*:', caseSensitive: false).hasMatch(line),
    end,
  );
  final methodEnd = sourceHeading < 0 ? lines.length : sourceHeading;
  final sourceUrl = sourceHeading < 0
      ? null
      : RegExp(
          r'https://[^\s)\]>]+',
        ).firstMatch(lines.skip(sourceHeading).join(' '))?.group(0);
  final methodLines = lines
      .sublist(end, methodEnd)
      .where((s) => !heading(s))
      .map((s) => s.replaceFirst(RegExp(r'^(?:[-•*]|\d+\\?[.)])\s+'), ''))
      .toList();
  if (methodLines.isNotEmpty) {
    methodLines[methodLines.length - 1] = methodLines.last
        .replaceAll(RegExp(r'["”]+$'), '')
        .trim();
  }
  final method = methodLines
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
  final compoundNotes = <String>[];
  for (final bullet in bullets) {
    var item = bullet.replaceFirst(RegExp(r'^[-•*]\s+'), '').trim();
    item = item.replaceFirstMapped(
      RegExp(r'^(\d+)\s*(?:&|and)\s*(\d+\s*/\s*\d+)\b'),
      (match) => '${match[1]} ${match[2]}',
    );
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
    final names = name.split(RegExp(r'\s+\+\s+'));
    if (names.any((name) => !IngredientIdentity.validName(name))) return null;
    for (var index = 0; index < names.length; index++) {
      final food = names[index];
      final foodAmount = index == 0 ? amount : null;
      final aisle = IngredientIdentity.category(food);
      ingredients.add(
        Ingredient(
          name: food,
          quantity: foodAmount ?? 0,
          quantitySpecified: foodAmount != null,
          unit: foodAmount == null ? 'as needed' : unit,
          aisle: aisle,
          isPerishable: aisle == 'Produce' || aisle == 'Dairy',
        ),
      );
    }
    if (names.length > 1) {
      compoundNotes.add(
        'Review the combined ingredient line "$bullet". The stated amount is assigned to ${names.first}; amounts for the other items are unspecified.',
      );
    }
  }

  final text = normalized(ingredients.map((i) => i.canonicalId).join(' '));
  final protein = RegExp(r'\bbeef\b').hasMatch(text)
      ? 'beef'
      : RegExp(r'\bchicken\b').hasMatch(text)
      ? 'chicken'
      : RegExp(
          r'fish|salmon|cod|tuna|shrimp|prawn|prawns|crab|lobster|mussels?|clams?|scallops?|anchov(?:y|ies)|sardines?|mackerel|trout|tilapia|haddock|hake|sea ?bass|seafood',
        ).hasMatch(text)
      ? 'fish'
      : RegExp(r'\b(?:pork|lamb|turkey|meat|mince)\b').hasMatch(text)
      ? 'other'
      : 'vegetarian';
  final metadata = lines.take(first).join('\n');
  final yieldMatch = RegExp(
    r'^(?:serves|servings)\s*:\s*(\d+)\s*$',
    caseSensitive: false,
    multiLine: true,
  ).firstMatch(metadata);
  final servings = yieldMatch == null ? null : int.tryParse(yieldMatch[1]!);
  int? minutes(String label) {
    final match = RegExp(
      '$label\\s*:\\s*(\\d+)\\s*(minutes?|mins?|m|hours?|hrs?|h)\\b',
      caseSensitive: false,
    ).firstMatch(metadata);
    if (match == null) return null;
    return int.parse(match[1]!) *
        (match[2]!.toLowerCase().startsWith('h') ? 60 : 1);
  }

  final notes = <String>[
    if (servings == null || servings < 1)
      'The source does not state servings. Set the actual yield before scaling this recipe.',
    ...compoundNotes,
    if (RegExp(r'\b(?:minced meat|meat mince)\b').hasMatch(text))
      'The source does not specify the type of minced meat. Review its protein category.',
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
    instructions: methodLines,
    servings: servings != null && servings > 0 ? servings : 1,
    prepMinutes: minutes('prep'),
    cookMinutes: minutes('cook'),
    sourceUrl: sourceUrl,
    reviewNotes: notes,
  );
}
