"""
Dyslexia Formatter — restructures extracted text for easier reading.

IMPORTANT: This module NEVER changes, translates, simplifies, or rewrites words.
It only adjusts visual structure and returns reading profile settings for the frontend.

Visual pipeline (words untouched at every step):
  raw text
    → split into sentences
    → group sentences into small chunks  (mild: 3, moderate: 2, severe: 1)
    → wrap each sentence at N words/line (mild: 12, moderate: 10, severe: 8)
    → join lines within a chunk with \n
    → join chunks with \n\n  (blank line between chunks)
"""

import re

# ── Reading profiles ──────────────────────────────────────────────────────────
# Field names match Flutter TextStyle parameters exactly so the client can
# pass them directly without any mapping:
#   fontSize         → TextStyle.fontSize
#   lineHeight       → TextStyle.height          (multiplier, e.g. 1.8)
#   letterSpacing    → TextStyle.letterSpacing   (logical pixels)
#   wordSpacing      → TextStyle.wordSpacing     (logical pixels)
#   paragraphSpacing → SizedBox height between paragraph chunks
#   recommendedFont  → font-family string for google_fonts lookup
PROFILES = {
    "mild": {
        "profile": "mild",
        "recommendedFont": "Lexend",
        "fontSize": 18.0,
        "lineHeight": 1.6,
        "letterSpacing": 0.5,
        "wordSpacing": 2.0,
        "paragraphSpacing": 12.0,
        "sentencesPerChunk": 3,
        "wordsPerLine": 12,
    },
    "moderate": {
        "profile": "moderate",
        "recommendedFont": "Lexend",
        "fontSize": 20.0,
        "lineHeight": 1.8,
        "letterSpacing": 1.0,
        "wordSpacing": 4.0,
        "paragraphSpacing": 16.0,
        "sentencesPerChunk": 2,
        "wordsPerLine": 10,
    },
    "severe": {
        "profile": "severe",
        "recommendedFont": "Lexend",
        "fontSize": 22.0,
        "lineHeight": 2.0,
        "letterSpacing": 1.5,
        "wordSpacing": 6.0,
        "paragraphSpacing": 20.0,
        "sentencesPerChunk": 1,
        "wordsPerLine": 8,
    },
}

DEFAULT_PROFILE = "moderate"

# Matches sentence-ending punctuation (. ! ?) followed by whitespace.
# Avoids splitting on common abbreviations like Mr. Dr. Fig. or decimals.
_ABBREV = re.compile(
    r'\b(?:Mr|Mrs|Ms|Dr|Prof|Sr|Jr|vs|Fig|Jan|Feb|Mar|Apr|Jun|Jul|Aug|Sep|Oct|Nov|Dec|'
    r'St|Ave|Blvd|Dept|approx|est|govt|no|vol|pp)\.'
    r'|\b\d+\.'              # "1. 2. 3." list markers
    r'|\b[A-Z]\.',           # single capital letters (initials)
    re.IGNORECASE,
)

_SENTENCE_SPLIT = re.compile(r'(?<=[.!?])\s+')


def _split_sentences(text: str) -> list[str]:
    """
    Split text into individual sentences while ignoring abbreviations,
    list markers, and initials.
    Existing paragraph breaks are dissolved — the formatter re-paragraphs.
    """
    # Normalise whitespace: collapse all runs of spaces/tabs
    text = re.sub(r'[ \t]+', ' ', text)

    # Collapse any multi-line runs into a single space so we work with flat text
    text = re.sub(r'\n+', ' ', text).strip()

    # Temporarily mask abbreviations so the sentence splitter ignores them
    placeholder = "\x00"
    masked = _ABBREV.sub(lambda m: m.group().replace('.', placeholder), text)

    # Split on sentence boundaries in the masked string
    raw_parts = _SENTENCE_SPLIT.split(masked)

    sentences = []
    for part in raw_parts:
        # Restore placeholders → real dots
        restored = part.replace(placeholder, '.').strip()
        if restored:
            sentences.append(restored)
    return sentences


def _wrap_sentence(sentence: str, words_per_line: int) -> str:
    """
    Wrap a single sentence so each line contains at most `words_per_line` words.
    The original words are never changed.

    Example (words_per_line=10):
      "As he leaned down he saw his reflection in the water and gasped in surprise."
      →
      "As he leaned down he saw his reflection in\nthe water and gasped in surprise."
    """
    words = sentence.split()
    if len(words) <= words_per_line:
        return sentence  # short sentence — no wrapping needed

    lines = []
    for i in range(0, len(words), words_per_line):
        lines.append(' '.join(words[i: i + words_per_line]))
    return '\n'.join(lines)


def _build_formatted(sentences: list[str], sentences_per_chunk: int,
                     words_per_line: int) -> str:
    """
    Group sentences into chunks, wrap each sentence at words_per_line,
    and return the final formatted string.

    Within a chunk: sentences are separated by \n.
    Between chunks: separated by \n\n (blank line).
    """
    chunks = []
    for i in range(0, len(sentences), sentences_per_chunk):
        group = sentences[i: i + sentences_per_chunk]
        # Wrap each sentence individually then join with a single newline
        wrapped_lines = [_wrap_sentence(s, words_per_line) for s in group]
        chunks.append('\n'.join(wrapped_lines))

    return '\n\n'.join(chunks)


def _preserve_layout(raw_text: str) -> str:
    """
    Preserve line-based OCR layout.

    OCR lines can represent table rows, menu items, headings, or separate
    columns. Flattening them into sentences makes those relationships
    impossible to recover, so multiline extraction is kept line-by-line.
    """
    lines = raw_text.strip().splitlines()
    output = []
    previous_blank = False
    for line in lines:
        cleaned = line.rstrip()
        if not cleaned.strip():
            if output and not previous_blank:
                output.append('')
            previous_blank = True
            continue
        output.append(cleaned)
        previous_blank = False
    return '\n'.join(output).strip()


def format_text(raw_text: str, profile_name: str = DEFAULT_PROFILE) -> dict:
    """
    Apply dyslexia-friendly formatting to raw extracted text.

    Args:
        raw_text:     The original extracted text — words are NEVER changed.
        profile_name: 'mild', 'moderate', or 'severe'. Defaults to 'moderate'.

    Returns a dict with:
        formattedText   — same words, wrapped to short lines, chunked into paragraphs
        readingProfile  — font/size/spacing settings for the Flutter renderer
        metadata        — word count, character count, paragraph count, reading time
    """
    profile_name = (profile_name or DEFAULT_PROFILE).lower()
    if profile_name not in PROFILES:
        profile_name = DEFAULT_PROFILE

    profile            = PROFILES[profile_name]
    sentences_per_chunk = profile["sentencesPerChunk"]
    words_per_line      = profile["wordsPerLine"]

    if '\n' in raw_text.strip():
        # Keep OCR/document structure intact. Typography settings are still
        # returned below for the Flutter renderer.
        formatted = _preserve_layout(raw_text)
    else:
        sentences = _split_sentences(raw_text)
        if not sentences:
            formatted = raw_text.strip()
        else:
            formatted = _build_formatted(
                sentences,
                sentences_per_chunk,
                words_per_line,
            )

    word_count      = len(raw_text.split())           # count from original, not formatted
    char_count      = len(raw_text)
    paragraph_count = len([p for p in formatted.split('\n\n') if p.strip()])
    # Dyslexic readers average ~130 wpm; minimum 1 s
    reading_time_seconds = max(1, round((word_count / 130) * 60))

    # Strip internal keys the Flutter client doesn't need
    _internal = {"sentencesPerChunk", "wordsPerLine"}
    display_profile = {k: v for k, v in profile.items() if k not in _internal}

    return {
        "formattedText":  formatted,
        "readingProfile": display_profile,
        "metadata": {
            "wordCount":                  word_count,
            "characterCount":             char_count,
            "paragraphCount":             paragraph_count,
            "estimatedReadingTimeSeconds": reading_time_seconds,
        },
    }
