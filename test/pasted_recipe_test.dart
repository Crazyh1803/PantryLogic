import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pantry_logic/ai_service.dart';
import 'package:pantry_logic/caption_parser.dart';
import 'package:pantry_logic/features/recipes/services/recipe_ingestion_service.dart';

void main() {
  final source = File('test/potato_meat_pie.txt').readAsStringSync();
  test('pasted potato meat pie imports without an AI request', () async {
    var calls = 0;
    final ai = GeminiDirectService(
      apiKey: '',
      client: MockClient((_) async {
        calls++;
        return http.Response('{}', 503);
      }),
    );
    final recipe = await RecipeIngestionService(ai).ingest(blurb: source);
    expect(calls, 0);
    expect(recipe.title, 'Potato Meat Pie');
    expect(recipe.servings, 6);
    expect(recipe.prepMinutes, 30);
    expect(recipe.cookMinutes, 30);
    expect(recipe.protein, 'other');
    expect(recipe.sourceUrl, 'https://www.instagram.com/p/DQcKUa6CKQa/');
    expect(recipe.instructions, hasLength(6));
    expect(recipe.instructions.first, startsWith('Prepare the dough'));
    expect(recipe.instructions.last, contains('180°C'));
    expect(recipe.instructions.join(), isNot(contains('instagram')));
    final flour = recipe.ingredients.singleWhere(
      (i) => i.name.contains('flour'),
    );
    expect(flour.quantity, 1.5);
    expect(flour.unit, 'cup');
    final meat = recipe.ingredients.singleWhere((i) => i.name == 'minced meat');
    expect(meat.quantity, 0.5);
    expect(meat.unit, 'kg');
    expect(
      recipe.ingredients.singleWhere((i) => i.name == 'oil').quantitySpecified,
      isFalse,
    );
    expect(
      recipe.ingredients
          .singleWhere((i) => i.name == 'Shredded mozzarella cheese')
          .quantitySpecified,
      isFalse,
    );
    expect(
      recipe.reviewNotes.any((n) => n.contains('does not state servings')),
      isFalse,
    );
  });
  test('complete pasted text does not fetch a throttled source link', () async {
    var requests = 0;
    final scraper = MockClient((_) async {
      requests++;
      return http.Response('Throttled', 429);
    });
    final recipe = await RecipeIngestionService(
      GeminiDirectService(apiKey: ''),
      client: scraper,
    ).ingest(blurb: source, url: 'https://www.instagram.com/p/DQcKUa6CKQa/');
    expect(requests, 0);
    expect(recipe.title, 'Potato Meat Pie');
    expect(recipe.sourceUrl, 'https://www.instagram.com/p/DQcKUa6CKQa/');
  });
  test('ambiguous unbulleted ingredient sections defer to AI', () {
    expect(
      parseCaption('''Dinner
Ingredients:
100 g rice
For the sauce:
200 ml milk
Instructions:
Cook the rice until tender, prepare the sauce and serve everything warm.'''),
      isNull,
    );
  });
}
