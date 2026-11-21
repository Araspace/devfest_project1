// Extracted invoice fields, the Checker's findings and the SKR03 booking.

import 'package:belegguard_shared/models.dart';
import 'package:flutter/material.dart';

import '../theme.dart';
import 'key_value.dart';

class InvoiceDetailsCard extends StatelessWidget {
  const InvoiceDetailsCard({super.key, required this.invoiceCase});
  final InvoiceCase invoiceCase;

  @override
  Widget build(BuildContext context) {
    final inv = invoiceCase.invoice!;
    final chk = invoiceCase.check;
    final b = invoiceCase.booking;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Invoice data', style: headline(17)),
            const SizedBox(height: 18),
            Wrap(
              runSpacing: 16,
              children: [
                KeyValue('Supplier', inv.supplierName),
                KeyValue('Invoice no.', inv.invoiceNumber),
                KeyValue('Date', inv.invoiceDate),
                KeyValue('VAT ID', inv.vatId ?? (inv.taxNumber != null ? 'St.-Nr. ${inv.taxNumber}' : null)),
                KeyValue('Net', money(inv.net)),
                KeyValue(
                  'VAT',
                  inv.vat == null
                      ? null
                      : '${money(inv.vat)}${inv.vatRate != null ? ' · ${inv.vatRate!.round()} %' : ''}',
                ),
                KeyValue('Gross', money(inv.gross)),
                KeyValue('Delivery', inv.deliveryDate),
              ],
            ),
            if (chk != null && chk.issues.isNotEmpty) ...[
              const Divider(height: 40, color: Brand.line),
              const Text('Findings', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              const SizedBox(height: 10),
              for (final i in chk.issues) _finding(i),
              if (chk.injectionEvidence.isNotEmpty) ...[const SizedBox(height: 10), _evidence(chk.injectionEvidence)],
            ],
            if (b != null) ...[
              const Divider(height: 40, color: Brand.line),
              const Text('Booking (SKR03)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
              const SizedBox(height: 14),
              Wrap(
                runSpacing: 16,
                children: [
                  KeyValue('Account', '${b.account} ${b.accountName ?? ''}'),
                  KeyValue('Contra account', '${b.contraAccount} ${b.contraAccountName ?? ''}'),
                  KeyValue('Tax code', (b.taxCode ?? '').isEmpty ? '—' : b.taxCode),
                  KeyValue('Booking text', b.bookingText),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _finding(Issue i) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          switch (i.severity) {
            Severity.critical => Icons.gpp_bad_outlined,
            Severity.error => Icons.error_outline,
            _ => Icons.info_outline,
          },
          size: 18,
          color: switch (i.severity) {
            Severity.critical || Severity.error => Brand.danger,
            Severity.warning => Brand.warn,
            _ => Brand.muted,
          },
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(i.message, style: const TextStyle(fontSize: 14, height: 1.4))),
        const SizedBox(width: 12),
        Text(i.code, style: mono(size: 11, color: Brand.muted)),
      ],
    ),
  );

  Widget _evidence(List<String> evidence) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Brand.paper, borderRadius: BorderRadius.circular(12)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quoted, not followed:',
          style: TextStyle(fontWeight: FontWeight.w600, color: Brand.muted),
        ),
        const SizedBox(height: 6),
        for (final e in evidence.take(3)) Text('“$e”', style: mono(color: Brand.ink)),
      ],
    ),
  );
}
