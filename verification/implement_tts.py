from pathlib import Path
p=Path(__file__).resolve().parents[1]/'AksharBuddy/aksharally_ui'
f=p/'android/app/src/main/kotlin/com/example/aksharally_ui/MainActivity.kt'
f.write_text('''package com.example.aksharally_ui

import android.content.Intent
import android.speech.tts.TextToSpeech
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "aksharbuddy/voices")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "settings" -> {
                        try {
                            startActivity(Intent("com.android.settings.TTS_SETTINGS"))
                            result.success(true)
                        } catch (e: Exception) { result.error("settings", "Open Android Settings > Text-to-speech", null) }
                    }
                    "offlineVoices" -> {
                        val engine = call.argument<String>("engine")
                        var probe: TextToSpeech? = null
                        probe = TextToSpeech(applicationContext, { status ->
                            runOnUiThread {
                                try {
                                    val voices = if (status == TextToSpeech.SUCCESS) probe?.voices else null
                                    result.success(voices?.filter {
                                        !it.isNetworkConnectionRequired &&
                                        !it.features.contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED)
                                    }?.map { mapOf("name" to it.name, "locale" to it.locale.toLanguageTag()) } ?: emptyList<Map<String,String>>())
                                } catch (e: Exception) { result.error("voices", e.message, null) }
                                finally { probe?.shutdown() }
                            }
                        }, engine)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
''',encoding='utf-8')
f=p/'lib/services/tts_service.dart';s=f.read_text(encoding='utf-8').replace("import 'dart:async';", "import 'dart:async';\nimport 'package:flutter/services.dart';\nimport 'package:shared_preferences/shared_preferences.dart';")
a=s.index('  Future<void> _setLanguage');b=s.index('  double get currentRate',a)
s=s[:a]+'''  static const _voices = MethodChannel('aksharbuddy/voices');
  static Future<void> openVoiceSettings() => _voices.invokeMethod<void>('settings');
  String? _selectedLanguage;

  Future<void> _setLanguage(String code) async {
    if (_selectedLanguage == code) return;
    final diagnostics = <String>[];
    final android = defaultTargetPlatform == TargetPlatform.android;
    final current = android ? await _tts.getDefaultEngine : null;
    final engines = android ? await _tts.getEngines : null;
    final choices = <String?>[current is String ? current : null];
    if (engines is List) {
      choices.addAll(engines.whereType<String>().where((e) => e != current));
    }
    for (final engine in choices) {
      try {
        if (engine != null && engine != current) {
          await _tts.setEngine(engine).timeout(const Duration(seconds: 8));
        }
        final locales = code == 'en' ? ['en-IN', 'en-US', 'en-GB'] : ['$code-IN'];
        final voices = android
            ? await _voices.invokeMethod<List<dynamic>>('offlineVoices', {'engine': engine})
                .timeout(const Duration(seconds: 8))
            : await _tts.getVoices;
        for (final locale in locales) {
          final available = await _tts.isLanguageAvailable(locale);
          final installed = android ? await _tts.isLanguageInstalled(locale) : available;
          diagnostics.add('engine=$engine locale=$locale available=$available offlineInstalled=$installed');
          if (available != true && available != 1) continue;
          if (android && installed != true && installed != 1) continue;
          final matching = voices is List ? voices.whereType<Map>().where(
              (v) => v['locale'].toString().replaceAll('_', '-') == locale).toList() : <Map>[];
          if (android && matching.isEmpty) continue;
          final result = await _tts.setLanguage(locale);
          if (result == 0 || result == false) continue;
          if (matching.isNotEmpty) {
            final voiceResult = await _tts.setVoice({
              'name': matching.first['name'].toString(), 'locale': locale});
            if (voiceResult == 0 || voiceResult == false) continue;
          }
          _selectedLanguage = code;
          await _saveVoiceDiagnostics(diagnostics);
          return;
        }
      } catch (e) { diagnostics.add('engine=$engine error=$e'); }
    }
    await _saveVoiceDiagnostics(diagnostics);
    final name = {'en':'English', 'hi':'Hindi', 'mr':'Marathi'}[code] ?? code;
    throw StateError('Install an offline $name voice in Android Text-to-speech settings, then try Listen again. Voice downloads need internet once.');
  }

  Future<void> _saveVoiceDiagnostics(List<String> messages) async {
    debugPrint(messages.join('\\n'));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('tts_last_diagnostics', messages.join('\\n'));
    } catch (_) { /* Diagnostics must never prevent speech. */ }
  }

'''+s[b:]
# Preserve the useful missing-language error instead of hiding it.
start=s.index('  Future<void> speak(')
s=s[:start]+s[start:].replace('    } catch (_) {','    } catch (e) {',1).replace("'Speech is unavailable. Check your device voice settings.'", "e is StateError ? e.message.toString() : 'Speech could not start. Open Voice settings and install an offline voice.'",1)
f.write_text(s,encoding='utf-8')
f=p/'lib/screens/settings_screen.dart';s=f.read_text(encoding='utf-8').replace("import '../services/api_service.dart';", "import '../services/api_service.dart';\nimport '../services/tts_service.dart';")
s=s.replace("title: const Text('Advanced connection settings'),", "initiallyExpanded: true,\n          title: const Text('Laptop connection'),")
pos=s.index('        const BuddyHeading(')
s=s[:pos]+'''        OutlinedButton.icon(
          icon: const Icon(Icons.record_voice_over),
          label: const Text('Android voice settings'),
          onPressed: () async {
            try { await TTSService.openVoiceSettings(); }
            catch (_) { if (mounted) setState(() => _message = 'Open Android Settings > Text-to-speech. Install English, Hindi or Marathi voice data.'); }
          },
        ),
'''+s[pos:];f.write_text(s,encoding='utf-8')
