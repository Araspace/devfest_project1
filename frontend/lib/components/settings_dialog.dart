// Settings: backend address and whether the Approver agent may decide clear cases.

import 'package:flutter/material.dart';

import '../services/settings.dart';
import '../theme.dart';

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});
  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  final _backend = TextEditingController(text: Settings.backendUrl);
  bool _auto = Settings.autoApprove;

  @override
  void dispose() {
    _backend.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      title: Text('Settings', style: headline(22)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Backend URL', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(controller: _backend),
            const SizedBox(height: 6),
            const Text(
              'The Gemini key and model are configured on the backend.',
              style: TextStyle(color: Brand.muted, fontSize: 13),
            ),
            const SizedBox(height: 20),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: Brand.orange,
              title: const Text('Let the Approver agent decide'),
              subtitle: const Text(
                'Clear cases are approved or rejected automatically. Unclear ones still come to you.',
              ),
              value: _auto,
              onChanged: (v) => setState(() => _auto = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            Settings.backendUrl = _backend.text;
            Settings.autoApprove = _auto;
            Navigator.pop(context);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
