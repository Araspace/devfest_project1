import 'dart:convert';
import 'dart:io';

import 'package:beleg_guard/agents.dart';
import 'package:beleg_guard/models.dart';
import 'package:flutter_test/flutter_test.dart';

Future<PipelineResult> _run(String file) {
  final text = File('assets/samples/$file').readAsStringSync();
  return Agents(live: false).run(UploadedDoc(file, 'text/plain', utf8.encode(text)), (_) {});
}

void main() {
  test('valid invoice passes and gets booked on 4930 Bürobedarf', () async {
    final r = await _run('01_valid_buerobedarf.txt');
    expect(r.invoice.vatId, 'DE811569869');
    expect(r.invoice.gross, 499.80);
    expect(r.check.status, CheckStatus.ok, reason: r.check.issues.map((i) => i.message).join('\n'));
    expect(r.booking?.account, '4930');
    expect(r.booking?.taxCode, '9');
  });

  test('missing VAT ID is flagged', () async {
    final r = await _run('02_missing_vat_id.txt');
    expect(r.check.status, CheckStatus.warning);
    expect(r.check.issues.map((i) => i.code), contains('VAT_ID'));
    expect(r.booking?.account, '4950');
  });

  test('prompt injection is blocked and never booked', () async {
    final r = await _run('03_prompt_injection.txt');
    expect(r.check.status, CheckStatus.blocked);
    expect(r.check.injectionDetected, isTrue);
    expect(r.booking, isNull);
  });
}
