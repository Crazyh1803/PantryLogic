import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html;
import '../../../ai_service.dart';
import '../../../caption_parser.dart';
import '../../../models.dart';
import '../../../core/errors/ai_exception_handler.dart';

class RecipeIngestionService {
  final AIService ai;
  final http.Client? client;
  RecipeIngestionService(this.ai, {this.client});
  Future<String> scrape(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty)
      throw const FormatException('Use a valid HTTPS recipe link.');
    final transport = client ?? http.Client();
    try {
      final response = await transport
          .send(
            http.Request('GET', uri)
              ..headers['User-Agent'] = 'PantryLogicRecipeImporter/1.1',
          )
          .timeout(const Duration(seconds: 20));
      if ([401, 403, 404].contains(response.statusCode))
        throw const EmptyScrapedContentException();
      if (response.statusCode == 429)
        throw const AiRequestException(429, 'HTTP 429');
      if (response.statusCode != 200)
        throw const EmptyScrapedContentException();
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 20),
      )) {
        bytes.addAll(chunk);
        if (bytes.length > 3 * 1024 * 1024)
          throw const EmptyScrapedContentException();
      }
      final doc = html.parse(utf8.decode(bytes, allowMalformed: true));
      final structured = <Map>[];
      void scan(dynamic value) {
        if (value is List) {
          for (final v in value) {
            scan(v);
          }
        } else if (value is Map) {
          final t = value['@type'];
          if (t == 'Recipe' || t is List && t.contains('Recipe'))
            structured.add(value);
          if (value['@graph'] != null) scan(value['@graph']);
        }
      }

      for (final script in doc.querySelectorAll(
        'script[type="application/ld+json"]',
      )) {
        try {
          scan(jsonDecode(script.text));
        } catch (_) {}
      }
      String text;
      if (structured.isNotEmpty) {
        text = jsonEncode(structured.first);
      } else {
        final social =
            uri.host == 'instagram.com' ||
            uri.host.endsWith('.instagram.com') ||
            uri.host == 'tiktok.com' ||
            uri.host.endsWith('.tiktok.com');
        final captions = doc
            .querySelectorAll(
              'meta[property="og:description"],meta[name="description"]',
            )
            .map((e) => e.attributes['content'] ?? '')
            .where((s) => s.trim().length > 100);
        for (final e in doc.querySelectorAll(
          'script,style,nav,footer,header',
        )) {
          e.remove();
        }
        text = social ? captions.join('\n') : doc.body?.text.trim() ?? '';
        final lower = text.toLowerCase();
        final cooking = RegExp(
          r'ingredients|\b(?:cups?|tbsp|tsp|grams?|oven|simmer|chop|cook|bake)\b',
        ).hasMatch(lower);
        if (!cooking ||
            RegExp(
                  r'log in to (continue|see|view)|sign in to (continue|see|view)|enable javascript',
                ).hasMatch(lower) &&
                !lower.contains('ingredients'))
          throw const EmptyScrapedContentException();
      }
      if (text.trim().length <= 100) throw const EmptyScrapedContentException();
      return text.length > 24000 ? text.substring(0, 24000) : text;
    } finally {
      if (client == null) transport.close();
    }
  }

  Future<Recipe> ingest({
    String url = '',
    String blurb = '',
    Uint8List? image,
    String? mimeType,
  }) async {
    final source = url.trim(), notes = blurb.trim();
    if (source.isEmpty && notes.isEmpty && image == null)
      throw const FormatException('Add a link, text or image.');
    if (source.isNotEmpty) {
      final uri = Uri.tryParse(source);
      if (uri == null || uri.scheme != 'https' || uri.host.isEmpty)
        throw const FormatException('Use a valid HTTPS recipe link.');
    }
    String extracted = '';
    if (source.isNotEmpty && image == null) {
      try {
        extracted = await scrape(source);
      } on EmptyScrapedContentException {
        if (notes.isEmpty) rethrow;
      } on TimeoutException {
        if (notes.isEmpty) rethrow;
      } on SocketException {
        if (notes.isEmpty) rethrow;
      } on http.ClientException {
        if (notes.isEmpty) rethrow;
      }
    }
    // Caption is explicit user input and can stand alone even if a social URL is blocked.
    final local = image == null
        ? parseCaption(notes.isNotEmpty ? notes : extracted)
        : null;
    final recipe =
        local ??
        await ai.parseRecipe(
          [
            if (source.isNotEmpty)
              'Source URL (attribution only; do not claim to have watched it): $source',
            if (extracted.isNotEmpty) 'Accessible page text:\n$extracted',
            if (notes.isNotEmpty) 'Recipe text / caption / user notes:\n$notes',
            if (image != null)
              'Extract the recipe from the attached image; use the supplied text as context. Do not invent missing ingredients or steps.',
          ].join('\n\n'),
          image: image,
          mimeType: mimeType,
        );
    return Recipe.fromJson({
      ...recipe.toJson(),
      'source_url': source.isEmpty ? recipe.sourceUrl : source,
    });
  }
}
