import 'dart:async';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../theme/app_settings.dart';

class TTSService {
  final FlutterTts _tts = FlutterTts();
  Future<void>? _initialization;
  bool isSpeaking = false;
  bool _disposed = false;
  bool _hasProgress = false;
  double _speechRate = 0.4;
  Timer? _fallback;
  int _generation = 0;
  String _text = '';
  int _fallbackIndex = 0;
  List<RegExpMatch> _ranges = [];
  void Function(int start, int end)? onProgress;
  VoidCallback? onComplete;
  ValueChanged<String>? onError;

  Future<void> init() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    _tts.setStartHandler(() {
      if (_disposed || _text.isEmpty) return;
      isSpeaking = true;
      _startFallback();
    });
    _tts.setCompletionHandler(_finish);
    _tts.setCancelHandler(_finish);
    _tts.setErrorHandler((_) {
      _finish();
      if (!_disposed) {
        onError?.call(
          'Speech is unavailable. Check your device voice settings.',
        );
      }
    });
    _tts.setProgressHandler((text, start, end, word) {
      if (_disposed ||
          !isSpeaking ||
          text != _text ||
          start < 0 ||
          end <= start) {
        return;
      }
      _hasProgress = true;
      _fallback?.cancel();
      onProgress?.call(start, end);
    });
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
  }

  static const _voices = MethodChannel('aksharbuddy/voices');
  static Future<void> openVoiceSettings() =>
      _voices.invokeMethod<void>('settings');
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
        final locales = code == 'en'
            ? ['en-IN', 'en-US', 'en-GB']
            : ['$code-IN'];
        final voices = android
            ? await _voices
                  .invokeMethod<List<dynamic>>('offlineVoices', {
                    'engine': engine,
                  })
                  .timeout(const Duration(seconds: 8))
            : await _tts.getVoices;
        for (final locale in locales) {
          final available = await _tts.isLanguageAvailable(locale);
          final installed = android
              ? await _tts.isLanguageInstalled(locale)
              : available;
          diagnostics.add(
            'engine=$engine locale=$locale available=$available offlineInstalled=$installed',
          );
          if (available != true && available != 1) continue;
          if (android && installed != true && installed != 1) continue;
          final matching = voices is List
              ? voices
                    .whereType<Map>()
                    .where(
                      (v) =>
                          v['locale'].toString().replaceAll('_', '-') == locale,
                    )
                    .toList()
              : <Map>[];
          if (android && matching.isEmpty) continue;
          final result = await _tts.setLanguage(locale);
          if (result == 0 || result == false) continue;
          if (matching.isNotEmpty) {
            final voiceResult = await _tts.setVoice({
              'name': matching.first['name'].toString(),
              'locale': locale,
            });
            if (voiceResult == 0 || voiceResult == false) continue;
          }
          _selectedLanguage = code;
          await _saveVoiceDiagnostics(diagnostics);
          return;
        }
      } catch (e) {
        diagnostics.add('engine=$engine error=$e');
      }
    }
    await _saveVoiceDiagnostics(diagnostics);
    final name =
        {'en': 'English', 'hi': 'Hindi', 'mr': 'Marathi'}[code] ?? code;
    throw StateError(
      'Install an offline $name voice in Android Text-to-speech settings, then try Listen again. Voice downloads need internet once.',
    );
  }

  Future<void> _saveVoiceDiagnostics(List<String> messages) async {
    debugPrint(messages.join('\n'));
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('tts_last_diagnostics', messages.join('\n'));
    } catch (_) {
      /* Diagnostics must never prevent speech. */
    }
  }

  double get currentRate => _speechRate;
  Future<void> setRate(double rate) async {
    _speechRate = rate.clamp(0.1, 1.0).toDouble();
    try {
      await init();
      if (_disposed) return;
      await _tts.setSpeechRate(_speechRate);
      if (isSpeaking && !_hasProgress) _startFallback();
    } catch (_) {
      _finish();
      if (!_disposed) {
        onError?.call(
          'Speech is unavailable. Check your device voice settings.',
        );
      }
    }
  }

  void _startFallback() {
    _fallback?.cancel();
    if (_hasProgress || _ranges.isEmpty || _disposed) return;
    // Approximation only: native progress always replaces this timer.
    final interval = Duration(
      milliseconds: (400 * 0.4 / _speechRate).round().clamp(80, 1600),
    );
    _fallback = Timer.periodic(interval, (timer) {
      if (_disposed ||
          !isSpeaking ||
          _hasProgress ||
          _fallbackIndex >= _ranges.length) {
        timer.cancel();
        return;
      }
      final word = _ranges[_fallbackIndex++];
      onProgress?.call(word.start, word.end);
    });
  }

  Future<void> speak(String text, {String? language}) async {
    final generation = ++_generation;
    try {
      await init();
      if (_disposed || generation != _generation) return;
      _finish();
      await _tts.stop();
      await _setLanguage(language ?? AppSettings.language);
      await _tts.setSpeechRate(_speechRate);
      if (_disposed || generation != _generation || text.trim().isEmpty) return;
      _text = text;
      _ranges = RegExp(r'\S+').allMatches(text).toList();
      _fallbackIndex = 0;
      _hasProgress = false;
      isSpeaking = true;
      final result = await _tts.speak(text);
      if (result == 0 || result == false) {
        _finish();
        onError?.call(
          'The device could not start speech. Check your installed voices.',
        );
      }
    } catch (e) {
      _finish();
      if (!_disposed) {
        onError?.call(
          e is StateError
              ? e.message.toString()
              : 'Speech could not start. Open Voice settings and install an offline voice.',
        );
      }
    }
  }

  void _finish() {
    isSpeaking = false;
    _fallback?.cancel();
    _text = '';
    if (!_disposed) onComplete?.call();
  }

  Future<void> stop() async {
    ++_generation;
    _finish();
    try {
      await _tts.stop();
    } catch (_) {
      /* A missing engine is non-fatal. */
    }
  }

  void dispose() {
    _disposed = true;
    onProgress = null;
    onComplete = null;
    onError = null;
    unawaited(stop());
  }
}
