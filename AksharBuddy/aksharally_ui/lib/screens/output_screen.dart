import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/word_help_sheet.dart';

import 'package:flutter/material.dart';
import '../theme/app_settings.dart';

import '../theme/app_theme.dart';
import '../services/library_storage.dart';
import '../models/library_item.dart';
import '../models/format_result.dart';
import '../services/tts_service.dart';
import '../theme/accessibility_settings.dart';
import '../widgets/highlighted_text_view.dart';
import '../widgets/structured_content_view.dart';
import '../widgets/reading_customize_sheet.dart';

/// OutputScreen — DISPLAY / READING screen only.
///
/// OutputScreen never performs input processing. All OCR and AI
/// (local model) calls happen upstream in ReadingScreen; by the time content
/// reaches this screen it is already final. This screen's only job is to
/// render that content in a dyslexia-friendly way and provide reading
/// controls (TTS, word highlighting, accessibility/profile settings,
/// library save/open).
///
/// Content can arrive from three sources, all already processed:
///   - ReadingScreen  → initialFormatResult (OCR/format-only result)
///   - ReadingScreen  → displayText (typed text, or OCR+local model result)
///   - LibraryScreen  → displayText (previously-saved content)
///   - initialText is kept only for backward-compatible construction and
///     is displayed as-is — OutputScreen never calls local model itself.
///
/// ReaderScreen itself is left completely untouched as rollback
/// protection — it is simply no longer referenced by navigation.
class OutputScreen extends StatefulWidget {
  /// Kept for constructor compatibility. Nothing currently passes this,
  /// but if it is ever provided, the text is displayed directly —
  /// OutputScreen never calls the AI simplify endpoint itself.
  final String? initialText;

  /// Pre-formatted result from ReadingScreen (image/file, Format Only).
  final FormatResult? initialFormatResult;

  /// Already-processed / already-saved text — from ReadingScreen (typed
  /// text, or OCR+local model result) or from LibraryScreen (saved content).
  final String? displayText;
  final String? originalText;
  final String? readingId;
  final String? language;

  /// When true, _loadDisplayText() saves the content to the library.
  /// Set to true only by ReadingScreen (fresh content).
  /// LibraryScreen and HomeScreen leave this false to avoid duplicates.
  final bool saveOnLoad;
  final bool simplificationRequested;

  const OutputScreen({
    super.key,
    this.initialText,
    this.initialFormatResult,
    this.displayText,
    this.originalText,
    this.readingId,
    this.language,
    this.saveOnLoad = false,
    this.simplificationRequested = false,
  });

  @override
  State<OutputScreen> createState() => _OutputScreenState();
}

class _OutputScreenState extends State<OutputScreen>
    with WidgetsBindingObserver {
  late final String _readingId =
      widget.readingId ?? DateTime.now().toIso8601String();
  // ── display text state ────────────────────────────────────────────────────
  String simplifiedText = '';
  bool _originalSelected = false;
  String _resultText = '';
  int _speechOffset = 0;
  int _pausedOffset = 0;
  bool _paused = false;
  bool _speaking = false;

  // ── profile & format result ───────────────────────────────────────────────
  // _selectedProfile reflects the active accessibility preset.
  // _isCustomize tracks whether the 'Customize' chip is visually active.
  String _selectedProfile = 'moderate';
  bool _isCustomize = false;
  bool _showOriginalOcr = false;
  FormatResult? _formatResult;

  // ── TTS ───────────────────────────────────────────────────────────────────
  final TTSService _tts = TTSService();
  double speechRate = 0.4;
  bool autoRead = false;

  List<String> words = [];
  int currentIndex = -1;

  // ── accessibility overlays ────────────────────────────────────────────────
  // Initialised lazily in build() once LayoutBuilder provides a real height.
  double? _focusLineY; // centre of the focus band
  double? _rulerY; // top edge of the reading ruler

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tts.onProgress = (start, end) {
      if (!mounted) return;
      final index = HighlightedTextView.wordIndexAtOffset(
        simplifiedText,
        words,
        start + _speechOffset,
        end + _speechOffset,
      );
      _pausedOffset = start + _speechOffset;
      if (index != currentIndex) setState(() => currentIndex = index);
    };
    _tts.onComplete = () {
      if (mounted) {
        setState(() {
          _speaking = false;
          if (!_paused) currentIndex = -1;
        });
      }
    };
    _tts.onError = (message) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    };

    // Restore active profile from persisted accessibility settings.
    _selectedProfile = (AccessibilitySettings.profile == 'customize')
        ? 'moderate'
        : AccessibilitySettings.profile;
    _isCustomize = AccessibilitySettings.profile == 'customize';

    if (widget.initialFormatResult != null) {
      // Pre-formatted result from ReadingScreen (image/file, format-only).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadInitialFormatResult(widget.initialFormatResult!);
      });
    } else if (widget.displayText != null) {
      // Already-processed / already-saved content — display as-is,
      // no API call.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadDisplayText(widget.displayText!);
      });
    } else if (widget.initialText != null) {
      // Compatibility path only — display as-is. OutputScreen never
      // calls the AI simplify endpoint itself.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadDisplayText(widget.initialText!);
      });
    }
  }

  // ── word-splitting — removes embedded \n / \n\n ───────────────────────────
  List<String> _splitToWords(String text) =>
      HighlightedTextView.splitToWords(text);

  // ── load pre-formatted result (from ReadingScreen) ────────────────────────
  void _loadInitialFormatResult(FormatResult r) {
    if (!mounted) return;
    stopReading();
    setState(() {
      _formatResult = r;
      simplifiedText = r.processedText;
      _resultText = r.processedText;
      words = _splitToWords(r.processedText);
    });
    _saveToLibrary(r.processedText, r.sourceType);
    unawaited(LibraryStorage.markOpened(_readingId));
    unawaited(_restorePosition());
    if (autoRead) _tts.setRate(speechRate).then((_) => startReading());
  }

  // ── load already-processed / already-saved text — no API call ────────────
  void _loadDisplayText(String text) {
    if (!mounted) return;
    stopReading();
    setState(() {
      simplifiedText = text;
      _resultText = text;
      words = _splitToWords(text);
    });
    // Save only when the caller (ReadingScreen) signals fresh content via
    // saveOnLoad: true. LibraryScreen and HomeScreen leave saveOnLoad at its
    // default (false), so reopening existing items never creates duplicates.
    if (widget.saveOnLoad) _saveToLibrary(text, 'text');
    unawaited(LibraryStorage.markOpened(_readingId));
    unawaited(_restorePosition());
    if (autoRead) _tts.setRate(speechRate).then((_) => startReading());
  }

  // ── library save ──────────────────────────────────────────────────────────
  void _saveToLibrary(String content, String sourceType) {
    if (content.isEmpty ||
        content.startsWith('❌') ||
        content.startsWith('⚠️')) {
      return;
    }

    final wordCount = content.split(' ').where((w) => w.isNotEmpty).length;
    final now = DateTime.tryParse(_readingId) ?? DateTime.now();
    final label = sourceType.isEmpty ? 'Document' : _cap(sourceType);

    LibraryStorage.addItem(
      LibraryItem(
        language: widget.language ?? AppSettings.language,
        title: '$label · ${wordCount}w · ${now.day}/${now.month}/${now.year}',
        content: content,
        originalText: widget.originalText ?? _formatResult?.originalText,
        date: now,
        sourceType: sourceType,
      ),
    );
  }

  String _cap(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  // ── accessibility theme helpers ───────────────────────────────────────────
  Color getBackgroundColor() => AccessibilitySettings.backgroundColor();
  Color getTextColor() => AccessibilitySettings.textColor();

  // ── TTS ───────────────────────────────────────────────────────────────────
  void startReading() async {
    if (!mounted || simplifiedText.isEmpty) return;
    if (_speaking) {
      _paused = true;
      await _savePosition();
      await _tts.stop();
      if (mounted) setState(() => _speaking = false);
      return;
    }
    _speechOffset = _paused
        ? _pausedOffset.clamp(0, simplifiedText.length - 1)
        : 0;
    _paused = false;
    await _tts.setRate(speechRate);
    if (!mounted) return;
    setState(() => _speaking = true);
    await _tts.speak(
      simplifiedText.substring(_speechOffset),
      language: widget.language,
    );
    if (mounted) setState(() => _speaking = _tts.isSpeaking);
  }

  void stopReading() {
    _paused = false;
    _pausedOffset = 0;
    _speechOffset = 0;
    _tts.stop();
    if (mounted) {
      setState(() {
        _speaking = false;
        currentIndex = -1;
      });
    }
  }

  void repeatSentence() async {
    final before = simplifiedText.substring(
      0,
      _pausedOffset.clamp(0, simplifiedText.length),
    );
    final boundaries = RegExp(r'[.!?।]\s+').allMatches(before);
    final start = boundaries.isEmpty ? 0 : boundaries.last.end;
    _paused = true;
    await _tts.stop();
    _pausedOffset = start;
    _speaking = false;
    startReading();
  }

  void selectVersion(bool original) {
    stopReading();
    setState(() {
      _originalSelected = original;
      simplifiedText = original ? widget.originalText! : _resultText;
      words = _splitToWords(simplifiedText);
    });
  }

  Future<void> _savePosition() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('reading_position_$_readingId', _pausedOffset);
    await prefs.setBool('reading_original_$_readingId', _originalSelected);
  }

  Future<void> _restorePosition() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted || widget.readingId == null) return;
    final original = prefs.getBool('reading_original_$_readingId') ?? false;
    setState(() {
      if (original && widget.originalText != null) {
        _originalSelected = true;
        simplifiedText = widget.originalText!;
        words = _splitToWords(simplifiedText);
      }
      _pausedOffset = (prefs.getInt('reading_position_$_readingId') ?? 0).clamp(
        0,
        simplifiedText.length,
      );
      _paused = _pausedOffset > 0 && _pausedOffset < simplifiedText.length;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_savePosition());
      if (_speaking) startReading();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_savePosition());
    _tts.dispose();
    super.dispose();
  }

  // ── profile chip selector ─────────────────────────────────────────────────
  Widget _profileSelector() {
    final active = _isCustomize ? 'customize' : _selectedProfile;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final value in ['mild', 'moderate', 'severe', 'customize'])
          ChoiceChip(
            label: Text(
              {
                'mild': 'Light',
                'moderate': 'Comfort',
                'severe': 'Focus',
                'customize': 'Customize',
              }[value]!,
            ),
            avatar: value == 'customize'
                ? const Icon(Icons.tune, size: 18)
                : null,
            selected: active == value,
            onSelected: (_) => _onProfileChanged(value),
          ),
      ],
    );
  }

  // ── profile changed ───────────────────────────────────────────────────────
  Future<void> _onProfileChanged(String profile) async {
    if (profile == 'customize') {
      // Customize is purely client-side.
      setState(() => _isCustomize = true);
      AccessibilitySettings.profile = 'customize';
      await showReadingCustomizeSheet(
        context,
        onChanged: () {
          if (mounted) setState(() {});
        },
        detectedText: words.join(' '),
      );
      return;
    }

    // Preset selected — apply client-side accessibility settings.
    AccessibilitySettings.applyPreset(profile);
    await AccessibilitySettings.save();
    if (!mounted) return;

    setState(() {
      _selectedProfile = profile;
      _isCustomize = false;
    });
  }

  // ── formatting info bar ───────────────────────────────────────────────────
  Widget _formattingInfoBar() => Card(
    child: ExpansionTile(
      title: const Text('Reading appearance'),
      subtitle: Text('Adjust font, spacing, colour and focus tools'),
      childrenPadding: const EdgeInsets.all(16),
      children: [
        _profileSelector(),
        const SizedBox(height: 12),
        Text(
          'Text size ${AccessibilitySettings.fontSize.toStringAsFixed(0)} · '
          'Line spacing ${AccessibilitySettings.lineHeight.toStringAsFixed(1)}. '
          'Use Customize to adjust the page for comfortable reading.',
        ),
      ],
    ),
  );

  // ── primary (blue gradient) button — Start / Stop ─────────────────────────
  // ── empty state — no content was provided to this screen ─────────────────
  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMD),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.menu_book_outlined,
            size: 44,
            color: AppTheme.primaryBlue.withValues(alpha: 0.35),
          ),
          const SizedBox(height: AppTheme.spaceMD),
          Text(
            'Nothing to read yet',
            style: AppTheme.titleStyle,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTheme.spaceXS),
          Text(
            'Go back and scan, type, or upload some content first.',
            style: AppTheme.captionStyle,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTheme.spaceLG),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back, color: AppTheme.primaryBlue),
              label: const Text(
                'Go Back',
                style: TextStyle(color: AppTheme.primaryBlue),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: const BorderSide(color: AppTheme.primaryBlue, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMD),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── reading card — the formatted/simplified content ───────────────────────
  Widget _readingCard() {
    final structuredBlocks =
        _formatResult?.structuredContent?['blocks'] as List?;
    final hasStructuredLayout =
        structuredBlocks?.any(
          (block) => block is Map && block['type'] != 'paragraph',
        ) ??
        false;
    final originalText = _formatResult?.originalText;

    return Container(
      padding: const EdgeInsets.all(AppTheme.spaceMD),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMD),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(AppTheme.spaceMD),
        decoration: BoxDecoration(
          color: getBackgroundColor(),
          borderRadius: BorderRadius.circular(AppTheme.radiusSM),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (hasStructuredLayout)
              StructuredContentView(
                content: _formatResult!.structuredContent!,
                onWordTap: (word) {
                  stopReading();
                  showWordHelp(
                    context,
                    word,
                    widget.language ?? AppSettings.language,
                  );
                },
              )
            else
              HighlightedTextView(
                text: simplifiedText,
                words: words,
                currentIndex: currentIndex,
                onWordTap: (word) {
                  stopReading();
                  showWordHelp(
                    context,
                    word,
                    widget.language ?? AppSettings.language,
                  );
                },
              ),
            if (originalText != null && originalText.trim().isNotEmpty) ...[
              const SizedBox(height: AppTheme.spaceMD),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 4),
                title: Text(
                  'View original OCR',
                  style: TextStyle(
                    color: AppTheme.primaryBlue,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                initiallyExpanded: _showOriginalOcr,
                onExpansionChanged: (expanded) =>
                    setState(() => _showOriginalOcr = expanded),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(
                      originalText,
                      style: TextStyle(
                        color: getTextColor().withValues(alpha: 0.82),
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Focus Line Mode overlay ───────────────────────────────────────────────
  //
  // Dims content above and below a draggable horizontal band.
  // The dimming rectangles use IgnorePointer so they never block
  // scrolling or text interaction. Only the drag handle absorbs events.
  Widget _focusLineOverlay(double bodyHeight) {
    const bandH = 72.0;
    final fy = (_focusLineY ?? bodyHeight * 0.45).clamp(
      bandH / 2,
      bodyHeight - bandH / 2,
    );
    final bandTop = fy - bandH / 2;

    return Stack(
      children: [
        // ── Upper dim ──────────────────────────────────────────────────────
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: bandTop,
          child: IgnorePointer(
            child: Container(color: Colors.black.withValues(alpha: 0.30)),
          ),
        ),
        // ── Lower dim ──────────────────────────────────────────────────────
        Positioned(
          top: bandTop + bandH,
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            child: Container(color: Colors.black.withValues(alpha: 0.30)),
          ),
        ),
        // ── Top border of focus band ───────────────────────────────────────
        Positioned(
          top: bandTop,
          left: 0,
          right: 0,
          height: 2,
          child: IgnorePointer(
            child: Container(
              color: AppTheme.primaryBlue.withValues(alpha: 0.75),
            ),
          ),
        ),
        // ── Bottom border of focus band ────────────────────────────────────
        Positioned(
          top: bandTop + bandH - 2,
          left: 0,
          right: 0,
          height: 2,
          child: IgnorePointer(
            child: Container(
              color: AppTheme.primaryBlue.withValues(alpha: 0.75),
            ),
          ),
        ),
        // ── Drag handle — only interactive element ─────────────────────────
        Positioned(
          top: bandTop + (bandH / 2) - 16,
          right: 10,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (d) => setState(() {
              _focusLineY = (fy + d.delta.dy).clamp(
                bandH / 2,
                bodyHeight - bandH / 2,
              );
            }),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: const Icon(Icons.swap_vert, color: Colors.white, size: 16),
            ),
          ),
        ),
      ],
    );
  }

  // ── Reading Ruler overlay ─────────────────────────────────────────────────
  //
  // A thin horizontal guide line the user can drag freely. The line itself
  // is IgnorePointer so it never blocks scrolling; only the circular handle
  // on the right absorbs pan events.
  Widget _readingRulerOverlay(double bodyHeight) {
    final ry = (_rulerY ?? bodyHeight * 0.3).clamp(4.0, bodyHeight - 4.0);

    return Stack(
      children: [
        // ── Ruler line ─────────────────────────────────────────────────────
        Positioned(
          top: ry,
          left: 0,
          right: 48,
          height: 3,
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withValues(alpha: 0.80),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.30),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
        ),
        // ── Drag handle ────────────────────────────────────────────────────
        Positioned(
          top: ry - 16,
          right: 10,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (d) => setState(() {
              _rulerY = (ry + d.delta.dy).clamp(4.0, bodyHeight - 4.0);
            }),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: const Icon(
                Icons.drag_indicator,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final hasContent = simplifiedText.isNotEmpty;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,

      appBar: AppBar(title: const Text('Your reading')),

      body: LayoutBuilder(
        builder: (context, constraints) {
          // Lazy initialisation — set once per session, then user can drag.
          _focusLineY ??= constraints.maxHeight * 0.45;
          _rulerY ??= constraints.maxHeight * 0.30;

          return Stack(
            children: [
              // ── Scrollable reading content ─────────────────────────────
              Padding(
                padding: const EdgeInsets.all(AppTheme.spaceMD),
                child: ListView(
                  children: [
                    // ── PROFILE SELECTOR ──────────────────────────────────
                    const SizedBox(height: AppTheme.spaceSM),

                    // ── FORMATTING INFO BAR ───────────────────────────────
                    _formattingInfoBar(),

                    const SizedBox(height: AppTheme.spaceMD),

                    if (!hasContent) ...[
                      _emptyState(),
                    ] else ...[
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            onPressed: startReading,
                            icon: const Icon(Icons.volume_up_outlined),
                            label: Text(
                              _speaking
                                  ? 'Pause'
                                  : (_paused ? 'Resume' : 'Listen'),
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: stopReading,
                            icon: const Icon(Icons.stop_rounded),
                            label: const Text('Stop'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Voice speed: ${speechRate < .35
                            ? 'Slow'
                            : speechRate > .55
                            ? 'Fast'
                            : 'Normal'}',
                      ),
                      Slider(
                        value: speechRate,
                        min: 0.1,
                        max: 0.8,
                        divisions: 7,
                        label: speechRate < .35
                            ? 'Slow'
                            : speechRate > .55
                            ? 'Fast'
                            : 'Normal',
                        onChanged: (v) {
                          setState(() => speechRate = v);
                          _tts.setRate(v);
                        },
                      ),
                      if (widget.originalText != null &&
                          widget.originalText != _resultText)
                        Wrap(
                          spacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('Original'),
                              selected: _originalSelected,
                              onSelected: (_) => selectVersion(true),
                            ),
                            ChoiceChip(
                              label: const Text('Simplified'),
                              selected: !_originalSelected,
                              onSelected: (_) => selectVersion(false),
                            ),
                          ],
                        ),
                      TextButton.icon(
                        onPressed: repeatSentence,
                        icon: const Icon(Icons.replay),
                        label: const Text('Repeat sentence'),
                      ),
                      if (widget.simplificationRequested &&
                          widget.originalText?.trim() == _resultText.trim())
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'The model did not produce a simpler version. Showing your original text.',
                          ),
                        ),
                      _readingCard(),
                    ],
                  ],
                ),
              ),

              // ── Accessibility overlays (above scroll, non-blocking) ─────
              // Focus Line Mode: dims content above/below a draggable band.
              // Reduce Motion: overlays appear/disappear instantly (no
              // animation) — already the case since we use `if` not
              // AnimatedSwitcher.
              if (AccessibilitySettings.focusLineMode)
                _focusLineOverlay(constraints.maxHeight),

              // Reading Ruler: a draggable horizontal guide line.
              if (AccessibilitySettings.readingRuler)
                _readingRulerOverlay(constraints.maxHeight),
            ],
          );
        },
      ),
    );
  }
}
