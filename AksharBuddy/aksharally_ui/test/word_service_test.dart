import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aksharally_ui/services/word_service.dart';
import 'package:aksharally_ui/theme/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
  });
  test(
    'word help sends only cleaned word and language and uses configured server',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final seen = <Map<String, dynamic>>[];
      server.listen((req) async {
        final data =
            jsonDecode(await utf8.decoder.bind(req).join())
                as Map<String, dynamic>;
        seen.add(data);
        expect(req.uri.path, '/api/word-help');
        req.response.headers.contentType = ContentType.json;
        req.response.write(
          jsonEncode({'definition': 'A meaning', 'example': 'An example'}),
        );
        await req.response.close();
      });
      try {
        await AppSettings.setBackendUrl('http://127.0.0.1:${server.port}');
        final result = await WordService.lookup('मराठी!', 'mr');
        expect(result.word, 'मराठी');
        expect(result.language, 'mr');
        expect(seen.single, {'word': 'मराठी', 'language': 'mr'});
      } finally {
        await server.close(force: true);
      }
    },
  );
  test(
    'word help surfaces safe error and handles unavailable backend',
    () async {
      final closed = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final unavailablePort = closed.port;
      await closed.close(force: true);
      await AppSettings.setBackendUrl('http://127.0.0.1:$unavailablePort');
      await expectLater(
        WordService.lookup('read', 'en'),
        throwsFormatException,
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        await req.drain<void>();
        req.response.statusCode = 503;
        req.response.write(
          jsonEncode({'error': 'Try again later.', 'debug': 'private data'}),
        );
        await req.response.close();
      });
      try {
        await AppSettings.setBackendUrl('http://127.0.0.1:${server.port}');
        await expectLater(
          WordService.lookup('read', 'en'),
          throwsA(
            predicate(
              (e) => e is FormatException && e.message == 'Try again later.',
            ),
          ),
        );
      } finally {
        await server.close(force: true);
      }
    },
  );
}
