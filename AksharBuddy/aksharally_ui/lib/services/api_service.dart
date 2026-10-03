import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/format_result.dart';
import '../theme/app_settings.dart';

class ApiService {
  static final Map<String, Future<FormatResult>> _imageRequests = {};

  static String get baseUrl {
    final url = AppSettings.effectiveBackendUrl;
    if (url.isEmpty) {
      throw Exception(
        'Add your backend URL in Settings before processing a file or simplifying text.',
      );
    }
    return url;
  }

  static Map<String, dynamic> _decode(http.Response response) {
    dynamic data;
    try {
      data = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw Exception(
        'The server returned an unreadable response. Check your backend address.',
      );
    }
    if (data is! Map<String, dynamic>) {
      throw Exception('The server returned an unexpected response.');
    }
    if ((response.statusCode < 200 || response.statusCode >= 300) ||
        data['status'] == 'error') {
      final message = data['error'] ?? data['message'];
      throw Exception(
        message is String && message.trim().isNotEmpty
            ? message
            : 'The server could not complete the request. Please try again.',
      );
    }
    return data;
  }

  static Future<T> _network<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on TimeoutException {
      throw Exception(
        'The laptop stopped responding. Check its connection and backend log. Your original is unchanged.',
      );
    } on SocketException {
      throw Exception(
        'Laptop backend unreachable. Start the backend, connect both devices to the same Wi-Fi/hotspot, and check the laptop address and Windows Firewall.',
      );
    } on http.ClientException {
      throw Exception(
        'Laptop backend unreachable. Start the backend, connect both devices to the same Wi-Fi/hotspot, and check the laptop address and Windows Firewall.',
      );
    } on FileSystemException {
      throw Exception(
        'This file is no longer available. Please select it again.',
      );
    } on FormatException {
      throw Exception('The server returned an invalid response.');
    } on TypeError {
      throw Exception('The server returned an unexpected response format.');
    }
  }

  static Future<FormatResult> processImage(
    File file, {
    String profile = 'moderate',
    void Function(String stage)? onProgress,
    String? language,
  }) async {
    final server = baseUrl;
    final lang = language ?? AppSettings.language;
    // Only identical requests share work. Changing server/language takes effect immediately.
    final key = jsonEncode([server, file.path, profile, lang]);
    final active = _imageRequests[key];
    if (active != null) return active;
    final future = _network(() async {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$server/api/extraction-jobs'),
      );
      request.fields.addAll({'language': lang, 'profile': profile});
      request.files.add(await http.MultipartFile.fromPath('file', file.path));
      onProgress?.call('Sending file to laptop');
      final response = await request
          .send()
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 90));
      final jobId = _decode(response)['jobId'] as String;
      final started = DateTime.now();
      try {
        while (DateTime.now().difference(started) <
            const Duration(minutes: 15)) {
          final poll = await http
              .get(Uri.parse('$server/api/extraction-jobs/$jobId'))
              .timeout(const Duration(seconds: 15));
          final job = _decode(poll);
          final stage = job['stage'] as String? ?? 'Extracting text';
          onProgress?.call(
            job['page'] != null
                ? '$stage · page ${job['page']} of ${job['pages']}'
                : stage,
          );
          if (job['state'] == 'complete') {
            return FormatResult.fromJson(job['result'] as Map<String, dynamic>);
          }
          if (job['state'] == 'failed' || job['state'] == 'cancelled') {
            throw Exception(job['error'] ?? 'Reading cancelled.');
          }
          await Future<void>.delayed(const Duration(milliseconds: 700));
        }
        throw TimeoutException('Document processing limit reached.');
      } finally {
        try {
          await http
              .delete(Uri.parse('$server/api/extraction-jobs/$jobId'))
              .timeout(const Duration(seconds: 3));
        } catch (_) {
          /* Expiring server jobs are also cleaned automatically. */
        }
      }
    });
    _imageRequests[key] = future;
    try {
      return await future;
    } finally {
      _imageRequests.remove(key);
    }
  }

  static Future<void> checkConnection() => _network(() async {
    final response = await http
        .get(Uri.parse('$baseUrl/health'))
        .timeout(const Duration(seconds: 5));
    final data = _decode(response);
    if (data['service'] != 'aksharbuddy' || data['version'] != 'lan-repair-1') {
      throw Exception('Start the backend from the new LAN repair folder.');
    }
  });

  static Future<Map<String, dynamic>> _simplify(
    String text,
    String? language, [
    Map<String, dynamic>? structure,
  ]) => _network(() async {
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/simplify-text'),
          headers: {'Content-Type': 'application/json; charset=utf-8'},
          body: jsonEncode({
            'text': text,
            'language': language ?? AppSettings.language,
            'structured_content': ?structure,
          }),
        )
        .timeout(const Duration(seconds: 180));
    final data = _decode(response);
    if (data['status'] != 'success' || data['simplifiedText'] is! String) {
      throw Exception(
        'The server returned an unexpected simplification response.',
      );
    }
    return data;
  });

  static Future<String> simplifyText(String text, {String? language}) async =>
      (await _simplify(text, language))['simplifiedText'] as String;

  static Future<StructuredSimplifyResult> simplifyStructuredText(
    String text,
    Map<String, dynamic> structuredContent, {
    String? language,
  }) async {
    final data = await _simplify(text, language, structuredContent);
    final returned = data['structured_content'];
    if (returned is! Map<String, dynamic>) {
      throw Exception(
        'The server did not preserve the document layout. Please update your backend.',
      );
    }
    return StructuredSimplifyResult(
      formattedText: data['simplifiedText'] as String,
      structuredContent: returned,
    );
  }
}

class StructuredSimplifyResult {
  final String formattedText;
  final Map<String, dynamic> structuredContent;
  const StructuredSimplifyResult({
    required this.formattedText,
    required this.structuredContent,
  });
}
