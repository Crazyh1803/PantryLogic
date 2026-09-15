import 'models.dart';

class PlanningException implements Exception {
  final String message;
  PlanningException(this.message);
  @override
  String toString() => message;
}

class PlanningEngine {
  static Map<int, DateTime> lastCooked(
    List<CookedMeal> history,
    DateTime before,
  ) {
    final result = <int, DateTime>{};
    for (final h in history) {
      if (day(h.date).isAfter(day(before))) continue;
      if (!result.containsKey(h.recipeId) ||
          h.date.isAfter(result[h.recipeId]!))
        result[h.recipeId] = day(h.date);
    }
    return result;
  }

  static bool eligible(Recipe r, DateTime date, Map<int, DateTime> last) =>
      last[r.id] == null ||
      day(date).difference(last[r.id]!).inDays >= r.cooldownDays;
  static List<Recipe> dueAnchors(
    List<Recipe> recipes,
    List<CookedMeal> history,
    DateTime start,
  ) {
    final last = lastCooked(history, start.add(const Duration(days: 6)));
    return recipes
        .where(
          (r) =>
              r.targetFrequencyDays != null &&
              (last[r.id] == null ||
                  day(start)
                          .add(const Duration(days: 6))
                          .difference(last[r.id]!)
                          .inDays >=
                      r.targetFrequencyDays!),
        )
        .toList();
  }

  // Exact fixed slots + three flexible slots. Search assigns anchors first,
  // then minimizes waste using adjacent fresh-ingredient overlap.
  static List<Recipe> plan(
    List<Recipe> recipes,
    List<CookedMeal> history,
    DateTime start, {
    List<MealPlan> reservations = const [],
  }) {
    final end = day(start).add(const Duration(days: 6));
    final effectiveHistory = [...history];
    for (final p in reservations) {
      if (day(p.start) == day(start)) continue;
      for (var i = 0; i < p.meals.length; i++) {
        if (p.meals[i].id != null)
          effectiveHistory.add(
            CookedMeal(-1, p.meals[i].id!, p.start.add(Duration(days: i))),
          );
      }
    }
    final anchors = dueAnchors(recipes, history, start);
    if (anchors.length > 7)
      throw PlanningException(
        'More than seven recurring recipes are due. Adjust their intervals before planning.',
      );
    const slots = [
      'chicken',
      'flexible',
      'beef',
      'fish',
      'chicken',
      'flexible',
      'flexible',
    ];
    final chosen = <Recipe>[];
    var visits = 0;
    bool available(Recipe r, DateTime date) {
      for (final h in effectiveHistory.where((h) => h.recipeId == r.id)) {
        final gap = day(date).difference(day(h.date)).inDays.abs();
        if (gap < r.cooldownDays ||
            r.targetFrequencyDays != null && gap < r.targetFrequencyDays!)
          return false;
      }
      return true;
    }

    bool search(int index) {
      if (++visits > 200000) return false;
      if (index == 7)
        return anchors.every((a) => chosen.any((r) => r.id == a.id));
      final remaining = anchors
          .where((a) => !chosen.any((r) => r.id == a.id))
          .length;
      if (remaining > 7 - index) return false;
      final date = day(start).add(Duration(days: index));
      final candidates = recipes
          .where(
            (r) =>
                !chosen.any(
                  (c) => normalized(c.title) == normalized(r.title),
                ) &&
                (slots[index] == 'flexible' || r.protein == slots[index]) &&
                available(r, date),
          )
          .toList();
      double score(Recipe r) {
        double value = anchors.any((a) => a.id == r.id) ? 10000 : 0;
        for (final previous in chosen.skip(
          chosen.length > 2 ? chosen.length - 2 : 0,
        )) {
          final fresh = previous.ingredients
              .where((i) => i.isPerishable)
              .map((i) => normalized(i.name))
              .toSet();
          value +=
              r.ingredients
                  .where(
                    (i) => i.isPerishable && fresh.contains(normalized(i.name)),
                  )
                  .length *
              20;
        }
        final last = lastCooked(history, end)[r.id];
        value += last == null ? 10 : end.difference(last).inDays / 100;
        return value;
      }

      candidates.sort((a, b) {
        final c = score(b).compareTo(score(a));
        return c == 0 ? a.title.compareTo(b.title) : c;
      });
      for (final r in candidates) {
        chosen.add(r);
        if (search(index + 1)) return true;
        chosen.removeLast();
      }
      return false;
    }

    if (!search(0))
      throw PlanningException(
        'No valid week fits the library, cooldowns and recurring recipes. Add more recipes (including chicken, beef and fish), or adjust recurring intervals. No rules were relaxed.',
      );
    validate(chosen, recipes, effectiveHistory, start, anchors: anchors);
    return chosen;
  }

  static void validate(
    List<Recipe> meals,
    List<Recipe> library,
    List<CookedMeal> history,
    DateTime start, {
    List<Recipe>? anchors,
  }) {
    if (meals.length != 7 ||
        meals.map((r) => normalized(r.title)).toSet().length != 7)
      throw PlanningException('A week must contain seven distinct recipes.');
    const fixed = {0: 'chicken', 2: 'beef', 3: 'fish', 4: 'chicken'};
    for (var i = 0; i < 7; i++) {
      final r = meals[i];
      if (fixed.containsKey(i) && r.protein != fixed[i])
        throw PlanningException('Protein cadence was not met.');
      final date = day(start).add(Duration(days: i));
      for (final h in history.where((h) => h.recipeId == r.id)) {
        if (date.difference(day(h.date)).inDays.abs() < r.cooldownDays)
          throw PlanningException('${r.title} is still on cooldown.');
      }
    }
    for (final a in anchors ?? dueAnchors(library, history, start)) {
      if (!meals.any((r) => r.id == a.id))
        throw PlanningException('Recurring recipe ${a.title} is missing.');
    }
  }

  static List<String> perishableNotes(List<Recipe> meals) {
    final uses = <String, List<int>>{};
    for (var d = 0; d < meals.length; d++) {
      for (final name
          in meals[d].ingredients
              .where((i) => i.isPerishable)
              .map((i) => normalized(i.name))
              .toSet()) {
        uses.putIfAbsent(name, () => []).add(d);
      }
    }
    return uses.entries.map((e) {
      final paired = e.value.any(
        (a) => e.value.any((b) => b > a && b - a <= 2),
      );
      return paired
          ? '${e.key}: shared within 2 days'
          : '${e.key}: buy only the amount needed or freeze leftovers';
    }).toList();
  }
}
