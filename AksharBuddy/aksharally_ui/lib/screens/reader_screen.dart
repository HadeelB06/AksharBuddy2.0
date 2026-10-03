import '../widgets/word_help_sheet.dart';
import '../widgets/reading_session_panel.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import '../theme/app_settings.dart';
import '../widgets/highlighted_text_view.dart';
import '../widgets/structured_content_view.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import '../services/library_storage.dart';
import '../models/library_item.dart';
import '../models/format_result.dart';
import '../services/tts_service.dart';
import '../theme/accessibility_settings.dart';

class ReaderScreen extends StatefulWidget {
  /// Path A — Enter Text screen: AI-simplifies the text on open.
  final String? initialText;

  /// Path B — Upload File screen: displays a pre-formatted result immediately,
  ///           no extra API call.
  final FormatResult? initialFormatResult;

  /// Path C — Library screen: displays saved content directly, no API call,
  ///           no re-simplification.
  final String? displayText;
  final String? language;

  const ReaderScreen({
    super.key,
    this.initialText,
    this.initialFormatResult,
    this.displayText,
    this.language,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  // ── image & text state ────────────────────────────────────────────────────
  File? selectedImage;
  String simplifiedText = '';
  bool isLoading = false;

  // ── profile & format result ───────────────────────────────────────────────
  // _selectedProfile is the profile sent to the backend (always mild/moderate/severe).
  // _isCustomize tracks whether the 'Customize' chip is visually active.
  String _selectedProfile = 'moderate';
  bool _isCustomize = false;
  FormatResult? _formatResult;

  // ── TTS ───────────────────────────────────────────────────────────────────
  final TTSService _tts = TTSService();
  double speechRate = 0.4;
  bool autoRead = false;

  List<String> words = [];
  int currentIndex = -1;

  // Marks paragraph breaks in the words list (never spoken by TTS).

  // ── gradients ─────────────────────────────────────────────────────────────
  static const blueGradient = [Color(0xFF315B3A), Color(0xFF315B3A)];
  static const creamGradient = [Color(0xFFFFF3E0), Color(0xFFFFE0B2)];
  static const yellowGradient = [Color(0xFFFFF59D), Color(0xFFFFF176)];

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _tts.onProgress = (start, end) {
      if (!mounted) return;
      final index = HighlightedTextView.wordIndexAtOffset(
        simplifiedText,
        words,
        start,
        end,
      );
      if (index != currentIndex) setState(() => currentIndex = index);
    };
    _tts.onComplete = () {
      if (mounted) setState(() => currentIndex = -1);
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
      // Path B: pre-formatted result from UploadFileScreen
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadInitialFormatResult(widget.initialFormatResult!);
      });
    } else if (widget.displayText != null) {
      // Path C: saved library content — display as-is, no API call
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadDisplayText(widget.displayText!);
      });
    } else if (widget.initialText != null) {
      // Path A: run AI simplification
      simplifyInitialText();
    }
  }

  // ── word-splitting — removes embedded \n / \n\n ───────────────────────────
  List<String> _splitToWords(String text) =>
      HighlightedTextView.splitToWords(text);

  // ── Path B: load pre-formatted result ────────────────────────────────────
  void _loadInitialFormatResult(FormatResult r) {
    if (!mounted) return;
    stopReading();
    setState(() {
      _formatResult = r;
      simplifiedText = r.processedText;
      words = _splitToWords(r.processedText);
    });
    _saveToLibrary(r.processedText, r.sourceType);
    if (autoRead) _tts.setRate(speechRate).then((_) => startReading());
  }

  // ── Path C: load saved library text — no API call ─────────────────────────
  void _loadDisplayText(String text) {
    if (!mounted) return;
    stopReading();
    setState(() {
      simplifiedText = text;
      words = _splitToWords(text);
    });
    // Do NOT call _saveToLibrary here — already in library.
    // Do NOT call any backend endpoint.
    if (autoRead) _tts.setRate(speechRate).then((_) => startReading());
  }

  // ── Path A: AI simplify on open (Enter Text flow) ─────────────────────────
  Future<void> simplifyInitialText() async {
    setState(() {
      isLoading = true;
    });
    try {
      final result = await ApiService.simplifyText(widget.initialText!);
      setState(() {
        simplifiedText = result;
        words = _splitToWords(result);
      });
      _saveToLibrary(result, 'text');
      if (autoRead) {
        await _tts.setRate(speechRate);
        startReading();
      }
    } catch (e) {
      setState(() {
        simplifiedText = "❌ Error: $e";
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  // ── library save ──────────────────────────────────────────────────────────
  void _saveToLibrary(String content, String sourceType) {
    if (content.isEmpty ||
        content.startsWith('❌') ||
        content.startsWith('⚠️')) {
      return;
    }

    final wordCount = content.split(' ').where((w) => w.isNotEmpty).length;
    final now = DateTime.now();
    final label = sourceType.isEmpty ? 'Document' : _cap(sourceType);

    LibraryStorage.addItem(
      LibraryItem(
        language: widget.language ?? AppSettings.language,
        title: '$label · ${wordCount}w · ${now.day}/${now.month}/${now.year}',
        content: content,
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

  Future<void> pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        selectedImage = File(picked.path);
        simplifiedText = '';
        words = [];
        _formatResult = null;
      });
    }
  }

  // ── Format Text (OCR + dyslexia formatting, no AI) ────────────────────────
  Future<void> _onFormatPressed() async {
    if (selectedImage == null) {
      setState(() {
        simplifiedText = "⚠️ Please select an image first.";
      });
      return;
    }
    setState(() {
      isLoading = true;
    });
    try {
      final result = await ApiService.processImage(
        selectedImage!,
        profile: _selectedProfile, // always mild/moderate/severe
      );
      setState(() {
        _formatResult = result;
        simplifiedText = result.processedText;
        words = _splitToWords(result.processedText);
      });
      _saveToLibrary(result.processedText, 'image');
      if (autoRead) {
        await _tts.setRate(speechRate);
        startReading();
      }
    } catch (e) {
      setState(() {
        simplifiedText = "❌ Error: $e";
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  // ── Simplify (AI) ─────────────────────────────────────────────────────────
  Future<void> _onSimplifyPressed() async {
    if (simplifiedText.isEmpty ||
        simplifiedText.startsWith("⚠️") ||
        simplifiedText.startsWith("❌")) {
      setState(() {
        simplifiedText = "⚠️ Format an image first, then use Simplify.";
      });
      return;
    }
    setState(() {
      isLoading = true;
    });
    try {
      final result = await ApiService.simplifyText(simplifiedText);
      setState(() {
        simplifiedText = result;
        words = _splitToWords(result);
      });
      _saveToLibrary(result, 'simplified');
      if (autoRead) {
        await _tts.setRate(speechRate);
        startReading();
      }
    } catch (e) {
      setState(() {
        simplifiedText = "❌ Simplify error: $e";
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  // ── TTS ───────────────────────────────────────────────────────────────────
  void startReading() async {
    if (!mounted || simplifiedText.isEmpty) return;
    await _tts.setRate(speechRate);
    if (!mounted) return;
    await _tts.speak(simplifiedText, language: widget.language);
  }

  void stopReading() {
    _tts.stop();
  }

  @override
  void dispose() {
    _tts.dispose();
    super.dispose();
  }

  Widget buildHighlightedText() {
    final content = _formatResult?.structuredContent;
    final blocks = content?['blocks'] as List?;
    if (blocks?.any((block) => block is Map && block['type'] != 'paragraph') ??
        false) {
      return Column(
        children: [
          ReadingSessionPanel(text: () => simplifiedText),
          StructuredContentView(
            content: content!,
            onWordTap: (word) {
              stopReading();
              showWordHelp(
                context,
                word,
                widget.language ?? AppSettings.language,
              );
            },
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReadingSessionPanel(text: () => simplifiedText),
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
      ],
    );
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
      // Customize is purely client-side. Backend profile stays unchanged.
      setState(() => _isCustomize = true);
      AccessibilitySettings.profile = 'customize';
      await _showCustomizePanel();
      return;
    }

    // Preset selected — apply client-side settings and update backend profile.
    AccessibilitySettings.applyPreset(profile);
    await AccessibilitySettings.save();
    if (!mounted) return;

    setState(() {
      _selectedProfile = profile;
      _isCustomize = false;
    });
    // Backend is only called when the user presses "Format Text" or "Simplify";
    // simply updating _selectedProfile is sufficient — no API call here.
  }

  // ── customize panel ───────────────────────────────────────────────────────
  Future<void> _showCustomizePanel() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            // update() modifies AccessibilitySettings, repaints sheet, and
            // triggers parent rebuild so the text preview updates in real-time.
            void update(VoidCallback fn) {
              setSheet(fn);
              if (mounted) setState(() {});
            }

            final screenH = MediaQuery.of(ctx).size.height;

            return Container(
              height: screenH * 0.92,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  // Drag handle
                  const SizedBox(height: 12),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Header
                  Row(
                    children: [
                      const SizedBox(width: 16),
                      const Icon(Icons.tune, color: Color(0xFF1565C0)),
                      const SizedBox(width: 8),
                      const Text(
                        'Customize Reading Experience',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1565C0),
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const Divider(height: 1),
                  // Scrollable content
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        // ── FONT SELECTION ─────────────────────────────────
                        _sectionHeader('Font Family'),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: AccessibilitySettings.fonts.map((font) {
                            final sel =
                                AccessibilitySettings.fontFamily == font;
                            final shortLabel = font == 'Atkinson Hyperlegible'
                                ? 'Atkinson'
                                : font;
                            return GestureDetector(
                              onTap: () => update(
                                () => AccessibilitySettings.fontFamily = font,
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: sel
                                      ? const Color(0xFF1565C0)
                                      : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: sel
                                        ? const Color(0xFF1565C0)
                                        : Colors.grey.shade300,
                                  ),
                                ),
                                child: Text(
                                  shortLabel,
                                  style: TextStyle(
                                    color: sel ? Colors.white : Colors.black87,
                                    fontWeight: sel
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),

                        const SizedBox(height: 20),

                        // ── FONT SIZE ─────────────────────────────────────
                        _sectionHeader(
                          'Font Size  •  '
                          '${AccessibilitySettings.fontSize.toStringAsFixed(0)}px',
                        ),
                        Slider(
                          value: AccessibilitySettings.fontSize,
                          min: 14,
                          max: 36,
                          divisions: 44,
                          onChanged: (v) =>
                              update(() => AccessibilitySettings.fontSize = v),
                        ),

                        // ── LETTER SPACING ────────────────────────────────
                        _sectionHeader(
                          'Letter Spacing  •  '
                          '${AccessibilitySettings.letterSpacing.toStringAsFixed(1)}',
                        ),
                        Slider(
                          value: AccessibilitySettings.letterSpacing,
                          min: 0,
                          max: 3.0,
                          divisions: 30,
                          onChanged: (v) => update(
                            () => AccessibilitySettings.letterSpacing = v,
                          ),
                        ),

                        // ── WORD SPACING ──────────────────────────────────
                        _sectionHeader(
                          'Word Spacing  •  '
                          '${AccessibilitySettings.wordSpacing.toStringAsFixed(1)}',
                        ),
                        Slider(
                          value: AccessibilitySettings.wordSpacing,
                          min: 0,
                          max: 8.0,
                          divisions: 16,
                          onChanged: (v) => update(
                            () => AccessibilitySettings.wordSpacing = v,
                          ),
                        ),

                        // ── LINE HEIGHT ───────────────────────────────────
                        _sectionHeader(
                          'Line Height  •  '
                          '${AccessibilitySettings.lineHeight.toStringAsFixed(1)}×',
                        ),
                        Slider(
                          value: AccessibilitySettings.lineHeight,
                          min: 1.0,
                          max: 3.0,
                          divisions: 20,
                          onChanged: (v) => update(
                            () => AccessibilitySettings.lineHeight = v,
                          ),
                        ),

                        // ── PARAGRAPH SPACING ─────────────────────────────
                        _sectionHeader(
                          'Paragraph Spacing  •  '
                          '${AccessibilitySettings.paragraphSpacing.toStringAsFixed(0)}px',
                        ),
                        Slider(
                          value: AccessibilitySettings.paragraphSpacing,
                          min: 8,
                          max: 32,
                          divisions: 24,
                          onChanged: (v) => update(
                            () => AccessibilitySettings.paragraphSpacing = v,
                          ),
                        ),

                        const SizedBox(height: 8),
                        const Divider(),
                        const SizedBox(height: 8),

                        // ── COLOR THEMES ──────────────────────────────────
                        _sectionHeader('Color Theme'),
                        const SizedBox(height: 10),
                        Builder(
                          builder: (ctx2) {
                            final cardW =
                                (MediaQuery.of(ctx2).size.width - 48) / 2;
                            return Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: AccessibilitySettings.themeLabels.keys
                                  .map((key) {
                                    final bg = AccessibilitySettings.previewBg(
                                      key,
                                    );
                                    final text =
                                        AccessibilitySettings.previewText(key);
                                    final sel =
                                        AccessibilitySettings.colorTheme == key;
                                    return GestureDetector(
                                      onTap: () => update(
                                        () => AccessibilitySettings.colorTheme =
                                            key,
                                      ),
                                      child: Container(
                                        width: cardW,
                                        height: 52,
                                        decoration: BoxDecoration(
                                          color: bg,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(
                                            color: sel
                                                ? const Color(0xFF1565C0)
                                                : Colors.grey.shade300,
                                            width: sel ? 2.5 : 1,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            if (sel)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  right: 4,
                                                ),
                                                child: Icon(
                                                  Icons.check,
                                                  color: text,
                                                  size: 13,
                                                ),
                                              ),
                                            Text(
                                              AccessibilitySettings
                                                  .themeLabels[key]!,
                                              style: TextStyle(
                                                color: text,
                                                fontSize: 12,
                                                fontWeight: sel
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  })
                                  .toList(),
                            );
                          },
                        ),

                        const SizedBox(height: 8),
                        const Divider(),
                        const SizedBox(height: 4),

                        // ── ACCESSIBILITY FEATURES ────────────────────────
                        _sectionHeader('Accessibility Features'),
                        _toggle(
                          'Word Highlighting during TTS',
                          AccessibilitySettings.wordHighlighting,
                          (v) => update(
                            () => AccessibilitySettings.wordHighlighting = v,
                          ),
                        ),
                        _toggle(
                          'Focus Window',
                          AccessibilitySettings.focusLineMode,
                          (v) => update(
                            () => AccessibilitySettings.focusLineMode = v,
                          ),
                          subtitle: 'UI ready — coming soon',
                        ),
                        _toggle(
                          'Reading Ruler',
                          AccessibilitySettings.readingRuler,
                          (v) => update(
                            () => AccessibilitySettings.readingRuler = v,
                          ),
                          subtitle: 'UI ready — coming soon',
                        ),
                        _toggle(
                          'Syllable Breakdown (Experimental)',
                          AccessibilitySettings.syllableBreakdown,
                          (v) => update(
                            () => AccessibilitySettings.syllableBreakdown = v,
                          ),
                          subtitle: 'UI ready — coming soon',
                        ),
                        _toggle(
                          'Larger Touch Targets',
                          AccessibilitySettings.largerTouchTargets,
                          (v) => update(
                            () => AccessibilitySettings.largerTouchTargets = v,
                          ),
                        ),
                        _toggle(
                          'Reduce Motion / Animations',
                          AccessibilitySettings.reduceMotion,
                          (v) => update(
                            () => AccessibilitySettings.reduceMotion = v,
                          ),
                        ),

                        const SizedBox(height: 20),

                        // ── SAVE BUTTON ───────────────────────────────────
                        ElevatedButton.icon(
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Save as Default'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1565C0),
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: () async {
                            await AccessibilitySettings.save();
                            if (ctx.mounted) Navigator.of(ctx).pop();
                          },
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    // After the sheet closes, rebuild so the main screen reflects any changes
    // the user didn't explicitly save.
    if (mounted) setState(() {});
  }

  // ── customize panel helpers ───────────────────────────────────────────────
  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF555555),
        ),
      ),
    );
  }

  Widget _toggle(
    String label,
    bool value,
    ValueChanged<bool> onChanged, {
    String? subtitle,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label, style: const TextStyle(fontSize: 14)),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            )
          : null,
      value: value,
      onChanged: onChanged,
      dense: true,
    );
  }

  // ── formatting info bar ───────────────────────────────────────────────────
  Widget _formattingInfoBar() => Card(
    child: ExpansionTile(
      title: const Text('Reading appearance'),
      subtitle: Text(
        '${_isCustomize ? "Custom" : _cap(_selectedProfile)} · ${AccessibilitySettings.fontFamily}',
      ),
      childrenPadding: const EdgeInsets.all(16),
      children: [
        Text(
          'Text size ${AccessibilitySettings.fontSize.toStringAsFixed(0)} · '
          'Line spacing ${AccessibilitySettings.lineHeight.toStringAsFixed(1)}. '
          'Use Customize to adjust the page for comfortable reading.',
        ),
      ],
    ),
  );

  // ── button helper ─────────────────────────────────────────────────────────
  Widget _yellowButton(
    String text,
    VoidCallback onTap, {
    bool isLoading = false,
    IconData? icon,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: yellowGradient),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Center(
          child: isLoading
              ? const CircularProgressIndicator(color: Colors.black)
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, color: Colors.black),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      text,
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: getBackgroundColor(),

      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: creamGradient),
          ),
        ),
        title: ShaderMask(
          shaderCallback: (bounds) =>
              const LinearGradient(colors: blueGradient).createShader(bounds),
          child: const Text(
            'AksharBuddy',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
        ),
        centerTitle: true,
      ),

      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            // ── IMAGE PREVIEW ──────────────────────────────────────────────
            Container(
              height: 180,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(16),
              ),
              child: selectedImage == null
                  ? const Center(child: Text("📷 No image selected"))
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.file(selectedImage!, fit: BoxFit.cover),
                    ),
            ),

            const SizedBox(height: 10),

            // ── CHOOSE IMAGE ───────────────────────────────────────────────
            _yellowButton("Choose Image", pickImage),

            const SizedBox(height: 12),

            // ── PROFILE SELECTOR (mild / moderate / severe / customize) ────
            _profileSelector(),

            const SizedBox(height: 10),

            // ── FORMAT TEXT ────────────────────────────────────────────────
            _yellowButton(
              "Format Text",
              isLoading ? () {} : _onFormatPressed,
              isLoading: isLoading,
            ),

            const SizedBox(height: 10),

            // ── SIMPLIFY (AI) ──────────────────────────────────────────────
            _yellowButton(
              "Simplify (AI)",
              isLoading ? () {} : _onSimplifyPressed,
            ),

            const SizedBox(height: 10),

            // ── FORMATTING INFO BAR (always visible) ──────────────────────
            _formattingInfoBar(),

            const SizedBox(height: 10),

            // ── START / STOP ───────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: _yellowButton(
                    "Start",
                    startReading,
                    icon: Icons.play_arrow,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _yellowButton("Stop", stopReading, icon: Icons.stop),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // ── AUTO READ SWITCH ───────────────────────────────────────────
            SwitchListTile(
              title: Text("Auto Read", style: TextStyle(color: getTextColor())),
              value: autoRead,
              onChanged: (v) => setState(() => autoRead = v),
            ),

            const SizedBox(height: 20),

            // ── OUTPUT BOX ─────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: getBackgroundColor(),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: buildHighlightedText(),
            ),
          ],
        ),
      ),
    );
  }
}
