import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;

class EmptyScrapedContentException implements Exception {
  const EmptyScrapedContentException();
  @override
  String toString() => 'EmptyScrapedContentException';
}

class AiRequestException extends FormatException {
  final int statusCode;
  final String detail;
  const AiRequestException(this.statusCode, this.detail) : super(detail);
  @override
  String toString() => detail;
}

class AiFallbackException extends FormatException {
  final Object cause;
  AiFallbackException(this.cause)
    : super(
        cause is FormatException
            ? cause.message
            : 'AI providers could not return a recipe.',
      );
}

enum AiErrorAction { none, settings, pasteText }

class AiFailure {
  final String message;
  final AiErrorAction action;
  const AiFailure(this.message, [this.action = AiErrorAction.none]);
}

class AiExceptionHandler {
  static AiFailure describe(Object error, {bool fromLink = false}) {
    if (error is AiFallbackException)
      return describe(error.cause, fromLink: fromLink);
    final text = error.toString().toUpperCase();
    final code = error is AiRequestException
        ? error.statusCode
        : int.tryParse(
            RegExp(
                  r'\b(400|401|403|404|429|500|502|503|504|529)\b',
                ).firstMatch(text)?.group(1) ??
                '',
          );
    if (code == 429 || text.contains('RESOURCE_EXHAUSTED'))
      return const AiFailure(
        'AI rate limit reached. Please wait about 30 seconds and try again.',
      );
    final badKey =
        code == 401 ||
        text.contains('UNAUTHENTICATED') ||
        text.contains('API_KEY_INVALID') ||
        text.contains('API KEY NOT VALID') ||
        RegExp(
          r'(INVALID|MISSING|ADD|ENTER|REJECTED).{0,35}(API KEY|API_KEY)|API KEY.{0,35}(INVALID|MISSING|REJECTED)',
        ).hasMatch(text);
    if (badKey)
      return const AiFailure(
        'Invalid API key. Please check your key in Settings > AI Configuration.',
        AiErrorAction.settings,
      );
    if (error is SocketException ||
        error is TimeoutException ||
        error is http.ClientException ||
        text.contains('NETWORK') ||
        text.contains('CANNOT REACH') ||
        text.contains('TIMED OUT') ||
        text.contains('SOCKETEXCEPTION'))
      return const AiFailure(
        'Network connection issue. Please check your internet connection.',
      );
    if (error is EmptyScrapedContentException ||
        (fromLink &&
            error is! AiRequestException &&
            (code == 403 ||
                text.contains('NO RECIPE') ||
                text.contains('NO COMPLETE RECIPE') ||
                text.contains('LOGIN'))))
      return const AiFailure(
        "Couldn't extract recipe text from that link. Try pasting the caption or uploading a screenshot below.",
        AiErrorAction.pasteText,
      );
    if (code == 503 || code == 529)
      return const AiFailure(
        'The AI service is busy right now. Please try again shortly or choose another model in Settings > AI Configuration.',
        AiErrorAction.settings,
      );
    if (code == 400 || code == 404)
      return const AiFailure(
        'The selected AI model or request is unavailable for this account. Load an available model in Settings > AI Configuration and test again.',
        AiErrorAction.settings,
      );
    if (code == 403)
      return const AiFailure(
        'This API key does not have access. Check its permissions and API billing in Settings > AI Configuration.',
        AiErrorAction.settings,
      );
    return const AiFailure(
      "We couldn't parse that recipe. Try pasting the text directly.",
      AiErrorAction.pasteText,
    );
  }
}
