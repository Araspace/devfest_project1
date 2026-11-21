// API flow with a fake Gemini client: the server enforces the approval rules.

import 'dart:convert';
import 'dart:io';

import 'package:belegguard_backend/agents.dart';
import 'package:belegguard_backend/api.dart';
import 'package:belegguard_backend/gemini_client.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

/// One answer that satisfies every agent: each parser only reads its own keys.
class FakeGemini extends GeminiClient {
  FakeGemini() : super(apiKey: 'test', model: 'fake');
  @override
  Future<Map<String, dynamic>> generateJson({
    required String system,
    required List<GeminiPart> parts,
    List<Map<String, Object?>>? tools,
    Map<String, Object?> Function(String name, Map<String, Object?> args)? onToolCall,
  }) async => {
    'supplier_name': 'Bürobedarf Weber GmbH',
    'supplier_address': 'Hafenweg 12, 48155 Münster',
    'recipient_name': 'Muster Consulting UG',
    'recipient_address': 'Ludgeristraße 5, 48143 Münster',
    'vat_id': 'DE287654321',
    'invoice_number': 'RE-2026-1142',
    'invoice_date': '2026-11-14',
    'delivery_date': '2026-11-12',
    'description': '2x Bürostuhl',
    'net': 450,
    'vat': 85.5,
    'gross': 535.5,
    'vat_rate': 19,
    'status': 'ok',
    'issues': [],
    'injection_detected': false,
    'decision': 'approve',
    'confidence': 0.9,
    'account': '4930',
    'account_name': 'Bürobedarf',
    'contra_account': '1600',
    'tax_code': '9',
    'reasoning': 'fake',
  };
}

void main() {
  late Handler api;
  setUp(() => api = Api(Agents(FakeGemini())).handler);

  Future<(int, Map<String, dynamic>)> post(String path, Object body) async {
    final res = await api(Request('POST', Uri.parse('http://localhost/$path'), body: jsonEncode(body)));
    return (res.statusCode, jsonDecode(await res.readAsString()) as Map<String, dynamic>);
  }

  Future<String> upload(String sample) async {
    final bytes = File('../samples/$sample.txt').readAsBytesSync();
    final (code, body) = await post('api/cases', {
      'file_name': '$sample.txt',
      'mime_type': 'text/plain',
      'data_base64': base64Encode(bytes),
    });
    expect(code, 200);
    return body['id'] as String;
  }

  test('valid invoice: extract → check → recommend → export', () async {
    final id = await upload('1_valid_invoice');
    expect((await post('api/cases/$id/check', {})).$2['status'], 'ok');
    expect((await post('api/cases/$id/recommend', {})).$2['decision'], 'approve');
    final (code, booking) = await post('api/cases/$id/export', {'approved_by': 'human'});
    expect(code, 200);
    expect(booking['account'], '4930');
  });

  test('injection invoice can never be exported, not even by a human', () async {
    final id = await upload('3_prompt_injection');
    expect((await post('api/cases/$id/check', {})).$2['status'], 'blocked');
    expect((await post('api/cases/$id/export', {'approved_by': 'human'})).$1, 403);
  });

  test('export without approval is refused', () async {
    final id = await upload('1_valid_invoice');
    await post('api/cases/$id/check', {});
    expect((await post('api/cases/$id/export', {})).$1, 403);
  });

  test('export before check is refused', () async {
    final id = await upload('1_valid_invoice');
    expect((await post('api/cases/$id/export', {'approved_by': 'human'})).$1, 409);
  });

  test('unsupported file type is refused', () async {
    final (code, _) = await post('api/cases', {
      'file_name': 'x.exe',
      'mime_type': 'application/x-msdownload',
      'data_base64': 'AA==',
    });
    expect(code, 415);
  });

  test('requests from a foreign browser origin are refused', () async {
    final res = await api(
      Request(
        'POST',
        Uri.parse('http://localhost/api/cases'),
        headers: {'origin': 'https://evil.example'},
        body: '{}',
      ),
    );
    expect(res.statusCode, 403);
    final local = await api(
      Request('GET', Uri.parse('http://localhost/api/health'), headers: {'origin': 'http://localhost:5000'}),
    );
    expect(local.statusCode, 200);
    expect(local.headers['access-control-allow-origin'], 'http://localhost:5000');
  });

  test('case ids are unguessable and a rejected case is gone', () async {
    final a = await upload('1_valid_invoice');
    final b = await upload('1_valid_invoice');
    expect(a, isNot(b));
    expect(a, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect((await post('api/cases/$a/reject', {'rejected_by': 'human'})).$1, 200);
    expect((await post('api/cases/$a/check', {})).$1, 404);
  });

  test('malformed body gives a JSON error, not a crash', () async {
    final (code, body) = await post('api/cases', [1, 2]);
    expect(code, 400);
    expect(body['error'], isNotNull);
  });

  test('second upload of a booked invoice is flagged as duplicate', () async {
    final first = await upload('1_valid_invoice');
    await post('api/cases/$first/check', {});
    await post('api/cases/$first/recommend', {});
    expect((await post('api/cases/$first/export', {'approved_by': 'human'})).$1, 200);
    final again = await upload('1_valid_invoice');
    final (_, chk) = await post('api/cases/$again/check', {});
    expect(chk['status'], 'warning');
    expect([for (final i in chk['issues'] as List) i['code']], contains('DUPLICATE_INVOICE'));
  });
}
