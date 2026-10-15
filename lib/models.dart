import 'dart:convert';
import 'ingredient_identity.dart';

const proteins = ['chicken', 'beef', 'fish', 'vegetarian', 'other'];
String normalized(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
DateTime day(DateTime d) => DateTime.utc(d.year, d.month, d.day);
String dateLabel(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class Ingredient {
  final String name, unit, aisle;
  String get canonicalId => IngredientIdentity.id(name);
  final double quantity;
  final bool isPerishable;
  final bool quantitySpecified;
  Ingredient({
    required this.name,
    required this.quantity,
    required this.unit,
    this.aisle = 'Pantry',
    this.isPerishable = false,
    this.quantitySpecified = true,
  }) {
    if (!IngredientIdentity.validName(name) ||
        unit.trim().isEmpty ||
        !quantity.isFinite ||
        quantity < 0 ||
        (quantitySpecified && quantity == 0)) {
      throw const FormatException(
        'Each ingredient needs a name, positive quantity, and unit.',
      );
    }
  }
  Map<String, dynamic> toJson() => {
    'canonical_id': canonicalId,
    'name': name,
    'quantity': quantity,
    'unit': unit,
    'aisle': aisle,
    'is_perishable': isPerishable,
    'quantity_specified': quantitySpecified,
  };
  factory Ingredient.fromJson(Map<String, dynamic> j) => Ingredient(
    name: j['name'] as String,
    quantity: (j['quantity'] as num).toDouble(),
    unit: j['unit'] as String,
    aisle: j['aisle'] as String? ?? 'Pantry',
    isPerishable: j['is_perishable'] as bool? ?? false,
    quantitySpecified: j['quantity_specified'] as bool? ?? true,
  );
}

class PantryItem {
  final int? id;
  final String name, unit;
  final double quantity;
  final bool quantitySpecified;

  PantryItem({
    this.id,
    required this.name,
    required this.quantity,
    required this.unit,
    this.quantitySpecified = true,
  }) {
    if (name.trim().isEmpty ||
        unit.trim().isEmpty ||
        !quantity.isFinite ||
        quantity < 0 ||
        (quantitySpecified && quantity == 0)) {
      throw const FormatException(
        'Pantry items need a name and, when supplied, a positive quantity.',
      );
    }
  }

  Ingredient get ingredient => Ingredient(
    name: name,
    quantity: quantity,
    unit: unit,
    quantitySpecified: quantitySpecified,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'quantity': quantity,
    'unit': unit,
    'quantity_specified': quantitySpecified,
  };

  factory PantryItem.fromJson(Map<String, dynamic> j) => PantryItem(
    id: j['id'] as int?,
    name: j['name'] as String,
    quantity: (j['quantity'] as num?)?.toDouble() ?? 0,
    unit: j['unit'] as String? ?? 'as needed',
    quantitySpecified: j['quantity_specified'] as bool? ?? true,
  );

  PantryItem withId(int value) =>
      PantryItem.fromJson({...toJson(), 'id': value});
}

class Recipe {
  final int? id;
  final String title, protein;
  final String? sourceUrl;
  final int servings, cooldownDays;
  final bool useDefaultCooldown, isSide;
  final int? targetFrequencyDays;
  final int? prepMinutes, cookMinutes;
  final List<Ingredient> ingredients;
  final List<String> instructions;
  final List<String> reviewNotes;
  Recipe({
    this.id,
    required this.title,
    required this.protein,
    required this.ingredients,
    required this.instructions,
    this.reviewNotes = const [],
    this.sourceUrl,
    this.servings = 2,
    this.cooldownDays = 18,
    this.useDefaultCooldown = true,
    this.isSide = false,
    this.targetFrequencyDays,
    this.prepMinutes,
    this.cookMinutes,
  }) {
    if (title.trim().isEmpty ||
        !proteins.contains(protein) ||
        servings < 1 ||
        cooldownDays < 0 ||
        (prepMinutes != null && prepMinutes! < 0) ||
        (cookMinutes != null && cookMinutes! < 0) ||
        (targetFrequencyDays != null && targetFrequencyDays! < 1) ||
        ingredients.isEmpty ||
        instructions.isEmpty ||
        instructions.any((s) => s.trim().isEmpty)) {
      throw const FormatException(
        'Recipe needs a title, valid protein, servings, ingredients and instructions.',
      );
    }
  }
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'protein': protein,
    'ingredients': ingredients.map((i) => i.toJson()).toList(),
    'instructions': instructions,
    'review_notes': reviewNotes,
    'source_url': sourceUrl,
    'servings': servings,
    'cooldown_days': cooldownDays,
    'use_default_cooldown': useDefaultCooldown,
    'is_side': isSide,
    'target_frequency_days': targetFrequencyDays,
    'prep_minutes': prepMinutes,
    'cook_minutes': cookMinutes,
  };
  factory Recipe.fromJson(Map<String, dynamic> j) => Recipe(
    id: j['id'] as int?,
    title: j['title'] as String,
    protein: j['protein'] as String,
    ingredients: (j['ingredients'] as List)
        .map((i) => Ingredient.fromJson(Map<String, dynamic>.from(i as Map)))
        .toList(),
    instructions: List<String>.from(j['instructions'] as List),
    reviewNotes: List<String>.from(j['review_notes'] as List? ?? []),
    sourceUrl: j['source_url'] as String?,
    servings: j['servings'] as int? ?? 2,
    cooldownDays: j['cooldown_days'] as int? ?? 18,
    useDefaultCooldown:
        j['use_default_cooldown'] as bool? ??
        (j['cooldown_days'] == null || j['cooldown_days'] == 18),
    isSide: j['is_side'] as bool? ?? false,
    targetFrequencyDays: j['target_frequency_days'] as int?,
    prepMinutes: j['prep_minutes'] as int?,
    cookMinutes: j['cook_minutes'] as int?,
  );
  Recipe withId(int id) => Recipe.fromJson({...toJson(), 'id': id});
}

class CookedMeal {
  final int id, recipeId;
  final DateTime date;
  CookedMeal(this.id, this.recipeId, this.date);
}

class MealPlan {
  final int? id;
  final DateTime start;
  final List<Recipe> meals;
  final int servings;
  final Set<String> checked;
  final Map<String, Ingredient> shoppingOverrides;
  final List<Ingredient> manualShoppingItems;
  final Map<int, Recipe> sides;
  final Set<int> shoppingDays;
  final List<String> people;
  final int guests;
  final Set<int> cooldownOverrides;
  MealPlan({
    this.id,
    required this.start,
    required this.meals,
    required this.servings,
    Set<String>? checked,
    Map<String, Ingredient>? shoppingOverrides,
    List<Ingredient>? manualShoppingItems,
    Map<int, Recipe>? sides,
    Set<int>? shoppingDays,
    this.people = const [],
    this.guests = 0,
    Set<int>? cooldownOverrides,
  }) : shoppingOverrides = shoppingOverrides ?? {},
       manualShoppingItems = manualShoppingItems ?? [],
       checked = checked ?? {},
       sides = sides ?? {},
       shoppingDays =
           shoppingDays ?? Set.of(List.generate(meals.length, (i) => i)),
       cooldownOverrides = cooldownOverrides ?? {};
  List<Recipe> get shoppingRecipes => [
    for (final i in shoppingDays.toList()..sort()) ...[
      meals[i],
      if (sides[i] != null) sides[i]!,
    ],
  ];
  Map<String, dynamic> toJson() => {
    'sides': {for (final e in sides.entries) '${e.key}': e.value.toJson()},
    'shopping_days': shoppingDays.toList(),
    'people': people,
    'guests': guests,
    'cooldown_overrides': cooldownOverrides.toList(),
    'start': dateLabel(start),
    'meals': meals.map((r) => r.toJson()).toList(),
    'servings': servings,
    'checked': checked.toList(),
    'shopping_overrides': {
      for (final e in shoppingOverrides.entries) e.key: e.value.toJson(),
    },
    'manual_shopping_items': manualShoppingItems
        .map((i) => i.toJson())
        .toList(),
  };
  factory MealPlan.decode(int id, String value) {
    final j = jsonDecode(value) as Map<String, dynamic>;
    return MealPlan(
      id: id,
      start: day(DateTime.parse(j['start'] as String)),
      meals: (j['meals'] as List)
          .map((r) => Recipe.fromJson(Map<String, dynamic>.from(r as Map)))
          .toList(),
      servings: j['servings'] as int,
      checked: Set<String>.from(j['checked'] as List? ?? []),
      shoppingOverrides: {
        for (final e in (j['shopping_overrides'] as Map? ?? {}).entries)
          e.key as String: Ingredient.fromJson(
            Map<String, dynamic>.from(e.value as Map),
          ),
      },
      manualShoppingItems: [
        for (final i in j['manual_shopping_items'] as List? ?? [])
          Ingredient.fromJson(Map<String, dynamic>.from(i as Map)),
      ],
      sides: {
        for (final e in (j['sides'] as Map? ?? {}).entries)
          int.parse(e.key as String): Recipe.fromJson(
            Map<String, dynamic>.from(e.value as Map),
          ),
      },
      shoppingDays: j['shopping_days'] == null
          ? null
          : Set<int>.from(j['shopping_days'] as List),
      people: List<String>.from(j['people'] as List? ?? []),
      guests: j['guests'] as int? ?? 0,
      cooldownOverrides: Set<int>.from(j['cooldown_overrides'] as List? ?? []),
    );
  }
}
