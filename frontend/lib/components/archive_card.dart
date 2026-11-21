// Receipt archive: filed receipts grouped by month, with search and Excel export.

import 'package:belegguard_shared/models.dart';
import 'package:flutter/material.dart';

import '../services/archive.dart';
import '../theme.dart';

class ArchiveCard extends StatefulWidget {
  const ArchiveCard({super.key, required this.archive, required this.onExcel, required this.onRemove});
  final List<InvoiceCase> archive;
  final void Function(List<InvoiceCase> shown) onExcel;
  final void Function(InvoiceCase c) onRemove;

  @override
  State<ArchiveCard> createState() => _ArchiveCardState();
}

class _ArchiveCardState extends State<ArchiveCard> {
  String _query = '';

  List<InvoiceCase> get _shown {
    final q = _query.trim().toLowerCase();
    return widget.archive.where((c) {
      if (q.isEmpty) return true;
      final i = c.invoice;
      return [
        c.fileName,
        i?.supplierName,
        i?.invoiceNumber,
        c.booking?.account,
        c.booking?.accountName,
        c.period,
      ].any((v) => v != null && v.toLowerCase().contains(q));
    }).toList()..sort((a, b) => (b.invoice?.invoiceDate ?? b.period).compareTo(a.invoice?.invoiceDate ?? a.period));
  }

  static double _gross(Iterable<InvoiceCase> cs) => cs.fold(0, (sum, c) => sum + (c.invoice?.gross ?? 0));

  @override
  Widget build(BuildContext context) {
    final items = _shown;
    final empty = widget.archive.isEmpty;
    final byMonth = <String, List<InvoiceCase>>{};
    for (final c in items) {
      byMonth.putIfAbsent(c.period, () => []).add(c);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.inventory_2_outlined, color: Brand.purple),
                const SizedBox(width: 10),
                Expanded(child: Text('Receipt archive', style: headline(22))),
                if (!empty)
                  TextButton.icon(
                    onPressed: () => widget.onExcel(items),
                    icon: const Icon(Icons.download_rounded, color: Brand.purple),
                    label: const Text('Excel', style: TextStyle(color: Brand.ink)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              empty
                  ? 'Approved receipts are copied and filed here, sorted by month.'
                  : '${items.length} receipt${items.length == 1 ? '' : 's'} · ${money(_gross(items))} gross',
              style: const TextStyle(color: Brand.muted),
            ),
            if (!empty) ...[
              const SizedBox(height: 16),
              TextField(
                decoration: const InputDecoration(
                  hintText: 'Search supplier, invoice no., account, month…',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ],
            for (final entry in byMonth.entries) ...[
              const SizedBox(height: 20),
              Row(
                children: [
                  const Icon(Icons.folder_outlined, size: 18, color: Brand.orangeDark),
                  const SizedBox(width: 6),
                  Text(
                    entry.key,
                    style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.orangeDark),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${entry.value.length} · ${money(_gross(entry.value))}',
                    style: const TextStyle(color: Brand.muted),
                  ),
                ],
              ),
              const Divider(color: Brand.line),
              for (final c in entry.value) _row(c),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(InvoiceCase c) {
    final i = c.invoice;
    final b = c.booking;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i?.supplierName ?? c.fileName, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  [
                    i?.invoiceDate,
                    i?.invoiceNumber,
                    if (b?.account != null) '${b!.account} ${b.accountName ?? ''}',
                  ].whereType<String>().join(' · '),
                  style: const TextStyle(color: Brand.muted, fontSize: 13),
                ),
              ],
            ),
          ),
          Text(money(i?.gross), style: const TextStyle(fontWeight: FontWeight.w600)),
          IconButton(
            tooltip: c.hasOriginal ? 'Download original' : 'Original file not stored',
            onPressed: c.hasOriginal ? () => Archive.downloadOriginal(c) : null,
            icon: const Icon(Icons.file_download_outlined, color: Brand.purple),
          ),
          IconButton(
            tooltip: 'Remove from archive',
            onPressed: () => widget.onRemove(c),
            icon: const Icon(Icons.delete_outline, color: Brand.muted),
          ),
        ],
      ),
    );
  }
}
