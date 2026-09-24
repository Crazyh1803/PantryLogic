import 'dart:convert';
import 'models.dart';
import 'grocery_aggregator.dart';

class FamilyMember {
  String id, name, likes, dislikes;
  FamilyMember(this.id, this.name, this.likes, this.dislikes);
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'likes': likes,
    'dislikes': dislikes,
  };
  factory FamilyMember.fromJson(Map j) =>
      FamilyMember(j['id'], j['name'], j['likes'], j['dislikes']);
}

class Preferences {
  int days = 3, cooldown = 18, sideCooldown = 5;
  String region = '',
      stores = '',
      equipment = '',
      weightUnit = 'g',
      volumeUnit = 'ml';
  String provider = 'Gemini';
  String cookingSkill = 'comfortable';
  String measurementSystem = 'metric', volumeStyle = 'ml';
  Map<String, int?> weeklyLimits = {
    'chicken': 2,
    'beef': 1,
    'fish': 1,
    'vegetarian': null,
    'other': null,
  };
  bool fallback = false;
  bool darkMode = false;
  List<String> cadence = [
    'chicken',
    'flexible',
    'beef',
    'fish',
    'chicken',
    'flexible',
    'flexible',
  ];
  List<String> aisleOrder = [...GroceryAggregator.aisles];
  List<FamilyMember> family = [];
  int effectiveCooldown(Recipe r) => r.useDefaultCooldown
      ? (r.isSide ? sideCooldown : cooldown)
      : r.cooldownDays;
  String slot(DateTime date) => 'flexible';
  String context(List<String> ids) =>
      'Region: $region. Frequent stores: $stores. Available cooking equipment: $equipment. Cooking skill: $cookingSkill. ${family.where((m) => ids.contains(m.id)).map((m) => '${m.name}: likes ${m.likes}; dislikes ${m.dislikes}.').join(' ')}';
  bool accepts(Recipe r, List<String> ids) {
    final names = r.ingredients.map((i) => normalized(i.name)).join(' ');
    return !family
        .where((m) => ids.contains(m.id))
        .expand((m) => m.dislikes.split(','))
        .map(normalized)
        .where((s) => s.isNotEmpty)
        .any(names.contains);
  }

  String encode() => jsonEncode({
    'days': days,
    'cooldown': cooldown,
    'sideCooldown': sideCooldown,
    'region': region,
    'stores': stores,
    'equipment': equipment,
    'weightUnit': weightUnit,
    'volumeUnit': volumeUnit,
    'measurementSystem': measurementSystem,
    'volumeStyle': volumeStyle,
    'weeklyLimits': weeklyLimits,
    'provider': provider,
    'cookingSkill': cookingSkill,
    'fallback': fallback,
    'darkMode': darkMode,
    'cadence': cadence,
    'aisleOrder': aisleOrder,
    'family': family.map((m) => m.toJson()).toList(),
  });
  factory Preferences.decode(String? value) {
    final p = Preferences();
    if (value == null) return p;
    final j = jsonDecode(value) as Map;
    p.days = j['days'] ?? 3;
    p.cooldown = j['cooldown'] ?? 18;
    p.sideCooldown = j['sideCooldown'] ?? 5;
    p.region = j['region'] ?? '';
    p.stores = j['stores'] ?? '';
    p.equipment = j['equipment'] ?? '';
    p.weightUnit = j['weightUnit'] ?? 'g';
    p.volumeUnit = j['volumeUnit'] ?? 'ml';
    p.measurementSystem =
        j['measurementSystem'] ??
        (p.weightUnit == 'oz' || p.weightUnit == 'lb' ? 'us' : 'metric');
    p.volumeStyle =
        j['volumeStyle'] ??
        (p.volumeUnit == 'ml' || p.volumeUnit == 'l' ? 'ml' : 'kitchen');
    if (j['weeklyLimits'] is Map) {
      p.weeklyLimits = {
        for (final protein in proteins)
          protein: (j['weeklyLimits'] as Map)[protein] as int?,
      };
    }
    p.provider = j['provider'] ?? 'Gemini';
    p.cookingSkill = j['cookingSkill'] ?? 'comfortable';
    p.fallback = j['fallback'] ?? false;
    p.darkMode = j['darkMode'] == true;
    p.cadence = List<String>.from(j['cadence'] ?? p.cadence);
    p.aisleOrder = List<String>.from(j['aisleOrder'] ?? p.aisleOrder);
    p.family = (j['family'] as List? ?? [])
        .map((m) => FamilyMember.fromJson(m as Map))
        .toList();
    if (p.days < 1 ||
        p.days > 14 ||
        p.cooldown < 0 ||
        p.sideCooldown < 0 ||
        p.weeklyLimits.values.any((v) => v != null && (v < 0 || v > 7)) ||
        !['metric', 'us', 'uk'].contains(p.measurementSystem) ||
        !['ml', 'kitchen'].contains(p.volumeStyle) ||
        p.cadence.length != 7 ||
        p.cadence.any((s) => !['flexible', ...proteins].contains(s))) {
      throw const FormatException('Invalid planning preferences.');
    }
    return p;
  }
  Preferences();
}

bool birthdayDue(DateTime now, int lastYear) =>
    lastYear < now.year && !day(now).isBefore(DateTime.utc(now.year, 5, 15));

class FlexiblePlanner {
  static DateTime weekStart(DateTime date) =>
      day(date).subtract(Duration(days: date.weekday - 1));
  static Map<String, int> weeklyCounts(
    List<Recipe> library,
    List<CookedMeal> history,
    List<MealPlan> plans,
    DateTime date, {
    DateTime? replacing,
    DateTime? excludingDate,
  }) {
    final start = weekStart(date),
        end = weekStart(date).add(const Duration(days: 7));
    final byDate = <DateTime, String>{};
    final byId = {
      for (final r in [...library, ...plans.expand((p) => p.meals)])
        if (r.id != null) r.id!: r,
    };
    bool inWeek(DateTime d) =>
        !day(d).isBefore(start) &&
        day(d).isBefore(end) &&
        day(d) != excludingDate;
    for (final p in plans.where((p) => day(p.start) != replacing)) {
      for (final e in p.meals.indexed) {
        final d = day(p.start).add(Duration(days: e.$1));
        if (inWeek(d)) byDate[d] = e.$2.protein;
      }
    }
    final cooked = [...history]..sort((a, b) => a.id.compareTo(b.id));
    for (final h in cooked) {
      final r = byId[h.recipeId];
      if (r != null && !r.isSide && inWeek(h.date)) {
        byDate[day(h.date)] = r.protein;
      }
    }
    return {
      for (final p in proteins) p: byDate.values.where((v) => v == p).length,
    };
  }

  static int used(
    List<Recipe> chosen,
    DateTime start,
    DateTime date,
    String protein,
  ) => chosen.indexed
      .where(
        (e) =>
            e.$2.protein == protein &&
            weekStart(start.add(Duration(days: e.$1))) == weekStart(date),
      )
      .length;
  static bool available(
    Recipe r,
    DateTime date,
    Preferences prefs,
    List<CookedMeal> history,
    List<MealPlan> plans, {
    DateTime? replacing,
  }) {
    final dates = [
      ...history
          .where((h) => h.recipeId == r.id && r.id != null)
          .map((h) => h.date),
    ];
    for (final p in plans.where((p) => p.start != replacing)) {
      for (final e in p.meals.indexed) {
        if (normalized(e.$2.title) == normalized(r.title)) {
          dates.add(p.start.add(Duration(days: e.$1)));
        }
      }
      for (final e in p.sides.entries) {
        if (normalized(e.value.title) == normalized(r.title)) {
          dates.add(p.start.add(Duration(days: e.key)));
        }
      }
    }
    return dates.every(
      (d) =>
          day(date).difference(day(d)).inDays.abs() >=
          prefs.effectiveCooldown(r),
    );
  }

  static List<Recipe> plan(
    List<Recipe> library,
    List<CookedMeal> history,
    List<MealPlan> reservations,
    DateTime start,
    Preferences prefs,
    List<String> people,
  ) {
    final chosen = <Recipe>[];
    final end = day(start).add(Duration(days: prefs.days - 1));
    final anchors = library.where((r) {
      if (r.isSide ||
          r.targetFrequencyDays == null ||
          !prefs.accepts(r, people)) {
        return false;
      }
      final scheduled = reservations
          .where((p) => day(p.start) != day(start))
          .expand(
            (p) => p.meals.indexed
                .where((e) => e.$2.id == r.id)
                .map(
                  (e) =>
                      CookedMeal(-1, r.id!, p.start.add(Duration(days: e.$1))),
                ),
          );
      final previous =
          [...history, ...scheduled]
              .where((h) => h.recipeId == r.id && !day(h.date).isAfter(end))
              .map((h) => day(h.date))
              .toList()
            ..sort();
      return previous.isEmpty ||
          end.difference(previous.last).inDays >= r.targetFrequencyDays!;
    }).toList();
    var visits = 0;
    bool search(int index) {
      if (index == prefs.days) {
        return anchors.every((a) => chosen.any((r) => r.id == a.id));
      }
      if (anchors.where((a) => !chosen.any((r) => r.id == a.id)).length >
          prefs.days - index) {
        return false;
      }
      if (++visits > 200000) return false;
      final date = day(start).add(Duration(days: index));
      final counts = weeklyCounts(
        library,
        history,
        reservations,
        date,
        replacing: day(start),
      );
      final candidates = library
          .where(
            (r) =>
                !r.isSide &&
                prefs.accepts(r, people) &&
                (prefs.weeklyLimits[r.protein] == null ||
                    (counts[r.protein] ?? 0) +
                            used(chosen, start, date, r.protein) <
                        prefs.weeklyLimits[r.protein]!) &&
                !chosen.any(
                  (c) => normalized(c.title) == normalized(r.title),
                ) &&
                available(
                  r,
                  date,
                  prefs,
                  history,
                  reservations,
                  replacing: day(start),
                ),
          )
          .toList();
      double score(Recipe r) {
        final previous =
            history.where((h) => h.recipeId == r.id).map((h) => h.date).toList()
              ..sort();
        final elapsed = previous.isEmpty
            ? 10000
            : date.difference(previous.last).inDays;
        final due =
            r.targetFrequencyDays != null && elapsed >= r.targetFrequencyDays!;
        final fresh = chosen
            .expand((c) => c.ingredients)
            .where((i) => i.isPerishable)
            .map((i) => normalized(i.name))
            .toSet();
        final likes = prefs.family
            .where((m) => people.contains(m.id))
            .expand((m) => m.likes.split(','))
            .map(normalized)
            .where((s) => s.isNotEmpty)
            .toList();
        final ingredientText = r.ingredients
            .map((i) => normalized(i.name))
            .join(' ');
        return (due ? 100000 : 0) +
            (prefs.weeklyLimits[r.protein] != null
                ? 1000 *
                      (prefs.weeklyLimits[r.protein]! -
                          (counts[r.protein] ?? 0) -
                          used(chosen, start, date, r.protein))
                : 0) +
            likes.where(ingredientText.contains).length * 100 +
            elapsed.toDouble() +
            r.ingredients
                    .where((i) => fresh.contains(normalized(i.name)))
                    .length *
                20;
      }

      candidates.sort((a, b) => score(b).compareTo(score(a)));
      for (final r in candidates) {
        chosen.add(r);
        if (search(index + 1)) return true;
        chosen.removeLast();
      }
      return false;
    }

    if (!search(0)) {
      throw const FormatException(
        'No menu fits these dates, weekly protein limits, family dislikes and cooldowns. Existing menus and cooked dinners use this week’s allowance. Adjust limits or add recipes.',
      );
    }
    return chosen;
  }
}
