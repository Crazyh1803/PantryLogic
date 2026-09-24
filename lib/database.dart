import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'models.dart';
import 'grocery_aggregator.dart';
import 'preferences.dart';

// Drift custom queries keep the schema reviewable without generated source.
class AppDatabase extends GeneratedDatabase {
  AppDatabase(super.executor);
  static Future<AppDatabase> open() async {
    final dir = await getApplicationSupportDirectory();
    return AppDatabase(
      NativeDatabase.createInBackground(
        File(p.join(dir.path, 'pantry_logic.sqlite')),
      ),
    );
  }

  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await customStatement(
        'CREATE TABLE recipes (id INTEGER PRIMARY KEY AUTOINCREMENT, title_key TEXT NOT NULL UNIQUE, payload TEXT NOT NULL)',
      );
      await customStatement(
        'CREATE TABLE meal_history (id INTEGER PRIMARY KEY AUTOINCREMENT, recipe_id INTEGER NOT NULL REFERENCES recipes(id) ON DELETE CASCADE, cooked_date TEXT NOT NULL, UNIQUE(recipe_id,cooked_date))',
      );
      await customStatement(
        'CREATE TABLE weekly_plans (id INTEGER PRIMARY KEY AUTOINCREMENT, start_date TEXT NOT NULL UNIQUE, plan_json TEXT NOT NULL, shopping_list_json TEXT NOT NULL)',
      );
      await customStatement(
        'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
      );
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
  Future<List<Recipe>> recipes() async =>
      (await customSelect(
            'SELECT id,payload FROM recipes ORDER BY title_key',
          ).get())
          .map(
            (r) => Recipe.fromJson(
              jsonDecode(r.read<String>('payload')) as Map<String, dynamic>,
            ).withId(r.read<int>('id')),
          )
          .toList();
  Future<Recipe> saveRecipe(Recipe r) async {
    if (r.id == null) {
      final id = await customInsert(
        'INSERT INTO recipes (title_key,payload) VALUES (?,?)',
        variables: [
          Variable(normalized(r.title)),
          Variable(jsonEncode(r.toJson())),
        ],
      );
      return r.withId(id);
    }
    await customUpdate(
      'UPDATE recipes SET title_key=?,payload=? WHERE id=?',
      variables: [
        Variable(normalized(r.title)),
        Variable(jsonEncode(r.toJson())),
        Variable(r.id!),
      ],
    );
    return r;
  }

  Future<void> deleteRecipe(int id) =>
      customStatement('DELETE FROM recipes WHERE id=?', [id]);
  Future<List<CookedMeal>> history() async =>
      (await customSelect(
            'SELECT * FROM meal_history ORDER BY cooked_date DESC,id DESC',
          ).get())
          .map(
            (r) => CookedMeal(
              r.read<int>('id'),
              r.read<int>('recipe_id'),
              day(DateTime.parse(r.read<String>('cooked_date'))),
            ),
          )
          .toList();
  Future<void> markCooked(int id, DateTime date) => customStatement(
    'INSERT OR IGNORE INTO meal_history(recipe_id,cooked_date) VALUES (?,?)',
    [id, dateLabel(date)],
  );
  Future<void> undoCooked(int id) =>
      customStatement('DELETE FROM meal_history WHERE id=?', [id]);
  Future<List<MealPlan>> plans() async =>
      (await customSelect(
            'SELECT id,plan_json FROM weekly_plans ORDER BY start_date DESC',
          ).get())
          .map(
            (r) =>
                MealPlan.decode(r.read<int>('id'), r.read<String>('plan_json')),
          )
          .toList();
  Future<void> savePlan(MealPlan plan) async {
    if (plan.meals.isEmpty ||
        plan.meals.length > 14 ||
        plan.servings < 1 ||
        plan.servings > 40 ||
        plan.shoppingDays.any((i) => i < 0 || i >= plan.meals.length) ||
        plan.sides.keys.any((i) => i < 0 || i >= plan.meals.length)) {
      throw const FormatException('Invalid menu dates or servings.');
    }
    await customStatement(
      'INSERT INTO weekly_plans(start_date,plan_json,shopping_list_json) VALUES (?,?,?) ON CONFLICT(start_date) DO UPDATE SET plan_json=excluded.plan_json,shopping_list_json=excluded.shopping_list_json',
      [
        dateLabel(plan.start),
        jsonEncode(plan.toJson()),
        jsonEncode(
          GroceryAggregator.consolidate(
            plan.shoppingRecipes,
            plan.servings,
          ).map((i) => i.toJson()).toList(),
        ),
      ],
    );
  }
  Future<void> deletePlan(DateTime start) =>
      customStatement('DELETE FROM weekly_plans WHERE start_date=?', [dateLabel(start)]);

  Future<String?> setting(String key) async => (await customSelect(
    'SELECT value FROM settings WHERE key=?',
    variables: [Variable(key)],
  ).getSingleOrNull())?.read<String>('value');
  Future<void> setSetting(String key, String value) => customStatement(
    'INSERT OR REPLACE INTO settings(key,value) VALUES (?,?)',
    [key, value],
  );
  Future<String> export() async => const JsonEncoder.withIndent('  ').convert({
    'version': 1,
    'preferences': await setting('preferences'),
    'profile': await setting('profile'),
    'servings': await setting('servings'),
    'recipes': (await recipes()).map((r) => r.toJson()).toList(),
    'history': (await history())
        .map((h) => {'recipe_id': h.recipeId, 'date': dateLabel(h.date)})
        .toList(),
    'plans': (await plans()).map((p) => p.toJson()).toList(),
  });
  Future<void> restore(String source) async {
    final j = jsonDecode(source) as Map<String, dynamic>;
    if (j['version'] != 1) {
      throw const FormatException('Unsupported backup version.');
    }
    final incoming = (j['recipes'] as List)
        .map((r) => Recipe.fromJson(Map<String, dynamic>.from(r as Map)))
        .toList();
    if (j['preferences'] != null) {
      Preferences.decode(j['preferences'] as String);
    }
    await transaction(() async {
      final existing = {
        for (final r in await recipes()) normalized(r.title): r,
      };
      final ids = <int, int>{};
      for (final r in incoming) {
        final saved =
            existing[normalized(r.title)] ??
            await saveRecipe(Recipe.fromJson({...r.toJson(), 'id': null}));
        if (r.id != null) ids[r.id!] = saved.id!;
      }
      for (final h in j['history'] as List) {
        final id = ids[h['recipe_id']];
        if (id == null) {
          throw const FormatException('Backup references a missing recipe.');
        }
        await markCooked(id, DateTime.parse(h['date'] as String));
      }
      for (final raw in j['plans'] as List) {
        final plan = MealPlan.decode(0, jsonEncode(raw));
        if (plan.meals.isEmpty ||
            plan.meals.length > 14 ||
            plan.servings < 1 ||
            plan.servings > 40 ||
            plan.shoppingDays.any((i) => i < 0 || i >= plan.meals.length) ||
            plan.sides.keys.any((i) => i < 0 || i >= plan.meals.length)) {
          throw const FormatException(
            'Backup contains an invalid weekly plan.',
          );
        }
        final meals = plan.meals
            .map((r) => Recipe.fromJson({...r.toJson(), 'id': ids[r.id]}))
            .toList();
        await savePlan(
          MealPlan(
            start: plan.start,
            meals: meals,
            servings: plan.servings,
            checked: plan.checked,
            sides: {
              for (final e in plan.sides.entries)
                e.key: Recipe.fromJson({
                  ...e.value.toJson(),
                  'id': ids[e.value.id],
                }),
            },
            shoppingDays: plan.shoppingDays,
            people: plan.people,
            guests: plan.guests,
            cooldownOverrides: plan.cooldownOverrides,
          ),
        );
      }
      for (final key in ['preferences', 'profile', 'servings']) {
        if (j[key] is String) await setSetting(key, j[key] as String);
      }
    });
  }
}
