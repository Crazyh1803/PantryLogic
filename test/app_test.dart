import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:pantry_logic/database.dart';
import 'package:pantry_logic/main.dart';
import 'package:pantry_logic/models.dart';
import 'package:pantry_logic/seed.dart';
import 'core_checks.dart' as core;

void main() {
  test('deterministic planning and grocery checks', core.main);
  test('SQLite transactions, history, plans and backup round trip', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final restored = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    addTearDown(restored.close);
    final r = await db.saveRecipe(seedRecipes().first);
    final rice = await db.savePantryItem(
      PantryItem(name: 'rice', quantity: 500, unit: 'g'),
    );
    final flour = await db.savePantryItem(
      PantryItem(name: 'flour', quantity: 100, unit: 'g'),
    );
    final merged = await db.savePantryItem(
      PantryItem(id: flour.id, name: 'rice', quantity: 750, unit: 'g'),
    );
    expect(merged.id, rice.id);
    expect((await db.pantryItems()).single.quantity, 750);
    await db.markCooked(r.id!, DateTime(2026, 9, 14));
    await db.markCooked(r.id!, DateTime(2026, 9, 14));
    expect((await db.history()).length, 1);
    await db.savePlan(
      MealPlan(
        start: DateTime(2026, 9, 14),
        meals: List.filled(7, r),
        servings: 4,
        checked: {'rice|g'},
      ),
    );
    await restored.restore(await db.export());
    expect((await restored.recipes()).single.title, r.title);
    expect((await restored.history()).length, 1);
    expect((await restored.plans()).single.checked, contains('rice|g'));
    expect((await restored.pantryItems()).single.name, 'rice');
    await db.deleteRecipe(r.id!);
    expect(await db.history(), isEmpty);
  });
  test('version 1 backup without pantry still restores', () async {
    final source = AppDatabase(NativeDatabase.memory());
    final restored = AppDatabase(NativeDatabase.memory());
    addTearDown(source.close);
    addTearDown(restored.close);
    await source.saveRecipe(seedRecipes().first);
    final backup = jsonDecode(await source.export()) as Map<String, dynamic>
      ..['version'] = 1
      ..remove('pantry');
    await restored.restore(jsonEncode(backup));
    expect((await restored.recipes()).single.title, seedRecipes().first.title);
    expect(await restored.pantryItems(), isEmpty);
  });
  test('version 1 database migrates pantry storage', () async {
    final raw = sqlite3.openInMemory();
    raw.execute(
      'CREATE TABLE recipes (id INTEGER PRIMARY KEY AUTOINCREMENT, title_key TEXT NOT NULL UNIQUE, payload TEXT NOT NULL)',
    );
    raw.execute(
      'CREATE TABLE meal_history (id INTEGER PRIMARY KEY AUTOINCREMENT, recipe_id INTEGER NOT NULL REFERENCES recipes(id) ON DELETE CASCADE, cooked_date TEXT NOT NULL, UNIQUE(recipe_id,cooked_date))',
    );
    raw.execute(
      'CREATE TABLE weekly_plans (id INTEGER PRIMARY KEY AUTOINCREMENT, start_date TEXT NOT NULL UNIQUE, plan_json TEXT NOT NULL, shopping_list_json TEXT NOT NULL)',
    );
    raw.execute(
      'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
    raw.execute('PRAGMA user_version = 1');
    raw.execute("INSERT INTO settings(key,value) VALUES ('profile','kept')");
    final migrated = AppDatabase(NativeDatabase.opened(raw));
    addTearDown(migrated.close);
    await migrated.savePantryItem(
      PantryItem(name: 'flour', quantity: 1, unit: 'kg'),
    );
    expect((await migrated.pantryItems()).single.name, 'flour');
    expect(await migrated.setting('profile'), 'kept');
  });
  testWidgets('manual recipe editor validates and saves', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: RecipeEditor(recipe: seedRecipes().first)),
    );
    expect(find.text('Make it a keeper.'), findsOneWidget);
    expect(find.text('Lemon chicken & herby rice'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
