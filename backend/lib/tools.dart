// Read-only tools the Checker agent may call via Gemini function calling.
//
//   lookup_supplier(vat_id | name)            → known master data (IBAN, VAT ID)
//   check_duplicate(supplier, invoice_number) → was this invoice already booked?
//
// Security model:
//  * Fixed allowlist: any other tool name is refused.
//  * Read-only: no tool can write, book or pay. The only write (markBooked) is
//    called by the server after an approved export, never by an agent.
//  * Arguments are validated (type, length) before anything runs.
//  * Every call is recorded and goes into the audit log.
//  * Tools only return information; they can make a check stricter, never looser.
//  * Local data only – no network, nothing can fail on stage.

class Supplier {
  const Supplier(this.name, this.vatId, this.iban);
  final String name;
  final String? vatId;
  final String iban;
}

/// One recorded tool call (for the audit log).
class ToolCall {
  ToolCall(this.name, this.args, this.result, {required this.allowed, this.caller = 'checker'});
  final String name;
  final Map<String, Object?> args;
  final Map<String, Object?> result;
  final bool allowed;

  /// 'checker' = requested by the LLM, 'backend' = deterministic re-check by the server.
  final String caller;
}

class CheckerTools {
  CheckerTools({List<Supplier>? suppliers}) : suppliers = suppliers ?? demoSuppliers;

  /// Demo master data. CloudHosting Nord's known IBAN differs on purpose from the
  /// one on samples/3_prompt_injection (classic "bank details changed" fraud).
  static const demoSuppliers = [
    Supplier('Bürobedarf Weber GmbH', 'DE287654321', 'DE89370400440532013000'),
    Supplier('IT-Service Brandt', null, 'DE12400501500000123456'),
    Supplier('CloudHosting Nord GmbH', 'DE301122334', 'DE02120300000000202051'),
  ];

  final List<Supplier> suppliers;
  final _booked = <String>{};
  final _calls = <ToolCall>[];

  static const maxArgLength = 100;

  /// Gemini functionDeclarations for the Checker.
  static const declarations = [
    {
      'name': 'lookup_supplier',
      'description':
          'Read-only. Looks up the known master data (registered IBAN and VAT ID) of a supplier. '
          'Use it to compare the bank details on the invoice with the known ones.',
      'parameters': {
        'type': 'object',
        'properties': {
          'vat_id': {'type': 'string', 'description': 'USt-IdNr. of the supplier, e.g. DE123456789'},
          'name': {'type': 'string', 'description': 'Supplier name as printed on the invoice'},
        },
      },
    },
    {
      'name': 'check_duplicate',
      'description': 'Read-only. Checks whether this supplier\'s invoice number was already booked.',
      'parameters': {
        'type': 'object',
        'properties': {
          'supplier': {'type': 'string'},
          'invoice_number': {'type': 'string'},
        },
        'required': ['supplier', 'invoice_number'],
      },
    },
  ];

  static const allowlist = {'lookup_supplier', 'check_duplicate'};

  /// Returns and clears the calls recorded since the last drain.
  List<ToolCall> drainCalls() {
    final out = List<ToolCall>.of(_calls);
    _calls.clear();
    return out;
  }

  /// Runs one tool. Never throws: unknown tools and bad arguments return an error result.
  Map<String, Object?> call(String name, Map<String, Object?> args, {String caller = 'checker'}) {
    Map<String, Object?> result;
    var allowed = true;
    if (!allowlist.contains(name)) {
      allowed = false;
      result = {'error': 'Tool "$name" is not allowed'};
    } else {
      final bad = args.entries
          .where((e) => e.value != null && (e.value is! String || (e.value as String).length > maxArgLength))
          .map((e) => e.key);
      if (bad.isNotEmpty) {
        allowed = false;
        result = {'error': 'Invalid arguments: ${bad.join(', ')}'};
      } else {
        result = switch (name) {
          'lookup_supplier' => _lookup(args['vat_id'] as String?, args['name'] as String?),
          _ => _duplicate(args['supplier'] as String?, args['invoice_number'] as String?),
        };
      }
    }
    _calls.add(ToolCall(name, args, result, allowed: allowed, caller: caller));
    return result;
  }

  /// Called by the server after an approved export – not available to any agent.
  void markBooked(String? supplier, String? invoiceNumber) {
    if (supplier == null || invoiceNumber == null) return;
    _booked.add(_key(supplier, invoiceNumber));
  }

  Map<String, Object?> _lookup(String? vatId, String? name) {
    final v = _norm(vatId ?? '');
    final n = _norm(name ?? '');
    final s = suppliers
        .where((s) => (v.isNotEmpty && _norm(s.vatId ?? '') == v) || (n.isNotEmpty && _norm(s.name) == n))
        .firstOrNull;
    if (s == null) return {'found': false};
    return {'found': true, 'name': s.name, 'vat_id': s.vatId, 'iban': s.iban};
  }

  Map<String, Object?> _duplicate(String? supplier, String? number) {
    if (supplier == null || number == null) return {'error': 'supplier and invoice_number are required'};
    return {'already_booked': _booked.contains(_key(supplier, number))};
  }

  static String _key(String supplier, String number) => '${_norm(supplier)}|${_norm(number)}';
  static String _norm(String s) => s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9ÄÖÜ]'), '');

  /// All IBANs printed in a text, normalised (no spaces).
  static List<String> findIbans(String text) => RegExp(
    r'\b[A-Z]{2}\d{2}(?:[ ]?[A-Z0-9]{4}){3,7}(?:[ ]?[A-Z0-9]{1,3})?\b',
  ).allMatches(text.toUpperCase()).map((m) => m.group(0)!.replaceAll(' ', '')).toSet().toList();
}
