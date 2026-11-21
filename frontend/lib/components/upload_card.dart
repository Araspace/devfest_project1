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
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: const BoxDecoration(color: Brand.purpleSoft, shape: BoxShape.circle),
              child: const Icon(Icons.upload_file_rounded, size: 36, color: Brand.purple),
            ),
            const SizedBox(height: 18),
            Text('Drop in an invoice', style: headline(26)),
            const SizedBox(height: 6),
            const Text('PDF, JPG, PNG, WEBP or TXT', style: TextStyle(color: Brand.muted)),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: busy ? null : _pick,
              icon: busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.add_rounded),
              label: Text(busy ? 'Agents at work…' : 'Choose invoice'),
            ),
          ],
        ),
      ),
    );
  }
}
