// Checker tools: allowlist, argument checks, IBAN mismatch, duplicates, and the
// Gemini function-calling loop (with a fake HTTP-free client).

import 'package:belegguard_backend/agents.dart';
import 'package:belegguard_backend/gemini_client.dart';
import 'package:belegguard_backend/tools.dart';
import 'package:belegguard_shared/models.dart';
import 'package:test/test.dart';

/// Simulates a model that first calls lookup_supplier, then answers.
class ToolCallingGemini extends GeminiClient {
  ToolCallingGemini(this.toolName) : super(apiKey: 'test', model: 'fake');
  final String toolName;
  Map<String, Object?>? toolResult;
  @override
  Future<Map<String, dynamic>> generateJson({
    required String system,
    required List<GeminiPart> parts,
    List<Map<String, Object?>>? tools,
    Map<String, Object?> Function(String name, Map<String, Object?> args)? onToolCall,
  }) async {
    if (onToolCall != null) toolResult = onToolCall(toolName, {'name': 'CloudHosting Nord GmbH'});
    return {'status': 'ok', 'issues': [], 'injection_detected': false, 'reasoning': 'fine'};
  }
}

InvoiceData inv({String raw = '', String supplier = 'CloudHosting Nord GmbH', String number = 'CHN-1'}) => InvoiceData(
  supplierName: supplier,
  supplierAddress: 'Am Stadthafen 3, 48155 Münster',
  recipientName: 'Muster Consulting UG',
  recipientAddress: 'Ludgeristraße 5, 48143 Münster',
  vatId: 'DE301122334',
  invoiceNumber: number,
  invoiceDate: '2026-11-19',
  deliveryDate: '2026-11-30',
  description: 'Managed Server',
  net: 300,
  vat: 57,
  gross: 357,
  vatRate: 19,
  rawText: raw,
);

void main() {
  test('unknown tool is refused and recorded', () {
    final t = CheckerTools();
    expect(t.call('book_payment', {})['error'], isNotNull);
    final calls = t.drainCalls();
    expect(calls.single.allowed, isFalse);
  });

  test('oversized or non-string arguments are refused', () {
    final t = CheckerTools();
    expect(t.call('lookup_supplier', {'name': 'x' * 500})['error'], isNotNull);
    expect(t.call('lookup_supplier', {'name': 42})['error'], isNotNull);
  });

  test('lookup by VAT ID returns master data', () {
    final r = CheckerTools().call('lookup_supplier', {'vat_id': 'DE 301 122 334'});
    expect(r['iban'], 'DE02120300000000202051');
  });

  test('IBAN finder normalises spaces', () {
    expect(CheckerTools.findIbans('IBAN: DE89 3704 0044 0532 0130 00 · Sparkasse'), ['DE89370400440532013000']);
  });

  test('model tool call runs through the allowlist and is logged', () async {
    final g = ToolCallingGemini('lookup_supplier');
    final agents = Agents(g);
    await agents.check(inv());
    expect(g.toolResult?['found'], isTrue);
    expect(agents.tools.drainCalls().map((c) => c.caller), containsAll(['checker', 'backend']));
  });

  test('model cannot call a tool outside the allowlist', () async {
    final g = ToolCallingGemini('delete_everything');
    await Agents(g).check(inv());
    expect(g.toolResult?['error'], contains('not allowed'));
  });

  test('IBAN different from master data → IBAN_MISMATCH, never ok', () async {
    final r = await Agents(ToolCallingGemini('lookup_supplier')).check(inv(raw: 'IBAN: DE44 5001 0517 5407 3249 31'));
    expect(r.issues.map((i) => i.code), contains('IBAN_MISMATCH'));
    expect(r.status, isNot(CheckStatus.ok));
  });

  test('matching IBAN gives no finding', () async {
    final r = await Agents(ToolCallingGemini('lookup_supplier')).check(inv(raw: 'IBAN: DE02 1203 0000 0000 2020 51'));
    expect(r.issues.map((i) => i.code), isNot(contains('IBAN_MISMATCH')));
  });

  test('already booked invoice → DUPLICATE_INVOICE', () async {
    final agents = Agents(ToolCallingGemini('check_duplicate'));
    agents.tools.markBooked('CloudHosting Nord GmbH', 'CHN-1');
    final r = await agents.check(inv());
    expect(r.issues.map((i) => i.code), contains('DUPLICATE_INVOICE'));
    expect(r.status, CheckStatus.warning);
  });
}
