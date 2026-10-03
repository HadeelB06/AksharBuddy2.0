import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aksharally_ui/services/api_service.dart';
import 'package:aksharally_ui/services/library_storage.dart';
import 'package:aksharally_ui/models/library_item.dart';
import 'package:aksharally_ui/theme/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'LAN health and extraction polling preserve text without calling AI',
    () async {
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({});
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final paths = <String>[];
      var polls = 0;
      server.listen((request) async {
        paths.add(request.uri.path);
        await request.drain<void>();
        Map<String, dynamic> body = {'status': 'success'};
        if (request.uri.path == '/health') {
          body.addAll({'service': 'aksharbuddy', 'version': 'lan-repair-1'});
        } else if (request.method == 'POST') {
          request.response.statusCode = 202;
          body['jobId'] = 'test-job';
        } else if (request.method == 'GET') {
          polls++;
          body.addAll({
            'state': polls == 1 ? 'working' : 'complete',
            'stage': 'Reading page',
            'page': 2,
            'pages': 3,
            'result': {
              'profile': 'moderate', 'fontSize': 20, 'lineHeight': 1.8,
              'letterSpacing': 1, 'wordSpacing': 4, 'paragraphSpacing': 16,
              'recommendedFont': 'Lexend',
              'originalText': 'Nina has 12 books.',
              'processedText': 'Nina has 12 books.',
              'sourceType': 'image',
            },
          });
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(body));
        await request.response.close();
      });
      final directory = await Directory.systemTemp.createTemp('buddy-lan-test');
      try {
        await AppSettings.setBackendUrl('http://127.0.0.1:${server.port}');
        await ApiService.checkConnection();
        final file = await File(
          '${directory.path}/test.png',
        ).writeAsBytes([1, 2, 3]);
        final stages = <String>[];
        final result = await ApiService.processImage(
          file,
          onProgress: stages.add,
        );
        expect(result.rawText, 'Nina has 12 books.');
        expect(stages, contains('Reading page · page 2 of 3'));
        expect(paths.any((p) => p.contains('simplify')), isFalse);
      } finally {
        await server.close(force: true);
        await directory.delete(recursive: true);
      }
    },
  );

  test('continue card follows last opened item and survives reload', () async {
    SharedPreferences.setMockInitialValues({});
    await LibraryStorage.load();
    final first = LibraryItem(
      title: 'First',
      content: 'First',
      date: DateTime(2026, 1, 1),
      sourceType: 'text',
      language: 'en',
    );
    final second = LibraryItem(
      title: 'Second',
      content: 'Second',
      date: DateTime(2026, 1, 2),
      sourceType: 'text',
      language: 'en',
    );
    LibraryStorage.addItem(first);
    LibraryStorage.addItem(second);
    await LibraryStorage.markOpened(first.date.toIso8601String());
    expect(LibraryStorage.continueReading().single.title, 'First');
    await LibraryStorage.load();
    expect(LibraryStorage.continueReading().single.title, 'First');
  });
}
