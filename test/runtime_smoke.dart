// Direct engine smoke test for restricted build hosts.
import 'dart:ffi';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:sqlite3/open.dart';
import 'package:pantry_logic/database.dart';
import 'package:pantry_logic/models.dart';
import 'package:pantry_logic/seed.dart';
import 'package:pantry_logic/planning_engine.dart';
import 'package:pantry_logic/preferences.dart';
import 'package:pantry_logic/side_seeds.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dll = Platform.environment['PANTRY_LOGIC_TEST_SQLITE'];
  if (dll != null) {
    open.overrideFor(OperatingSystem.windows, () => DynamicLibrary.open(dll));
  }
  final db = AppDatabase(NativeDatabase.memory());
  final copy = AppDatabase(NativeDatabase.memory());
  try {
    final recipes = <Recipe>[];
    for (final r in seedRecipes()) {
      recipes.add(await db.saveRecipe(r));
    }
    final week = MealPlan(
      start: DateTime.utc(2026, 9, 14),
      meals: PlanningEngine.plan(recipes, [], DateTime.utc(2026, 9, 14)),
      servings: 4,
      checked: {'rice|g'},
    );
    await db.savePlan(week);
    final side = await db.saveRecipe(starterSides().first);
    final metadata = await db.saveRecipe(
      Recipe(
        title: 'Metadata round trip',
        protein: 'vegetarian',
        prepMinutes: 5,
        cookMinutes: 20,
        reviewNotes: ['Check the source yield.'],
        sourceUrl: 'https://recipes.example/test',
        ingredients: [
          Ingredient(
            name: 'salt',
            quantity: 0,
            quantitySpecified: false,
            unit: 'as needed',
          ),
        ],
        instructions: ['Season to taste.'],
      ),
    );
    final short = MealPlan(
      start: DateTime.utc(2027, 1, 1),
      meals: week.meals.take(3).toList(),
      servings: 5,
      sides: {1: side},
      shoppingDays: {1},
      people: ['dan'],
      guests: 4,
      cooldownOverrides: {1},
    );
    await db.savePlan(short);
    final prefs = Preferences()..region = 'Germany';
    await db.setSetting('preferences', prefs.encode());
    await db.markCooked(recipes.first.id!, week.start);
    await db.markCooked(recipes.first.id!, week.start);
    if ((await db.history()).length != 1) throw StateError('Duplicate history');
    await copy.restore(await db.export());
    if ((await copy.recipes()).length != recipes.length + 2) {
      throw StateError('Recipe restore');
    }
    final restoredMetadata = (await copy.recipes()).singleWhere(
      (r) => r.title == metadata.title,
    );
    if (restoredMetadata.prepMinutes != 5 ||
        restoredMetadata.cookMinutes != 20 ||
        restoredMetadata.reviewNotes.single != 'Check the source yield.' ||
        restoredMetadata.ingredients.single.quantitySpecified ||
        restoredMetadata.sourceUrl != metadata.sourceUrl) {
      throw StateError('Recipe metadata restore');
    }
    if (!(await copy.plans()).last.checked.contains('rice|g')) {
      throw StateError('Checklist restore');
    }
    final restored = (await copy.plans()).first;
    if (restored.meals.length != 3 ||
        restored.shoppingRecipes.length != 2 ||
        restored.guests != 4 ||
        !restored.cooldownOverrides.contains(1) ||
        restored.sides[1]!.id == null) {
      throw StateError('Extended plan restore');
    }
    if (Preferences.decode(await copy.setting('preferences')).region !=
        'Germany') {
      throw StateError('Preferences restore');
    }
    if ((await copy.history()).length != 1) throw StateError('History restore');
    await db.deleteRecipe(recipes.first.id!);
    if ((await db.history()).isNotEmpty) {
      throw StateError('Foreign key cascade');
    }
    stdout.writeln(
      'PASS: SQLite CRUD, unique history, weekly plan, persistent checklist, backup restore, FK cascade',
    );
    await db.close();
    await copy.close();
    exit(0);
  } catch (e, stack) {
    stderr.writeln('$e\n$stack');
    await db.close();
    await copy.close();
    exit(1);
  }
}
