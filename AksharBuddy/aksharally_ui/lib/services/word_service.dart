import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../theme/app_settings.dart';
import 'buddy_store.dart';

class WordService {
  static String clean(String word) => word.replaceAll(
    RegExp(r'^[^\p{L}\p{M}\p{N}]+|[^\p{L}\p{M}\p{N}]+$', unicode: true),
    '',
  );
  static Future<SavedWord> lookup(String word, String language) async {
    final base = AppSettings.effectiveBackendUrl;
    if (base.isEmpty) {
      throw const FormatException(
        'Add your backend address in Settings to use word help.',
      );
    }
    late http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('$base/api/word-help'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'word': clean(word), 'language': language}),
          )
          .timeout(const Duration(seconds: 30));
    } on http.ClientException {
      throw const FormatException(
        'Word help is unavailable. Your saved words remain available offline.',
      );
    } on TimeoutException {
      throw const FormatException(
        'Word help timed out. Your saved words remain available offline.',
      );
    }
    Map<String, dynamic> data;
    try {
      data = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      throw const FormatException(
        'Word help returned an unreadable response. Try again.',
      );
    }
    if (response.statusCode != 200) {
      throw FormatException(
        data['error'] is String
            ? data['error'] as String
            : 'Word help is unavailable.',
      );
    }
    if (data['definition'] is! String ||
        data['example'] is! String ||
        (data['definition'] as String).trim().isEmpty) {
      throw const FormatException('No meaning was found. Try another word.');
    }
    return SavedWord(
      word: clean(word),
      language: language,
      definition: data['definition'],
      example: data['example'],
      source: data['source'] is String
          ? data['source'] as String
          : 'Local word help',
    );
  }
}
