from pathlib import Path
p=Path(__file__).resolve().parents[1]/'AksharBuddy'/'aksharally_ui'
def edit(name, old, new):
    f=p/name;s=f.read_text(encoding='utf-8');assert old in s,name;f.write_text(s.replace(old,new),encoding='utf-8')
edit('android/app/src/main/AndroidManifest.xml','android:label="AksharBuddy"','android:label="AksharBuddy"\n        android:usesCleartextTraffic="true"')
edit('lib/theme/app_settings.dart',"defaultValue: 'http://127.0.0.1:5000'","defaultValue: ''")
f=p/'lib/services/api_service.dart';s=f.read_text(encoding='utf-8')
s=s.replace("response.statusCode != 200", "(response.statusCode < 200 || response.statusCode >= 300)")
s=s.replace('Cannot reach the server. Check the backend address and connection.', 'Laptop backend unreachable. Start the backend, connect both devices to the same Wi-Fi/hotspot, and check the laptop address and Windows Firewall.')
s=s.replace('Processing took too long. Try a smaller file or try again.', 'The laptop stopped responding. Check its connection and backend log. Your original is unchanged.')
s=s.replace("    String profile = 'moderate',", "    String profile = 'moderate',\n    void Function(String stage)? onProgress,")
s=s.replace("Uri.parse('$server/api/format-text')", "Uri.parse('$server/api/extraction-jobs')")
s=s.replace("      final response = await request", "      onProgress?.call('Sending file to laptop');\n      final response = await request",1)
s=s.replace("      return FormatResult.fromJson(_decode(response));", """      final jobId = _decode(response)['jobId'] as String;
      final started = DateTime.now();
      try {
        while (DateTime.now().difference(started) < const Duration(minutes: 15)) {
          final poll = await http.get(Uri.parse('$server/api/extraction-jobs/$jobId'))
              .timeout(const Duration(seconds: 15));
          final job = _decode(poll);
          final stage = job['stage'] as String? ?? 'Extracting text';
          onProgress?.call(job['page'] != null
              ? '$stage · page ${job['page']} of ${job['pages']}' : stage);
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
          await http.delete(Uri.parse('$server/api/extraction-jobs/$jobId'))
              .timeout(const Duration(seconds: 3));
        } catch (_) { /* Expiring server jobs are also cleaned automatically. */ }
      }""")
pos=s.index('  static Future<Map<String, dynamic>> _simplify')
s=s[:pos]+"""  static Future<void> checkConnection() => _network(() async {
    final response = await http.get(Uri.parse('$baseUrl/health'))
        .timeout(const Duration(seconds: 5));
    final data = _decode(response);
    if (data['service'] != 'aksharbuddy' || data['version'] != 'lan-repair-1') {
      throw Exception('Start the backend from the new LAN repair folder.');
    }
  });

"""+s[pos:];f.write_text(s,encoding='utf-8')
edit('lib/screens/reading_screen.dart','  bool _isLoading = false;', "  bool _isLoading = false;\n  String _stage = 'Preparing text';")
edit('lib/screens/reading_screen.dart','        profile: _profile,', "        profile: _profile,\n        onProgress: (stage) { if (mounted) setState(() => _stage = stage); },")
edit('lib/screens/reading_screen.dart','    final display = _mode', "    if (_mode == _ProcessMode.simplifyFormat && mounted) {\n      setState(() => _stage = 'Simplifying text on laptop');\n    }\n    final display = _mode")
edit('lib/screens/reading_screen.dart',"_isLoading ? 'Preparing your reading…'",'_isLoading ? _stage')
edit('lib/screens/reading_screen.dart','The first request can take up to 3 minutes while the local model starts. Keep the USB cable connected.', 'The laptop loads the AI model once and reuses it. Keep both devices on the same Wi-Fi. Your original stays available.')
edit('lib/screens/settings_screen.dart',"import '../services/auth_service.dart';", "import '../services/auth_service.dart';\nimport '../services/api_service.dart';")
edit('lib/screens/settings_screen.dart','text: AppSettings.backendUrl','text: AppSettings.effectiveBackendUrl')
edit('lib/screens/settings_screen.dart','The USB launcher connects automatically. Change this address only for a different server.', 'Start the backend on your laptop. Connect both devices to the same Wi-Fi or hotspot; internet and USB are not needed. Enter the address shown by the laptop launcher.')
edit('lib/screens/settings_screen.dart',"hintText: 'http://127.0.0.1:5000'", "hintText: 'http://192.168.1.10:5000'")
edit('lib/screens/settings_screen.dart','await AppSettings.setBackendUrl(_url.text);','await AppSettings.setBackendUrl(_url.text);\n                            await ApiService.checkConnection();')
edit('lib/screens/settings_screen.dart',"'Backend address saved.'", "'Connected to your laptop. Ready for OCR and local AI.'")
edit('lib/screens/settings_screen.dart',"'Could not save the address.'", "e.toString().replaceFirst('Exception: ', '')")
edit('lib/screens/settings_screen.dart',"'Save backend address'", "'Save and check connection'")
edit('lib/screens/words_screen.dart','                    Text(w.definition),', """                    OutlinedButton.icon(
                      onPressed: () => showWordHelp(context, w.word, w.language),
                      icon: const Icon(Icons.volume_up_outlined),
                      label: const Text('Open meaning and pronunciation'),
                    ),
                    Text(w.definition),""")
edit('lib/services/library_storage.dart',"  static const _key", """  static String? _lastOpened;
  static List<LibraryItem> continueReading() {
    if (_items.isEmpty) return [];
    return [_items.firstWhere((i) => i.date.toIso8601String() == _lastOpened,
        orElse: () => _items.first)];
  }
  static Future<void> markOpened(String id) async {
    _lastOpened = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_opened_reading', id);
  }
  static const _key""")
edit('lib/services/library_storage.dart',"    final raw = prefs", "    _lastOpened = prefs.getString('last_opened_reading');\n    final raw = prefs")
edit('lib/screens/home_screen.dart','LibraryStorage.getItems().take(2).toList()','LibraryStorage.continueReading()')
edit('lib/screens/home_screen.dart','A place to return to','Continue reading')
edit('lib/screens/output_screen.dart','    unawaited(_restorePosition());','    unawaited(LibraryStorage.markOpened(_readingId));\n    unawaited(_restorePosition());')
