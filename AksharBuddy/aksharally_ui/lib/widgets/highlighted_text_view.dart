import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/accessibility_settings.dart';
import '../theme/app_theme.dart';

/// Paragraph-aware, word-highlighting text renderer.
///
/// Extracted from ReaderScreen (Phase 3A migration) with no behavior
/// changes: same paragraph-marker splitting, same font resolution rules,
/// same highlight color/weight rules. Used by both OutputScreen and ReaderScreen.
class HighlightedTextView extends StatelessWidget {
  /// Raw display text. Only used to detect the "empty" placeholder state —
  /// rendering itself uses [words].
  final String text;

  /// Pre-split word list (see [splitToWords]). Paragraph breaks are
  /// represented by [paragraphMarker] entries and are never rendered as
  /// text or spoken by TTS.
  final List<String> words;

  /// Index into [words] that should be highlighted (e.g. the word currently
  /// being spoken). Pass -1 for no highlight.
  final int currentIndex;
  final ValueChanged<String>? onWordTap;

  const HighlightedTextView({
    super.key,
    required this.text,
    required this.words,
    required this.currentIndex,
    this.onWordTap,
  });

  /// Marks paragraph breaks in the words list (never spoken by TTS).
  static const String paragraphMarker = '¶';

  /// Marks a single source line break so OCR rows and menu items stay
  /// visually separate in the reading view.
  static const String lineBreakMarker = '↵';

  /// Splits raw text into words while retaining paragraph and line breaks.
  ///
  /// Single line breaks are meaningful for OCR output: they can separate
  /// table rows, menu items, headings, and columns. They are kept as markers
  /// rather than silently collapsed into spaces.
  static List<String> splitToWords(String text) {
    final normalized = text.replaceAll('\r\n', '\n');
    final words = <String>[];
    final paragraphs = normalized.split('\n\n');

    for (
      var paragraphIndex = 0;
      paragraphIndex < paragraphs.length;
      paragraphIndex++
    ) {
      final lines = paragraphs[paragraphIndex].split('\n');
      for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
        words.addAll(
          lines[lineIndex]
              .split(RegExp(r'[^\S\n]+'))
              .where((word) => word.isNotEmpty),
        );
        if (lineIndex < lines.length - 1) {
          words.add(lineBreakMarker);
        }
      }
      if (paragraphIndex < paragraphs.length - 1) {
        words.add(paragraphMarker);
      }
    }
    return words;
  }

  /// Maps native UTF-16 speech offsets to display words, skipping layout markers.
  static int wordIndexAtOffset(
    String text,
    List<String> words,
    int start,
    int end,
  ) {
    var cursor = 0;
    for (var index = 0; index < words.length; index++) {
      final word = words[index];
      if (word == paragraphMarker || word == lineBreakMarker) continue;
      final position = text.indexOf(word, cursor);
      if (position < 0) continue;
      final wordEnd = position + word.length;
      if (start < wordEnd && end > position) return index;
      cursor = wordEnd;
    }
    return -1;
  }

  /// Returns a [TextStyle] using the font selected in AccessibilitySettings.
  ///
  /// Google Fonts: Lexend, Atkinson Hyperlegible, Noto Sans, Inter, Roboto,
  /// Comic Neue. Platform fonts (Verdana, Tahoma, Arial, Georgia, Trebuchet MS)
  /// use the system font stack with Lexend as fallback.
  /// OpenDyslexic uses the bundled TTF asset (registered in pubspec.yaml).
  /// System Default uses plain TextStyle with no font override.
  TextStyle _resolveFont({
    required double size,
    required double height,
    required double letterSp,
    required double wordSp,
    required Color color,
    FontWeight weight = FontWeight.normal,
  }) {
    final base = TextStyle(
      fontSize: size,
      height: height,
      letterSpacing: letterSp,
      wordSpacing: wordSp,
      color: color,
      fontWeight: weight,
    );
    switch (AccessibilitySettings.fontFamily) {
      case 'Atkinson Hyperlegible':
        return GoogleFonts.atkinsonHyperlegible(textStyle: base);
      case 'Noto Sans':
        return GoogleFonts.notoSans(textStyle: base);
      case 'Inter':
        return GoogleFonts.inter(textStyle: base);
      case 'Roboto':
        return GoogleFonts.roboto(textStyle: base);
      case 'Comic Neue':
        return GoogleFonts.comicNeue(textStyle: base);
      // ── Devanagari fonts — Hindi & Marathi ────────────────────────────────
      case 'Mukta':
        // Clean Devanagari letterforms selected for strong readability.
        return GoogleFonts.mukta(
          textStyle: base,
        ).copyWith(fontFamilyFallback: const ['Noto Sans Devanagari']);
      case 'Noto Sans Devanagari':
        // Broad Unicode coverage and reliable Devanagari rendering.
        return GoogleFonts.notoSansDevanagari(
          textStyle: base,
        ).copyWith(fontFamilyFallback: const ['Mukta']);
      case 'Hind':
        // Designed for Hindi interfaces and screen readability.
        return GoogleFonts.hind(
          textStyle: base,
        ).copyWith(fontFamilyFallback: const ['Mukta', 'Noto Sans Devanagari']);
      case 'Baloo 2':
        // Friendly rounded shapes for younger or beginner readers.
        return GoogleFonts.baloo2(
          textStyle: base,
        ).copyWith(fontFamilyFallback: const ['Mukta', 'Noto Sans Devanagari']);
      case 'Tiro Devanagari Hindi':
        // Comfortable long-form reading for sustained attention.
        return GoogleFonts.tiroDevanagariHindi(
          textStyle: base,
        ).copyWith(fontFamilyFallback: const ['Mukta', 'Noto Sans Devanagari']);
      // Platform font families — use system stack, Lexend as fallback
      case 'Verdana':
      case 'Tahoma':
      case 'Arial':
      case 'Georgia':
      case 'Trebuchet MS':
        return base.copyWith(
          fontFamily: AccessibilitySettings.fontFamily,
          fontFamilyFallback: const ['Lexend'],
        );
      case 'System Default':
        return base.copyWith(
          fontFamily: 'BuddySans',
        ); // Bundled neutral sans serif
      case 'OpenDyslexic':
        // Bundled asset font — registered in pubspec.yaml under family: OpenDyslexic
        return base.copyWith(fontFamily: 'OpenDyslexic');
      case 'Lexend':
      default:
        return GoogleFonts.lexend(textStyle: base);
    }
  }

  // ── Syllabification ────────────────────────────────────────────────────────

  /// Applies English syllable breaks for *visual display only*.
  ///
  /// Algorithm: common suffix stripping → VCCV consonant-cluster splitting.
  ///
  /// Verified examples:
  ///   "reading"   → "read-ing"   (suffix -ing)
  ///   "important" → "im-por-tant" (VCCV: mp, rt)
  ///   "butter"    → "but-ter"    (VCCV: tt)
  ///
  /// Known limitation: VCV-only patterns (e.g. "education") are split at
  /// the suffix boundary only → "educa-tion" rather than "ed-u-ca-tion".
  /// A working approximation per spec; original text is never modified.
  static String _syllabifyWord(String word) {
    if (word.length < 4) return word;
    // Only process pure-alphabetic tokens (skip numbers, punctuated words, etc.)
    if (!RegExp(r'^[a-zA-Z]+$').hasMatch(word)) return word;

    // Ordered from longest to shortest to avoid partial matches
    // (e.g. match 'tion' before 'on').
    const suffixes = [
      'tion',
      'sion',
      'ness',
      'ment',
      'ance',
      'ence',
      'ible',
      'able',
      'ery',
      'ary',
      'ory',
      'ful',
      'less',
      'ous',
      'ive',
      'ing',
      'ly',
      'al',
    ];

    for (final suf in suffixes) {
      final lc = word.toLowerCase();
      if (lc.endsWith(suf) && word.length - suf.length >= 2) {
        final stem = word.substring(0, word.length - suf.length);
        if (stem.isEmpty) continue;
        // Only split if the stem itself contains at least one vowel
        // (avoids orphaned consonant clusters like "str-ong").
        if (!stem.split('').any((c) => 'aeiouAEIOU'.contains(c))) continue;
        return '${_splitCore(stem)}-$suf';
      }
    }
    return _splitCore(word);
  }

  /// VCCV consonant-cluster splitting on a word with no suffix.
  ///
  /// Inserts a hyphen after the first consonant in any V-C₁-C₂-V sequence,
  /// unless C₁C₂ is a protected digraph or blend that must never be split.
  static String _splitCore(String word) {
    if (word.length < 4) return word;

    const vowels = 'aeiouAEIOU';
    bool isV(String c) => vowels.contains(c);

    // Digraphs and onset clusters that must stay together
    const noSplit = {
      'ch',
      'sh',
      'th',
      'ph',
      'wh',
      'gh',
      'ck',
      'qu',
      'ng',
      'bl',
      'br',
      'cl',
      'cr',
      'dr',
      'fl',
      'fr',
      'gl',
      'gr',
      'pl',
      'pr',
      'sc',
      'sk',
      'sl',
      'sm',
      'sn',
      'sp',
      'st',
      'sw',
      'tr',
      'tw',
    };

    final buf = StringBuffer();
    for (int i = 0; i < word.length; i++) {
      buf.write(word[i]);
      // VCCV check: insert hyphen after word[i] (the c₁ we just wrote) when:
      //   word[i-1] is a vowel (v1)
      //   word[i]   is a consonant (c1)   ← already written
      //   word[i+1] is a consonant (c2)
      //   word[i+2] is a vowel (v2)
      if (i >= 1 && i + 2 < word.length) {
        final v1 = word[i - 1];
        final c1 = word[i];
        final c2 = word[i + 1];
        final v2 = word[i + 2];
        if (isV(v1) && !isV(c1) && !isV(c2) && isV(v2)) {
          final pair = '${c1.toLowerCase()}${c2.toLowerCase()}';
          if (!noSplit.contains(pair)) {
            buf.write('-');
          }
        }
      }
    }
    return buf.toString();
  }

  // ── Word widget ────────────────────────────────────────────────────────────

  Widget _wordWidget(int index, Color textColor) {
    final isHighlighted =
        index == currentIndex && AccessibilitySettings.wordHighlighting;

    // Syllable breakdown is display-only — original words[] list is never mutated.
    final displayWord = AccessibilitySettings.syllableBreakdown
        ? _syllabifyWord(words[index])
        : words[index];

    final label = Text(
      displayWord,
      style: _resolveFont(
        size: AccessibilitySettings.fontSize,
        height: AccessibilitySettings.lineHeight,
        letterSp: AccessibilitySettings.letterSpacing,
        wordSp: AccessibilitySettings.wordSpacing,
        color: isHighlighted ? const Color(0xFF172219) : textColor,
        weight: FontWeight.normal,
      ).copyWith(backgroundColor: isHighlighted ? AppTheme.lime : null),
    );
    if (onWordTap == null) return label;
    return Semantics(
      button: true,
      label: 'Explain ${words[index]}',
      child: InkWell(
        onTap: () => onWordTap!(words[index]),
        borderRadius: BorderRadius.circular(6),
        child: label,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).accessibleNavigation) {
      return SelectableText(
        text,
        style: TextStyle(
          fontSize: AccessibilitySettings.fontSize,
          height: AccessibilitySettings.lineHeight,
          color: AccessibilitySettings.textColor(),
        ),
      );
    }
    final Color textColor = AccessibilitySettings.textColor();

    if (text.isEmpty) {
      return Text(
        'Formatted text will appear here...',
        style: _resolveFont(
          size: AccessibilitySettings.fontSize,
          height: AccessibilitySettings.lineHeight,
          letterSp: AccessibilitySettings.letterSpacing,
          wordSp: AccessibilitySettings.wordSpacing,
          color: textColor.withValues(alpha: 0.5),
        ),
      );
    }

    final double wSpacing = AccessibilitySettings.wordSpacing;
    final double pSpacing = AccessibilitySettings.paragraphSpacing;

    final List<Widget> sections = [];
    List<Widget> currentParagraph = [];

    void flush() {
      if (currentParagraph.isNotEmpty) {
        sections.add(
          Wrap(
            spacing: wSpacing,
            runSpacing: 4.0,
            children: List.from(currentParagraph),
          ),
        );
        currentParagraph = [];
      }
    }

    for (int i = 0; i < words.length; i++) {
      if (words[i] == paragraphMarker) {
        flush();
        sections.add(SizedBox(height: pSpacing));
      } else if (words[i] == lineBreakMarker) {
        flush();
        sections.add(const SizedBox(height: 4));
      } else {
        currentParagraph.add(_wordWidget(i, textColor));
      }
    }
    flush();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: sections,
    );
  }
}
