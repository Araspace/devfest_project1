// Offline stand-ins for the Gemini agents so the demo works without network
// or Firebase. They return the same JSON shape as the live agents.

import 'models.dart';

class DemoAgents {
  static String? _field(String text, List<String> keys) {
    for (final k in keys) {
      final m = RegExp('^\\s*$k\\s*[:：]\\s*(.+)\$', caseSensitive: false, multiLine: true).firstMatch(text);
      if (m != null) return m.group(1)!.trim();
    }
    return null;
  }

  static Map<String, dynamic> extract(String text) {
    final vatId = RegExp(r'\b[A-Z]{2}\s?\d{9}\b').firstMatch(_field(text, ['USt-IdNr\\.?', 'VAT ID']) ?? '')?.group(0);
    final rate = RegExp(r'(?:USt|MwSt)\.?\s*(\d{1,2})\s*%', caseSensitive: false).firstMatch(text)?.group(1);
    final vatLine = RegExp(r'^\s*(?:USt|MwSt)\.?\s*\d{1,2}\s*%[^:\n]*:\s*(.+)$', caseSensitive: false, multiLine: true)
        .firstMatch(text)
        ?.group(1);
    final suspicious = RegExp(r'\[\[.*?\]\]|<!--.*?-->', dotAll: true)
        .allMatches(text)
        .map((m) => m.group(0)!.replaceAll('\n', ' '))
        .toList();
    return {
      'supplier_name': _field(text, ['Lieferant', 'Supplier']),
      'supplier_address': _field(text, ['Anschrift', 'Address']),
      'recipient_name': _field(text, ['Rechnungsempfänger', 'Empfänger', 'Recipient']),
      'recipient_address': _field(text, ['Anschrift Empfänger', 'Recipient address']),
      'vat_id': vatId,
      'tax_number': _field(text, ['Steuernummer', 'St\\.-Nr\\.']),
      'invoice_number': _field(text, ['Rechnungsnummer', 'Rechnungsnr\\.?', 'Invoice no\\.?']),
      'invoice_date': _field(text, ['Rechnungsdatum', 'Datum', 'Invoice date']),
      'delivery_date': _field(text, ['Leistungsdatum', 'Leistungszeitraum', 'Lieferdatum']),
      'description': _field(text, ['Leistung', 'Beschreibung']),
      'currency': 'EUR',
      'net': _field(text, ['Nettobetrag', 'Netto', 'Summe netto']),
      'vat': vatLine,
      'gross': _field(text, ['Bruttobetrag', 'Brutto', 'Gesamtbetrag', 'Rechnungsbetrag']),
      'vat_rate': rate,
      'raw_text': text,
      'suspicious_text': suspicious,
      'reasoning': 'Offline demo extractor: matched labelled lines (Lieferant, Rechnungsnummer, Netto/USt/Brutto) with patterns.',
    };
  }

  static Map<String, dynamic> check(InvoiceData inv, List<Issue> ruleIssues, List<String> guardHits) {
    final injection = guardHits.isNotEmpty;
    final errors = ruleIssues.where((i) => i.severity == Severity.error).length;
    return {
      'status': injection ? 'blocked' : (ruleIssues.isEmpty ? 'ok' : 'warning'),
      'issues': <Map<String, dynamic>>[],
      'injection_detected': injection,
      'injection_evidence': guardHits,
      'reasoning': injection
          ? 'The document contains text addressed to an AI that tries to influence approval. Such text is never followed; the invoice is blocked for manual review.'
          : errors == 0
              ? 'All §14 Abs. 4 UStG mandatory details are present, amounts add up and the VAT rate is a valid German rate.'
              : '$errors mandatory detail(s) are missing or inconsistent, so input tax deduction (§15 UStG) would be at risk. Request a corrected invoice.',
    };
  }

  static const _rules = <(List<String>, String, String)>[
    (['papier', 'toner', 'büro', 'ordner', 'stift'], '4930', 'Bürobedarf'),
    (['lizenz', 'software', 'saas', 'abo', 'subscription', 'cloud'], '4964', 'Aufwendungen für Lizenzen/Software'),
    (['beratung', 'steuerberat', 'rechtsanwalt', 'consulting'], '4950', 'Rechts- und Beratungskosten'),
    (['miete', 'büroraum'], '4210', 'Miete'),
    (['telefon', 'mobilfunk'], '4920', 'Telefon'),
    (['internet', 'dsl', 'hosting'], '4925', 'Internetkosten'),
    (['bewirtung', 'restaurant', 'catering'], '4650', 'Bewirtungskosten'),
    (['hotel', 'bahn', 'flug', 'reise'], '4660', 'Reisekosten Arbeitnehmer'),
    (['werbung', 'anzeige', 'marketing', 'ads'], '4600', 'Werbekosten'),
  ];

  static Map<String, dynamic> book(InvoiceData inv) {
    final d = '${inv.description ?? ''} ${inv.supplierName ?? ''}'.toLowerCase();
    var account = '4980';
    var name = 'Sonstiger Betriebsbedarf';
    var why = 'No specific keyword matched, so the general expense account is suggested.';
    for (final (keys, acc, accName) in _rules) {
      final hit = keys.where(d.contains).firstOrNull;
      if (hit != null) {
        account = acc;
        name = accName;
        why = 'Description mentions "$hit", which maps to SKR03 $acc $accName.';
        break;
      }
    }
    if ((inv.net ?? 0) > 800 && account == '4930') {
      account = '0420';
      name = 'Büroeinrichtung';
      why = 'Net amount above 800 € (GWG limit), so it is capitalised as an asset.';
    }
    final rate = inv.vatRate ?? ((inv.net ?? 0) > 0 && inv.vat != null ? inv.vat! / inv.net! * 100 : 19);
    final taxCode = (rate - 19).abs() < 1 ? '9' : (rate - 7).abs() < 1 ? '8' : '';
    return {
      'account': account,
      'account_name': name,
      'contra_account': '1600',
      'contra_account_name': 'Verbindlichkeiten aus Lieferungen und Leistungen',
      'tax_code': taxCode,
      'booking_text': '${inv.supplierName ?? 'Lieferant'} ${inv.invoiceNumber ?? ''}'.trim(),
      'confidence': account == '4980' ? 0.5 : 0.85,
      'reasoning': '$why Unpaid supplier invoice → contra 1600. ${taxCode.isEmpty ? 'No input tax code.' : 'BU $taxCode for ${rate.round()} % input tax.'}',
    };
  }
}
