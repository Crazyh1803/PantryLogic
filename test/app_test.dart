import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
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
    await db.deleteRecipe(r.id!);
    expect(await db.history(), isEmpty);
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
