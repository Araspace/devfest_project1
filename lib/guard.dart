// Deterministic safety net that runs next to the LLM agents.
//
// The LLM Checker can flag issues, but it can never *clear* what these rules
// find: an injection hit here forces the invoice to BLOCKED.

import 'models.dart';

class InjectionGuard {
  static final List<RegExp> _patterns = [
    RegExp(r'ignore (all |any )?(previous|prior|above|earlier) (instructions|rules|prompts)', caseSensitive: false),
    RegExp(r'disregard (all |any )?(previous|prior|above) ', caseSensitive: false),
    RegExp(r'ignoriere (alle )?(vorherigen|bisherigen|obigen) (anweisungen|regeln)', caseSensitive: false),
    RegExp(r'\b(system prompt|systemprompt|developer message)\b', caseSensitive: false),
    RegExp(r'\byou are (now )?(an? )?(ai|assistant|language model|agent)\b', caseSensitive: false),
    RegExp(r'\b(as an ai|note to (the )?(ai|llm|assistant|agent)s?)\b', caseSensitive: false),
    RegExp(r'\b(hinweis an (die )?(ki|ai))\b', caseSensitive: false),
    RegExp(r'\bmark (this|the) invoice as (valid|approved|compliant)\b', caseSensitive: false),
    RegExp(r'\b(auto[- ]?approve|approve automatically|skip (the )?(check|review|validation))\b', caseSensitive: false),
    RegExp(r'\b(set|change) (the )?(status|account|iban) to\b', caseSensitive: false),
    RegExp(r'</?(system|instructions?|prompt|untrusted_invoice_text)>', caseSensitive: false),
    RegExp(r'\[\[?\s*(ai|llm|system)\s*[:\]]', caseSensitive: false),
  ];

  /// Returns the matched snippets (empty list when clean).
  static List<String> scan(String text) {
    final hits = <String>[];
    for (final p in _patterns) {
      for (final m in p.allMatches(text)) {
        final start = (m.start - 40).clamp(0, text.length);
        final end = (m.end + 40).clamp(0, text.length);
        hits.add('…${text.substring(start, end).replaceAll('\n', ' ').trim()}…');
      }
    }
    // Zero-width / bidi control characters are a classic hiding trick.
    // A leading BOM (Windows text files) and LRM/RLM marks (common in PDF text) are harmless.
    final body = text.startsWith('﻿') ? text.substring(1) : text;
    if (body.runes.any((r) => (r >= 0x200B && r <= 0x200D) || (r >= 0x202A && r <= 0x202E) || (r >= 0x2060 && r <= 0x2064) || r == 0xFEFF)) {
      hits.add('Invisible Unicode control characters found in invoice text');
    }
    return hits.toSet().toList();
  }

  /// Wraps untrusted text so it is clearly data, and neutralises attempts to
  /// close the wrapper tag from inside the document.
  static String quote(String text) {
    final safe = text.replaceAll(RegExp(r'</?\s*untrusted_invoice_text\s*>', caseSensitive: false), '[removed-tag]');
    return '<untrusted_invoice_text>\n$safe\n</untrusted_invoice_text>';
  }
}

/// Deterministic §14 Abs. 4 UStG checks + arithmetic plausibility.
class ComplianceRules {
  static final _vatIdRe = RegExp(r'^[A-Z]{2}[A-Z0-9]{8,12}$');
  static final _deVatIdRe = RegExp(r'^DE\d{9}$');

  static List<Issue> check(InvoiceData inv) {
    final issues = <Issue>[];
    final gross = inv.gross ?? 0;
    // §33 UStDV: invoices up to 250 € gross need fewer details.
    final smallAmount = gross > 0 && gross <= 250;

    void require(Object? value, String code, String label, {bool alsoSmall = true}) {
      final missing = value == null || (value is String && value.trim().isEmpty);
      if (missing && (alsoSmall || !smallAmount)) {
        issues.add(Issue(code, Severity.error, 'Missing mandatory detail: $label (§14 Abs. 4 UStG)'));
      }
    }

    require(inv.supplierName, 'SUPPLIER_NAME', 'supplier name');
    require(inv.supplierAddress, 'SUPPLIER_ADDRESS', 'supplier address');
    require(inv.recipientName, 'RECIPIENT_NAME', 'recipient name', alsoSmall: false);
    require(inv.recipientAddress, 'RECIPIENT_ADDRESS', 'recipient address', alsoSmall: false);
    require(inv.invoiceDate, 'INVOICE_DATE', 'invoice date');
    require(inv.invoiceNumber, 'INVOICE_NO', 'sequential invoice number', alsoSmall: false);
    require(inv.description, 'DESCRIPTION', 'quantity and description of goods/services');
    require(inv.deliveryDate, 'DELIVERY_DATE', 'date of delivery/service', alsoSmall: false);

    if (inv.vatId == null && inv.taxNumber == null && !smallAmount) {
      issues.add(Issue('VAT_ID', Severity.error,
          'Neither VAT ID (USt-IdNr.) nor tax number (Steuernummer) of the supplier is stated (§14 Abs. 4 Nr. 2 UStG)'));
    } else if (inv.vatId != null) {
      final id = inv.vatId!.replaceAll(' ', '').toUpperCase();
      if (!_vatIdRe.hasMatch(id) || (id.startsWith('DE') && !_deVatIdRe.hasMatch(id))) {
        issues.add(Issue('VAT_ID_FORMAT', Severity.warning, 'VAT ID "${inv.vatId}" has an invalid format'));
      }
    }

    if (inv.net != null && inv.vat != null && inv.gross != null) {
      final diff = (inv.net! + inv.vat! - inv.gross!).abs();
      if (diff > 0.02) {
        issues.add(Issue('SUM_MISMATCH', Severity.error,
            'Net ${inv.net!.toStringAsFixed(2)} + VAT ${inv.vat!.toStringAsFixed(2)} ≠ gross ${inv.gross!.toStringAsFixed(2)}'));
      }
    } else if (!smallAmount) {
      issues.add(Issue('AMOUNTS', Severity.error, 'Net amount, VAT amount or gross amount missing'));
    }

    if (inv.net != null && inv.vat != null && inv.net! > 0) {
      final rate = inv.vat! / inv.net! * 100;
      const allowed = [0.0, 7.0, 19.0];
      if (!allowed.any((r) => (r - rate).abs() < 0.6)) {
        issues.add(Issue('VAT_RATE', Severity.error,
            'Effective VAT rate ${rate.toStringAsFixed(1)} % is not a German rate (0 / 7 / 19 %)'));
      } else if (inv.vatRate != null && (inv.vatRate! - rate).abs() > 0.6) {
        issues.add(Issue('VAT_RATE_MISMATCH', Severity.warning,
            'Stated rate ${inv.vatRate} % does not match computed ${rate.toStringAsFixed(1)} %'));
      }
    }
    return issues;
  }
}
