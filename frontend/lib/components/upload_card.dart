// Upload area: picks one receipt file and hands it to [onFile].

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

class UploadCard extends StatelessWidget {
  const UploadCard({super.key, required this.busy, required this.onFile});
  final bool busy;
  final void Function(String name, String mimeType, Uint8List bytes) onFile;

  static const extensions = ['pdf', 'png', 'jpg', 'jpeg', 'webp', 'txt'];

  static String mimeOf(String name) => switch (name.split('.').last.toLowerCase()) {
    'pdf' => 'application/pdf',
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'webp' => 'image/webp',
    'txt' => 'text/plain',
    _ => 'application/octet-stream',
  };

  Future<void> _pick() async {
    final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: extensions);
    if (files.isEmpty) return;
    final f = files.first;
    onFile(f.name, mimeOf(f.name), await f.readAsBytes());
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          children: [
            const Icon(Icons.upload_file_outlined, size: 28, color: Brand.muted),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Upload an invoice', style: headline(16)),
                  const SizedBox(height: 4),
                  const Text(
                    'PDF, JPG, PNG, WEBP or TXT · max. 10 MB · treated as untrusted data',
                    style: TextStyle(color: Brand.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            FilledButton.icon(
              onPressed: busy ? null : _pick,
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.add_rounded),
              label: Text(busy ? 'Checking…' : 'Choose file'),
            ),
          ],
        ),
      ),
    );
  }
}
