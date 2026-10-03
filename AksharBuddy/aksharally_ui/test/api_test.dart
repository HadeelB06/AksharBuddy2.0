import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aksharally_ui/services/api_service.dart';
import 'package:aksharally_ui/theme/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'API follows saved URL changes and uses new multilingual structured contract',
    () async {
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues({});
      final servers = <HttpServer>[];
      final requests = <Map<String, dynamic>>[];
      for (var i = 0; i < 2; i++) {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        servers.add(server);
        server.listen((request) async {
          final body =
              jsonDecode(await utf8.decoder.bind(request).join())
                  as Map<String, dynamic>;
          requests.add({
            'path': request.uri.path,
            'port': server.port,
            ...body,
          });
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'status': 'success',
              'language': body['language'],
              'originalText': body['text'],
              'simplifiedText': body['text'],
              if (body['structured_content'] != null)
                'structured_content': body['structured_content'],
            }),
          );
          await request.response.close();
        });
      }
      try {
        await AppSettings.setBackendUrl('http://127.0.0.1:${servers[0].port}');
        expect(await ApiService.simplifyText('हिंदी', language: 'hi'), 'हिंदी');
        await AppSettings.setBackendUrl('http://127.0.0.1:${servers[1].port}');
        final structure = <String, dynamic>{'type': 'document', 'blocks': []};
        final result = await ApiService.simplifyStructuredText(
          'मराठी',
          structure,
          language: 'mr',
        );
        expect(result.structuredContent, structure);
        expect(
          requests.map((r) => r['path']),
          everyElement('/api/simplify-text'),
        );
        expect(requests.map((r) => r['port']).toList(), [
          servers[0].port,
          servers[1].port,
        ]);
        expect(requests.map((r) => r['language']).toList(), ['hi', 'mr']);
      } finally {
        for (final server in servers) {
          await server.close(force: true);
        }
      }
    },
  );
  test('API shows JSON error message without raw diagnostic body', () async {
    HttpOverrides.global = null;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await request.drain<void>();
      request.response.statusCode = 503;
      request.response.write(
        jsonEncode({
          'error': 'Try again later.',
          'debug': 'private diagnostic',
        }),
      );
      await request.response.close();
    });
    try {
      await AppSettings.setBackendUrl('http://127.0.0.1:${server.port}');
      await expectLater(
        ApiService.simplifyText('test'),
        throwsA(
          predicate((e) => e.toString() == 'Exception: Try again later.'),
        ),
      );
    } finally {
      await server.close(force: true);
    }
  });
}
