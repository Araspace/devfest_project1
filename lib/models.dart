// Data models shared by the agents, the UI and the Excel export.

double? _toDouble(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  final s = v.toString().trim().replaceAll('€', '').replaceAll('EUR', '').trim();
  if (s.isEmpty) return null;
  // Accept German "1.234,56" and English "1,234.56".
  final normalized = s.contains(',') && s.lastIndexOf(',') > s.lastIndexOf('.')
      ? s.replaceAll('.', '').replaceAll(',', '.')
      : s.replaceAll(',', '');
  return double.tryParse(normalized.replaceAll(RegExp(r'[^0-9.\-]'), ''));
}

String? _toStr(Object? v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty || s.toLowerCase() == 'null' ? null : s;
}

List<String> _toStrList(Object? v) =>
    v is List ? v.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList() : const [];

/// Output of the Extractor agent.
class InvoiceData {
  InvoiceData({
    this.supplierName,
    this.supplierAddress,
    this.recipientName,
    this.recipientAddress,
    this.vatId,
    this.taxNumber,
    this.invoiceNumber,
    this.invoiceDate,
    this.deliveryDate,
    this.description,
    this.currency,
    this.net,
    this.vat,
    this.gross,
    this.vatRate,
    this.rawText = '',
    this.suspiciousText = const [],
    this.reasoning = '',
  });

  final String? supplierName;
  final String? supplierAddress;
  final String? recipientName;
  final String? recipientAddress;
  final String? vatId;
  final String? taxNumber;
  final String? invoiceNumber;
  final String? invoiceDate;
  final String? deliveryDate;
  final String? description;
  final String? currency;
  final double? net;
  final double? vat;
  final double? gross;
  final double? vatRate; // percent, e.g. 19
  final String rawText;
  final List<String> suspiciousText;
  final String reasoning;

  factory InvoiceData.fromJson(Map<String, dynamic> j) => InvoiceData(
        supplierName: _toStr(j['supplier_name']),
        supplierAddress: _toStr(j['supplier_address']),
        recipientName: _toStr(j['recipient_name']),
        recipientAddress: _toStr(j['recipient_address']),
        vatId: _toStr(j['vat_id']),
        taxNumber: _toStr(j['tax_number']),
        invoiceNumber: _toStr(j['invoice_number']),
        invoiceDate: _toStr(j['invoice_date']),
        deliveryDate: _toStr(j['delivery_date']),
        description: _toStr(j['description']),
        currency: _toStr(j['currency']) ?? 'EUR',
        net: _toDouble(j['net']),
        vat: _toDouble(j['vat']),
        gross: _toDouble(j['gross']),
        vatRate: _toDouble(j['vat_rate']),
        rawText: _toStr(j['raw_text']) ?? '',
        suspiciousText: _toStrList(j['suspicious_text']),
        reasoning: _toStr(j['reasoning']) ?? '',
      );

  /// Fields shown to the next agents and the user (raw text excluded).
  Map<String, dynamic> toJson() => {
        'supplier_name': supplierName,
        'supplier_address': supplierAddress,
        'recipient_name': recipientName,
        'recipient_address': recipientAddress,
        'vat_id': vatId,
        'tax_number': taxNumber,
        'invoice_number': invoiceNumber,
        'invoice_date': invoiceDate,
        'delivery_date': deliveryDate,
        'description': description,
        'currency': currency,
        'net': net,
        'vat': vat,
        'gross': gross,
        'vat_rate': vatRate,
      };
}

enum Severity { info, warning, error, critical }

class Issue {
  Issue(this.code, this.severity, this.message, {this.source = 'rules'});
  final String code;
  final Severity severity;
  final String message;
  final String source; // 'rules' | 'guard' | 'checker'

  factory Issue.fromJson(Map<String, dynamic> j) => Issue(
        _toStr(j['code']) ?? 'CHECK',
        switch ((_toStr(j['severity']) ?? 'warning').toLowerCase()) {
          'info' => Severity.info,
          'error' => Severity.error,
          'critical' => Severity.critical,
          _ => Severity.warning,
        },
        _toStr(j['message']) ?? '',
        source: 'checker',
      );
}

enum CheckStatus { ok, warning, blocked }

/// Output of the Checker agent merged with deterministic rule + guard results.
class CheckResult {
  CheckResult({
    required this.status,
    required this.issues,
    required this.injectionDetected,
    required this.injectionEvidence,
    required this.reasoning,
  });

  final CheckStatus status;
  final List<Issue> issues;
  final bool injectionDetected;
  final List<String> injectionEvidence;
  final String reasoning;
}

/// Output of the Booker agent.
class BookingSuggestion {
  BookingSuggestion({
    this.account,
    this.accountName,
    this.contraAccount,
    this.contraAccountName,
    this.taxCode,
    this.bookingText,
    this.confidence,
    this.reasoning = '',
  });

  final String? account;
  final String? accountName;
  final String? contraAccount;
  final String? contraAccountName;
  final String? taxCode;
  final String? bookingText;
  final double? confidence;
  final String reasoning;

  factory BookingSuggestion.fromJson(Map<String, dynamic> j) => BookingSuggestion(
        account: _toStr(j['account']),
        accountName: _toStr(j['account_name']),
        contraAccount: _toStr(j['contra_account']),
        contraAccountName: _toStr(j['contra_account_name']),
        taxCode: _toStr(j['tax_code']),
        bookingText: _toStr(j['booking_text']),
        confidence: _toDouble(j['confidence']),
        reasoning: _toStr(j['reasoning']) ?? '',
      );
}

enum LogLevel { info, agent, warn, block, human }

class LogEntry {
  LogEntry(this.actor, this.message, {this.level = LogLevel.info, DateTime? at})
      : at = at ?? DateTime.now();
  final DateTime at;
  final String actor;
  final String message;
  final LogLevel level;
}

/// Everything known about one uploaded document.
class PipelineResult {
  PipelineResult({
    required this.fileName,
    required this.invoice,
    required this.check,
    this.booking,
  });

  final String fileName;
  final InvoiceData invoice;
  final CheckResult check;
  final BookingSuggestion? booking; // null when blocked
  String decision = 'pending'; // pending | approved | rejected
  DateTime? decidedAt;
}
