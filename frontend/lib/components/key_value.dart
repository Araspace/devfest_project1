// Label + value pair; a missing value is shown in red as "missing".

import 'package:flutter/material.dart';

import '../theme.dart';

class KeyValue extends StatelessWidget {
  const KeyValue(this.label, this.value, {super.key});
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final v = value;
    return SizedBox(
      width: 230,
      child: Padding(
        padding: const EdgeInsets.only(right: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: const TextStyle(fontSize: 11, letterSpacing: 0.8, color: Brand.muted, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              v ?? 'missing',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: v == null ? Brand.danger : Brand.ink),
            ),
          ],
        ),
      ),
    );
  }
}
