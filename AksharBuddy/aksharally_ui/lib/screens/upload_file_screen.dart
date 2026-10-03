import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../services/api_service.dart';
import '../services/library_storage.dart';
import '../models/library_item.dart';
import 'reader_screen.dart';

class UploadFileScreen extends StatefulWidget {
  const UploadFileScreen({super.key});

  @override
  State<UploadFileScreen> createState() => _UploadFileScreenState();
}

class _UploadFileScreenState extends State<UploadFileScreen> {
  File? selectedFile;
  String fileName = "No file selected";
  bool isLoading = false;

  static const blueGradient = [Color(0xFF1565C0), Color(0xFF42A5F5)];
  static const creamGradient = [Color(0xFFFFF3E0), Color(0xFFFFE0B2)];
  static const yellowGradient = [Color(0xFFFFF59D), Color(0xFFFFF176)];

  // ── pick any supported document ───────────────────────────────────────────
  Future<void> pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx', 'jpg', 'jpeg', 'png'],
    );

    if (result != null) {
      setState(() {
        selectedFile = File(result.files.single.path!);
        fileName = result.files.single.name;
      });
    }
  }

  // ── upload to backend and open ReaderScreen ───────────────────────────────
  Future<void> processFile() async {
    if (selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a file first")),
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      // /api/format-text accepts images, PDFs, and DOCX via the 'file' field
      final result = await ApiService.processImage(selectedFile!);

      // Save to library before navigating
      _saveToLibrary(result.processedText, result.sourceType);

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReaderScreen(initialFormatResult: result),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("❌ Error processing file: $e")));
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  // ── library save ──────────────────────────────────────────────────────────
  void _saveToLibrary(String content, String sourceType) {
    if (content.isEmpty) return;
    final wordCount = content.split(' ').where((w) => w.isNotEmpty).length;
    final now = DateTime.now();
    final label = sourceType.isEmpty
        ? 'Document'
        : '${sourceType[0].toUpperCase()}${sourceType.substring(1)}';

    LibraryStorage.addItem(
      LibraryItem(
        title: '$label · ${wordCount}w · ${now.day}/${now.month}/${now.year}',
        content: content,
        date: now,
        sourceType: sourceType,
      ),
    );
  }

  // ── build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
            "Upload File",
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 22,
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
            // ── FILE NAME PREVIEW ─────────────────────────────────────────
            Container(
              height: 150,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    fileName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // ── CHOOSE FILE ───────────────────────────────────────────────
            _yellowButton(
              text: "Choose File",
              icon: Icons.upload_file,
              onTap: pickFile,
            ),

            const SizedBox(height: 15),

            // ── PROCESS FILE ──────────────────────────────────────────────
            _yellowButton(
              text: "Format File",
              icon: isLoading ? null : Icons.auto_fix_high,
              onTap: isLoading ? () {} : processFile,
              isLoading: isLoading,
            ),

            const SizedBox(height: 20),

            // ── SUPPORTED TYPES INFO ──────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                "Supported: JPG, PNG, PDF, DOCX\n"
                "Result opens in reader with dyslexia-friendly formatting.",
                style: TextStyle(color: Colors.black54, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),

      bottomNavigationBar: Container(
        height: 10,
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: creamGradient),
        ),
      ),
    );
  }

  // ── button helper ─────────────────────────────────────────────────────────
  Widget _yellowButton({
    required String text,
    required VoidCallback onTap,
    IconData? icon,
    bool isLoading = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
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
}
