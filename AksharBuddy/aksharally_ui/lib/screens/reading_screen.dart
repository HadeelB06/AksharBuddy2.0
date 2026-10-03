import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

import '../widgets/buddy_brand.dart';
import '../services/api_service.dart';
import '../theme/app_settings.dart';
import 'output_screen.dart';
import 'ocr_review_screen.dart';

/// Public enum so HomeScreen can specify which tab opens by default.
enum ReadingTab { scan, type, upload }

enum _ProcessMode { formatOnly, simplifyFormat }

class ReadingScreen extends StatefulWidget {
  final ReadingTab initialTab;
  final String? initialInput;

  const ReadingScreen({
    super.key,
    this.initialTab = ReadingTab.scan,
    this.initialInput,
  });

  @override
  State<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends State<ReadingScreen> {
  // ── Local UI state ─────────────────────────────────────────────────────────
  late ReadingTab _tab;
  _ProcessMode _mode = _ProcessMode.formatOnly;

  // Language and profile are LOCAL to this screen.
  // They are NEVER written to AppSettings — they are only passed into API
  // calls via the optional language: and profile: parameters.
  String _language = AppSettings.language;
  final String _profile = 'moderate';

  // Input state
  final _textController = TextEditingController();
  final _picker = ImagePicker();
  File? _pickedFile;
  String? _pickedFileName;

  // Processing state
  bool _isLoading = false;
  String _stage = 'Preparing text';
  String? _error;

  // ── Lifecycle ───────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;

    // Recover an image if Android recreated MainActivity
    // while the camera/gallery picker was open.
    _retrieveLostImage();
    if (widget.initialInput != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        switch (widget.initialInput) {
          case 'camera':
            _pickImage(ImageSource.camera);
            break;
          case 'image':
            _pickImage(ImageSource.gallery);
            break;
          case 'pdf':
            _pickFile(extensions: ['pdf']);
            break;
          case 'docx':
            _pickFile(extensions: ['docx']);
            break;
        }
      });
    }
  }

  Future<void> _retrieveLostImage() async {
    try {
      final LostDataResponse response = await _picker.retrieveLostData();

      if (response.isEmpty) return;

      if (response.files != null && response.files!.isNotEmpty) {
        final XFile xf = response.files!.first;
        final file = File(xf.path);

        if (!await file.exists()) return;
        if (await file.length() == 0) return;

        if (!mounted) return;

        setState(() {
          _pickedFile = file;
          _pickedFileName = xf.name;
          _error = null;
        });
      } else if (response.exception != null) {
        if (!mounted) return;

        setState(() {
          _error = response.exception.toString();
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  // ── Input helpers ───────────────────────────────────────────────────────────

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? xf = await _picker.pickImage(
        source: source,
        // Keep the camera's full-resolution capture. JPEG compression here
        // can remove small characters, punctuation, prices, and table lines.
        preferredCameraDevice: CameraDevice.rear,
      );
      if (xf == null) return;

      final file = File(xf.path);
      if (!await file.exists()) {
        throw Exception('The camera did not return a readable image.');
      }
      if (await file.length() == 0) {
        throw Exception('The captured image is empty. Please scan it again.');
      }

      setState(() {
        _pickedFile = file;
        _pickedFileName = xf.name;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _pickFile({List<String>? extensions}) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions:
            extensions ?? ['pdf', 'docx', 'txt', 'png', 'jpg', 'jpeg'],
      );
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.first;
      if (picked.path == null) return;
      setState(() {
        _pickedFile = File(picked.path!);
        _pickedFileName = picked.name;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = 'Could not open file picker.');
    }
  }

  void _clearPick() => setState(() {
    _pickedFile = null;
    _pickedFileName = null;
  });

  // ── Continue action ─────────────────────────────────────────────────────────

  Future<void> _onContinue() async {
    if (_tab == ReadingTab.type && _textController.text.trim().isEmpty) {
      setState(() => _error = 'Please enter some text before continuing.');
      return;
    }
    if (_tab != ReadingTab.type && _pickedFile == null) {
      setState(
        () => _error = _tab == ReadingTab.scan
            ? 'Please capture or select an image first.'
            : 'Please select a file first.',
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await _runPipelineAndNavigate();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  /// Executes the correct pipeline for the current tab + mode combination
  /// and pushes the result to ReaderScreen.
  ///
  /// Language and profile are passed EXPLICITLY to every API call.
  /// AppSettings is never mutated here.
  Future<void> _runPipelineAndNavigate() async {
    String original;
    if (_tab == ReadingTab.type) {
      original = _textController.text.trim();
    } else {
      final file = _pickedFile!;
      if (!await file.exists() || await file.length() == 0) {
        throw Exception('Choose the image or document again.');
      }
      final result = await ApiService.processImage(
        file,
        language: _language,
        profile: _profile,
        onProgress: (stage) {
          if (mounted) setState(() => _stage = stage);
        },
      );
      if (!mounted) return;
      final reviewed = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => OcrReviewScreen(text: result.rawText, source: file),
        ),
      );
      if (!mounted) return;
      if (reviewed == null) {
        setState(() => _isLoading = false);
        return;
      }
      original = reviewed;
      if (_mode == _ProcessMode.formatOnly &&
          reviewed == result.rawText.trim()) {
        _push(OutputScreen(language: _language, initialFormatResult: result));
        return;
      }
    }
    if (_mode == _ProcessMode.simplifyFormat && mounted) {
      setState(() => _stage = 'Simplifying text on laptop');
    }
    final display = _mode == _ProcessMode.simplifyFormat
        ? await ApiService.simplifyText(original, language: _language)
        : original;
    _push(
      OutputScreen(
        language: _language,
        displayText: display,
        originalText: original,
        simplificationRequested: _mode == _ProcessMode.simplifyFormat,
        saveOnLoad: true,
      ),
    );
  }

  void _push(Widget screen) {
    if (!mounted) return;
    setState(() => _isLoading = false);
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('New reading')),
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const BuddyHeading(
                  'Bring something to read',
                  'Choose your source. Keep the words, or ask for a simpler version.',
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ReadingTab.values
                      .map(
                        (tab) => ChoiceChip(
                          label: Text(
                            {
                              ReadingTab.scan: 'Photo',
                              ReadingTab.type: 'Text',
                              ReadingTab.upload: 'Document',
                            }[tab]!,
                          ),
                          selected: _tab == tab,
                          onSelected: _isLoading
                              ? null
                              : (_) => setState(() {
                                  _tab = tab;
                                  _error = null;
                                }),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 20),
                BuddyCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_tab == ReadingTab.type)
                        TextField(
                          controller: _textController,
                          minLines: 6,
                          maxLines: 16,
                          decoration: const InputDecoration(
                            labelText: 'Your text',
                            hintText: 'Type or paste here…',
                          ),
                        ),
                      if (_tab == ReadingTab.scan) ...[
                        const Text(
                          'A clear, well-lit photo gives the best starting point.',
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _isLoading
                              ? null
                              : () => _pickImage(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt_outlined),
                          label: const Text('Take a photo'),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _isLoading
                              ? null
                              : () => _pickImage(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined),
                          label: const Text('Choose an image'),
                        ),
                      ],
                      if (_tab == ReadingTab.upload) ...[
                        const Text(
                          'Choose a PDF or Word document from your device.',
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _isLoading
                              ? null
                              : () => _pickFile(extensions: ['pdf']),
                          icon: const Icon(Icons.picture_as_pdf_outlined),
                          label: const Text('Open PDF'),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _isLoading
                              ? null
                              : () => _pickFile(extensions: ['docx']),
                          icon: const Icon(Icons.description_outlined),
                          label: const Text('Open Word (.docx)'),
                        ),
                      ],
                      if (_pickedFile != null && _tab != ReadingTab.type) ...[
                        const SizedBox(height: 16),
                        Text(_pickedFileName ?? 'File selected'),
                        TextButton.icon(
                          onPressed: _isLoading ? null : _clearPick,
                          icon: const Icon(Icons.close),
                          label: const Text('Remove file'),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                BuddyCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Language of this reading',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children:
                            [
                                  ('en', 'English'),
                                  ('hi', 'Hindi'),
                                  ('mr', 'Marathi'),
                                ]
                                .map(
                                  (l) => ChoiceChip(
                                    label: Text(l.$2),
                                    selected: _language == l.$1,
                                    onSelected: _isLoading
                                        ? null
                                        : (_) =>
                                              setState(() => _language = l.$1),
                                  ),
                                )
                                .toList(),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'How would you like to read?',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children:
                            [
                                  (_ProcessMode.formatOnly, 'Keep my words'),
                                  (
                                    _ProcessMode.simplifyFormat,
                                    'Simplify with AI',
                                  ),
                                ]
                                .map(
                                  (m) => ChoiceChip(
                                    label: Text(m.$2),
                                    selected: _mode == m.$1,
                                    onSelected: _isLoading
                                        ? null
                                        : (_) => setState(() => _mode = m.$1),
                                  ),
                                )
                                .toList(),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _mode == _ProcessMode.formatOnly
                            ? 'Change the layout without rewriting your text.'
                            : 'Ask local model for simpler wording. Check important details against the original.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _onContinue,
                  icon: Icon(
                    _isLoading ? Icons.hourglass_top : Icons.arrow_forward,
                  ),
                  label: Text(_isLoading ? _stage : 'Open my reading'),
                ),
                if (_isLoading && _mode == _ProcessMode.simplifyFormat)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'The laptop loads the AI model once and reuses it. Keep both devices on the same Wi-Fi. Your original stays available.',
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
