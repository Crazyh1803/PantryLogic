// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pantry_logic/ai_service.dart';
import 'package:pantry_logic/core/errors/ai_exception_handler.dart';
import 'package:pantry_logic/features/recipes/services/recipe_ingestion_service.dart';
import 'package:pantry_logic/models.dart';
import 'package:pantry_logic/providers.dart';

void check(bool value, String label) {
  if (!value) throw StateError(label);
  print('PASS: $label');
}

final sample = Recipe(
  title: 'Roasted carrots',
  protein: 'vegetarian',
  servings: 2,
  prepMinutes: 10,
  cookMinutes: 25,
  reviewNotes: ['Serve warm.'],
  ingredients: [Ingredient(name: 'carrots', quantity: 300, unit: 'g')],
  instructions: ['Roast until tender.'],
);

class SpyAI implements AIService {
  int calls = 0;
  String? text;
  Uint8List? bytes;
  String? mime;
  @override
  Future<Recipe> parseRecipe(
    String text, {
    Uint8List? image,
    String? mimeType,
  }) async {
    calls++;
    this.text = text;
    bytes = image;
    mime = mimeType;
    return sample;
  }

  @override
  Future<Recipe> compose({
    required String protein,
    required List<String> excludedTitles,
    required List<String> freshIngredients,
    required String profile,
  }) => throw UnimplementedError();
}

Future<void> main() async {
  for (final error in [
    const AiRequestException(429, 'secret'),
    Exception('RESOURCE_EXHAUSTED'),
    Exception('429'),
  ]) {
    check(
      AiExceptionHandler.describe(error).message ==
          'AI rate limit reached. Please wait about 30 seconds and try again.',
      'Rate limit maps to actionable message',
    );
  }
  for (final error in [
    const AiRequestException(401, 'secret'),
    Exception('UNAUTHENTICATED'),
    const AiRequestException(400, 'INVALID_ARGUMENT: API key not valid'),
  ]) {
    final mapped = AiExceptionHandler.describe(error);
    check(
      mapped.message ==
              'Invalid API key. Please check your key in Settings > AI Configuration.' &&
          mapped.action == AiErrorAction.settings,
      'Bad key offers Settings recovery',
    );
  }
  for (final error in [
    const SocketException('secret'),
    TimeoutException('secret'),
    http.ClientException('secret'),
  ]) {
    check(
      AiExceptionHandler.describe(error).message ==
          'Network connection issue. Please check your internet connection.',
      'Network failure is friendly',
    );
  }
  check(
    !AiExceptionHandler.describe(
      const AiRequestException(400, 'INVALID_ARGUMENT: invalid model'),
    ).message.startsWith('Invalid API key'),
    'Model 400 is not mislabeled as a key failure',
  );
  check(
    AiExceptionHandler.describe(
          const AiRequestException(403, 'secret'),
          fromLink: true,
        ).action ==
        AiErrorAction.settings,
    'Provider permissions are not mislabeled as scraping failures',
  );
  check(
    AiExceptionHandler.describe(StateError('technical stack secret')).message ==
        "We couldn't parse that recipe. Try pasting the text directly.",
    'Unexpected errors never expose internal detail',
  );
  check(
    AiExceptionHandler.describe(
      const AiRequestException(503, 'secret'),
    ).message.contains('busy'),
    'Exhausted server retries have friendly recovery',
  );
  final spy = SpyAI();
  final blocked = RecipeIngestionService(
    spy,
    client: MockClient((_) async => http.Response('Forbidden', 403)),
  );
  try {
    await blocked.ingest(url: 'https://www.instagram.com/reel/example/');
    throw StateError('Accepted blocked source');
  } on EmptyScrapedContentException catch (e) {
    final result = AiExceptionHandler.describe(e, fromLink: true);
    check(
      result.action == AiErrorAction.pasteText &&
          result.message ==
              "Couldn't extract recipe text from that link. Try pasting the caption or uploading a screenshot below.",
      'Blocked social URL offers caption recovery',
    );
  }
  check(spy.calls == 0, 'Blocked URL never sends an empty AI request');
  for (final body in [
    '<body></body>',
    '<body>Ingredients ${'x' * 88}</body>',
    '<meta property="og:description" content="Log in to continue ${'x' * 130}">',
  ]) {
    final service = RecipeIngestionService(
      spy,
      client: MockClient((_) async => http.Response(body, 200)),
    );
    try {
      await service.ingest(url: 'https://www.instagram.com/reel/example/');
      throw StateError('Accepted empty caption');
    } on EmptyScrapedContentException {
      check(spy.calls == 0, 'Empty or login-only page never calls AI');
    }
  }
  final boundary = RecipeIngestionService(
    spy,
    client: MockClient(
      (_) async => http.Response('<body>Ingredients ${'x' * 88}</body>', 200),
    ),
  );
  try {
    await boundary.scrape('https://recipes.example/short');
    throw StateError('Accepted 100 characters');
  } on EmptyScrapedContentException {
    check(true, '100-character body is rejected');
  }
  final fixture = File.fromUri(
    Platform.script.resolve('kabob_caption.txt'),
  ).readAsStringSync();
  final caption = await blocked.ingest(
    url: 'https://www.instagram.com/reel/example/',
    blurb: fixture,
  );
  check(
    caption.ingredients.length == 13 &&
        caption.sourceUrl!.contains('instagram.com') &&
        spy.calls == 0,
    'Blocked URL plus exact caption imports locally with attribution',
  );
  await blocked.ingest(
    url: 'https://www.instagram.com/reel/example/',
    blurb: 'Roast carrots with a little oil until tender.',
  );
  check(
    spy.calls == 1 &&
        spy.text!.contains('Roast carrots') &&
        spy.text!.contains('attribution only'),
    'Blocked URL plus freeform blurb uses supplied text',
  );
  final offline = RecipeIngestionService(
    spy,
    client: MockClient((_) async => throw const SocketException('offline')),
  );
  check(
    (await offline.ingest(
          url: 'https://recipes.example/offline',
          blurb: fixture,
        )).ingredients.length ==
        13,
    'Usable caption survives a network failure',
  );
  final page = RecipeIngestionService(
    spy,
    client: MockClient(
      (_) async => http.Response(
        '<script type="application/ld+json">${jsonEncode({
          '@type': 'Recipe',
          'name': 'Carrots',
          'recipeIngredient': ['300 g carrots'],
          'recipeInstructions': 'Roast carrots with oil until tender and lightly browned. Serve warm.',
        })}</script>',
        200,
      ),
    ),
  );
  await page.ingest(
    url: 'https://recipes.example/carrots',
    blurb: 'Please preserve the original servings.',
  );
  check(
    spy.text!.contains('Accessible page text:') &&
        spy.text!.contains('Please preserve'),
    'Accessible page and user notes are combined',
  );
  final bytes = Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);
  final imageOnly = RecipeIngestionService(
    spy,
    client: MockClient(
      (_) async => throw StateError('Image import must not scrape'),
    ),
  );
  final imageRecipe = await imageOnly.ingest(
    url: 'https://www.instagram.com/reel/example/',
    image: bytes,
    mimeType: 'image/png',
    blurb: 'Use the ingredients in this screenshot.',
  );
  check(
    identical(spy.bytes, bytes) &&
        spy.mime == 'image/png' &&
        spy.text!.contains('Use the ingredients'),
    'Image plus notes reaches multimodal adapter without scraping',
  );
  check(
    imageRecipe.prepMinutes == 10 &&
        imageRecipe.cookMinutes == 25 &&
        Recipe.fromJson(imageRecipe.toJson()).reviewNotes.single ==
            'Serve warm.',
    'Recipe metadata survives ingestion and serialization',
  );
  final gemini = GeminiDirectService(
    apiKey: 'test',
    client: MockClient((r) async {
      final body = jsonDecode(r.body);
      final parts = body['contents'][0]['parts'] as List;
      final data = parts.firstWhere(
        (p) => p['inlineData'] != null,
      )['inlineData'];
      check(
        data['mimeType'] == 'image/png' && data['data'] == base64Encode(bytes),
        'Google SDK sends actual MIME and base64 DataPart bytes',
      );
      final schema = body['generationConfig']['responseSchema'];
      check(
        schema['properties'].containsKey('prep_minutes') &&
            schema['properties'].containsKey('notes'),
        'SDK schema includes times and notes',
      );
      return http.Response(
        jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': jsonEncode(sample.toJson())},
                ],
              },
            },
          ],
        }),
        200,
      );
    }),
  );
  check(
    (await gemini.parseRecipe(
          'Image context',
          image: bytes,
          mimeType: 'image/png',
        )).cookMinutes ==
        25,
    'Multimodal structured recipe is decoded',
  );
  final emptyGemini = ProviderService(
    provider: 'Gemini',
    apiKey: 'test',
    model: 'test',
    client: MockClient(
      (_) async => http.Response(jsonEncode({'candidates': []}), 200),
    ),
  );
  final backup = ProviderService(
    provider: 'Grok',
    apiKey: 'test',
    model: 'test',
    client: MockClient(
      (_) async => http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': jsonEncode(sample.toJson())},
            },
          ],
        }),
        200,
      ),
    ),
  );
  check(
    (await FallbackService([
          emptyGemini,
          backup,
        ]).parseRecipe('context', image: bytes, mimeType: 'image/png')).title ==
        sample.title,
    'Empty SDK response falls back to the next enabled provider',
  );
  try {
    await FallbackService([]).parseRecipe('context');
    throw StateError('Expected missing key');
  } on AiFallbackException catch (e) {
    check(
      AiExceptionHandler.describe(e).action == AiErrorAction.settings,
      'Missing configured keys offers Settings',
    );
  }
}
