import 'dart:typed_data';

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
    source: _toStr(j['source']) ?? 'checker',
  );

  Map<String, dynamic> toJson() => {'code': code, 'severity': severity.name, 'message': message, 'source': source};
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

  Map<String, dynamic> toJson() => {
    'status': status.name,
    'issues': issues.map((i) => i.toJson()).toList(),
    'injection_detected': injectionDetected,
    'injection_evidence': injectionEvidence,
    'reasoning': reasoning,
  };

  factory CheckResult.fromJson(Map<String, dynamic> j) => CheckResult(
    status: CheckStatus.values.where((s) => s.name == j['status']).firstOrNull ?? CheckStatus.blocked,
    issues: (j['issues'] as List? ?? const [])
        .whereType<Map>()
        .map((m) => Issue.fromJson(m.cast<String, dynamic>()))
        .toList(),
    injectionDetected: j['injection_detected'] == true,
    injectionEvidence: _toStrList(j['injection_evidence']),
    reasoning: _toStr(j['reasoning']) ?? '',
  );
}

/// Output of the Exporter agent.
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

  Map<String, dynamic> toJson() => {
    'account': account,
    'account_name': accountName,
    'contra_account': contraAccount,
    'contra_account_name': contraAccountName,
    'tax_code': taxCode,
    'booking_text': bookingText,
    'confidence': confidence,
    'reasoning': reasoning,
  };
}

enum LogLevel { info, agent, warn, block, human }

class LogEntry {
  LogEntry(this.actor, this.message, {this.level = LogLevel.info, this.detail, DateTime? at})
    : at = at ?? DateTime.now();
  final DateTime at;
  final String? detail;
  final String actor;
  final String message;
  final LogLevel level;
}

/// Output of the Approver agent.
class ApprovalRecommendation {
  ApprovalRecommendation({required this.decision, required this.reasoning, this.confidence});
  final String decision; // approve | reject | human_review
  final String reasoning;
  final double? confidence;

  factory ApprovalRecommendation.fromJson(Map<String, dynamic> j) {
    final d = (_toStr(j['decision']) ?? 'human_review').toLowerCase();
    return ApprovalRecommendation(
      decision: const ['approve', 'reject', 'human_review'].contains(d) ? d : 'human_review',
      reasoning: _toStr(j['reasoning']) ?? '',
      confidence: _toDouble(j['confidence']),
    );
  }

  Map<String, dynamic> toJson() => {'decision': decision, 'reasoning': reasoning, 'confidence': confidence};
}

/// Everything known about one uploaded document as it moves through the flow.
class InvoiceCase {
  InvoiceCase(this.fileName, {String? id, this.serverId, this.mimeType = 'application/octet-stream', this.bytes})
    : id = id ?? DateTime.now().microsecondsSinceEpoch.toString();
  final String id;
  String? serverId; // case id on the backend while the flow is running
  final String fileName;
  final String mimeType;
  Uint8List? bytes; // original file, only in memory until it is filed
  InvoiceData? invoice;
  CheckResult? check;
  ApprovalRecommendation? recommendation;
  BookingSuggestion? booking;
  String decision = 'pending'; // pending | approved | rejected
  String decidedBy = ''; // 'human' | 'approver agent'
  DateTime? decidedAt;
  bool hasOriginal = false; // original file is stored in the archive

  /// Month folder used by the archive, e.g. "2026-11".
  String get period {
    final d = invoice?.invoiceDate;
    if (d != null && RegExp(r'^\d{4}-\d{2}').hasMatch(d)) return d.substring(0, 7);
    return (decidedAt ?? DateTime.now()).toIso8601String().substring(0, 7);
  }

  /// Archive record (without the original file and the raw text).
  Map<String, dynamic> toJson() => {
    'id': id,
    'file_name': fileName,
    'mime_type': mimeType,
    'has_original': hasOriginal,
    'invoice': invoice?.toJson(),
    'check_status': check?.status.name,
    'issues': check?.issues.map((i) => {'code': i.code, 'severity': i.severity.name, 'message': i.message}).toList(),
    'booking': booking?.toJson(),
    'decision': decision,
    'decided_by': decidedBy,
    'decided_at': decidedAt?.toIso8601String(),
  };

  factory InvoiceCase.fromJson(Map<String, dynamic> j) {
    final c = InvoiceCase(
      _toStr(j['file_name']) ?? 'receipt',
      id: _toStr(j['id']),
      mimeType: _toStr(j['mime_type']) ?? 'application/octet-stream',
    );
    final inv = j['invoice'];
    if (inv is Map) c.invoice = InvoiceData.fromJson(inv.cast<String, dynamic>());
    final status = CheckStatus.values.where((s) => s.name == j['check_status']).firstOrNull;
    if (status != null) {
      c.check = CheckResult(
        status: status,
        issues: (j['issues'] as List? ?? const [])
            .whereType<Map>()
            .map((m) => Issue.fromJson(m.cast<String, dynamic>()))
            .toList(),
        injectionDetected: false,
        injectionEvidence: const [],
        reasoning: '',
      );
    }
    final b = j['booking'];
    if (b is Map) c.booking = BookingSuggestion.fromJson(b.cast<String, dynamic>());
    c.decision = _toStr(j['decision']) ?? 'approved';
    c.decidedBy = _toStr(j['decided_by']) ?? '';
    c.decidedAt = DateTime.tryParse(j['decided_at']?.toString() ?? '');
    c.hasOriginal = j['has_original'] == true;
    return c;
  }
}
