class LibraryItem {
  final String? language;
  final String? originalText;
  final String title;
  final String content;
  final DateTime date;
  final String sourceType; // 'image' | 'pdf' | 'docx' | 'text' | 'simplified'

  LibraryItem({
    required this.title,
    this.language,
    this.originalText,
    required this.content,
    required this.date,
    this.sourceType = 'unknown',
  });

  // ── JSON serialisation ────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
    'language': language,
    'originalText': originalText,
    'title': title,
    'content': content,
    'date': date.toIso8601String(),
    'sourceType': sourceType,
  };

  factory LibraryItem.fromJson(Map<String, dynamic> json) => LibraryItem(
    language: json['language'] as String?,
    originalText: json['originalText'] as String?,
    title: json['title'] as String? ?? '',
    content: json['content'] as String? ?? '',
    date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
    sourceType: json['sourceType'] as String? ?? 'unknown',
  );
}
