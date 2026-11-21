// Collapsible audit log: every agent step and human decision, newest first.

import 'package:belegguard_shared/models.dart';
import 'package:flutter/material.dart';

import '../theme.dart';

class AuditLog extends StatelessWidget {
  const AuditLog({super.key, required this.log});
  final List<LogEntry> log;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 6),
          childrenPadding: const EdgeInsets.fromLTRB(28, 0, 28, 20),
          leading: const Icon(Icons.receipt_long_outlined),
          iconColor: Brand.accent,
          collapsedIconColor: Brand.accent,
          title: Text('Audit log', style: headline(16)),
          subtitle: Text('${log.length} events · newest first', style: const TextStyle(color: Brand.muted)),
          children: [
            if (log.isEmpty) const Align(alignment: Alignment.centerLeft, child: Text('No events yet.')),
            for (final e in log) _row(e),
          ],
        ),
      ),
    );
  }

  Widget _row(LogEntry e) {
    final dot = switch (e.level) {
      LogLevel.block => Brand.danger,
      LogLevel.warn => Brand.accent,
      LogLevel.human => Brand.ok,
      _ => Brand.accent,
    };
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 64,
          child: Text(e.at.toIso8601String().substring(11, 19), style: mono(color: Brand.muted)),
        ),
        SizedBox(
          width: 84,
          child: Text(e.actor, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ),
        Expanded(child: Text(e.message, style: const TextStyle(fontSize: 13))),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: e.detail == null || e.detail!.isEmpty
          ? row
          : Tooltip(message: e.detail!, waitDuration: const Duration(milliseconds: 300), child: row),
    );
  }
}
