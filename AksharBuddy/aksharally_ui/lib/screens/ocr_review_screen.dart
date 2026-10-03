import 'dart:io';
import 'package:flutter/material.dart';

/// Review is required before any extracted words reach simplification or speech.
class OcrReviewScreen extends StatefulWidget {
  final String text;
  final File source;
  const OcrReviewScreen({super.key, required this.text, required this.source});
  @override
  State<OcrReviewScreen> createState() => _OcrReviewScreenState();
}

class _OcrReviewScreenState extends State<OcrReviewScreen> {
  late final TextEditingController _text = TextEditingController(
    text: widget.text,
  );
  String? _error;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = RegExp(
      r'\.(png|jpe?g|webp)$',
      caseSensitive: false,
    ).hasMatch(widget.source.path);
    return Scaffold(
      appBar: AppBar(title: const Text('Check your text')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Check names, numbers and sentence order. Correct any mistakes before reading or simplifying.',
            ),
            const SizedBox(height: 16),
            if (image)
              ExpansionTile(
                title: const Text('View source image'),
                children: [
                  SizedBox(
                    height: 260,
                    child: InteractiveViewer(
                      maxScale: 5,
                      child: Image.file(
                        widget.source,
                        errorBuilder: (_, e, stack) =>
                            const Text('Image preview is unavailable.'),
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _text,
              minLines: 8,
              maxLines: 24,
              decoration: InputDecoration(
                labelText: 'Extracted text',
                alignLabelWithHint: true,
                errorText: _error,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                if (_text.text.trim().isEmpty) {
                  setState(() => _error = 'Enter some text to continue.');
                  return;
                }
                Navigator.pop(context, _text.text.trim());
              },
              child: const Text('Continue with this text'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Choose another image or document'),
            ),
          ],
        ),
      ),
    );
  }
}
