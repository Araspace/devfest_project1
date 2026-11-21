// HTTP API of the BelegGuard backend.
//
// The browser never talks to Gemini and never sees the API key. It uploads a
// receipt once; everything else happens on the server, step by step:
//
//   POST /api/cases                  upload → Extractor        → {id, invoice}
//   POST /api/cases/<id>/check       Checker + guard + rules   → CheckResult
//   POST /api/cases/<id>/recommend   Approver                  → ApprovalRecommendation
//   POST /api/cases/<id>/export      Exporter (after approval) → BookingSuggestion
//   POST /api/cases/<id>/reject      rejection → audit log, case dropped
//   GET  /api/health                                           → {ok, model}
//
// The raw invoice text stays on the server, so the client cannot tamper with
// what the Checker sees. The server enforces the approval rules itself: a
// blocked invoice can never be exported, whatever the client sends.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:belegguard_shared/models.dart';
import 'package:shelf/shelf.dart';

import 'agents.dart';
import 'gemini_client.dart';

/// Server-side state of one receipt while it moves through the flow.
class _Case {
  _Case(this.doc);
  final UploadedDoc doc;
  InvoiceData? invoice;
  CheckResult? check;
  ApprovalRecommendation? recommendation;
}

class Api {
  Api(this.agents, {this.allowedOrigins = const [], this.auditLog});

  final Agents agents;

  /// Browser origins allowed to call the API (CORS). Empty = any localhost origin.
  final List<String> allowedOrigins;

  /// Append-only JSONL audit log; null disables file logging (tests).
  final File? auditLog;

  static const maxUploadBytes = 10 * 1024 * 1024;
  static const allowedMimeTypes = {'application/pdf', 'image/png', 'image/jpeg', 'image/webp', 'text/plain'};

  /// Cases that were uploaded but never exported or rejected are dropped oldest-first.
  static const maxOpenCases = 50;

  final _cases = <String, _Case>{};
  final _random = Random.secure();

  /// Unguessable case id: it is the only handle a client has on a case.
  String _newId() => [for (var i = 0; i < 16; i++) _random.nextInt(256).toRadixString(16).padLeft(2, '0')].join();

  Handler get handler => const Pipeline().addMiddleware(_cors).addHandler(_route);

  Future<Response> _route(Request req) async {
    final seg = req.url.pathSegments;
    try {
      if (req.method == 'GET' && seg.join('/') == 'api/health') {
        return _json({'ok': true, 'model': agents.gemini.model, 'shield': agents.shield});
      }
      if (req.method == 'POST' && seg.length == 2 && seg[0] == 'api' && seg[1] == 'cases') {
        return await _upload(req);
      }
      if (req.method == 'POST' && seg.length == 4 && seg[0] == 'api' && seg[1] == 'cases') {
        final c = _cases[seg[2]];
        if (c == null) return _error(404, 'Unknown case');
        return switch (seg[3]) {
          'check' => await _check(seg[2], c),
          'recommend' => await _recommend(seg[2], c),
          'export' => await _export(seg[2], c, req),
          'reject' => await _reject(seg[2], req),
          _ => _error(404, 'Not found'),
        };
      }
      return _error(404, 'Not found');
    } on GeminiException catch (e) {
      return _error(502, e.message);
    } on FormatException catch (e) {
      return _error(400, 'Invalid request: ${e.message}');
    } catch (e) {
      // Never a stack trace for the client (or on stage).
      stderr.writeln('Unhandled error on ${req.method} /${req.url.path}: $e');
      return _error(500, 'Internal error – see the server log');
    }
  }

  Future<Response> _upload(Request req) async {
    // Refuse oversized bodies before reading them (base64 is 4/3 of the file size).
    if ((req.contentLength ?? 0) > maxUploadBytes * 4 ~/ 3 + 4096) {
      return _error(413, 'File is empty or larger than 10 MB');
    }
    final body = jsonDecode(await req.readAsString());
    if (body is! Map) return _error(400, 'Expected a JSON object');
    final name = body['file_name']?.toString() ?? 'receipt';
    final mime = body['mime_type']?.toString() ?? '';
    if (!allowedMimeTypes.contains(mime)) return _error(415, 'Unsupported file type: $mime');
    final bytes = base64Decode(body['data_base64']?.toString() ?? '');
    if (bytes.isEmpty || bytes.length > maxUploadBytes) return _error(413, 'File is empty or larger than 10 MB');

    final id = _newId();
    final c = _Case(UploadedDoc(name, mime, bytes));
    c.invoice = await agents.extract(c.doc);
    while (_cases.length >= maxOpenCases) {
      _cases.remove(_cases.keys.first);
    }
    _cases[id] = c; // only kept once the Extractor succeeded
    _audit(
      id,
      'extractor',
      'allowed',
      'extracted ${c.invoice!.supplierName ?? '?'}',
      c.invoice!.reasoning,
      tool: 'gemini.extract',
      args: {'file': name, 'mime': mime, 'bytes': bytes.length},
    );
    return _json({'id': id, 'invoice': c.invoice!.toJson()});
  }

  Future<Response> _check(String id, _Case c) async {
    final inv = c.invoice;
    if (inv == null) return _error(409, 'Extract first');
    c.recommendation = null; // a new check invalidates an earlier recommendation
    c.check = await agents.check(inv);
    for (final t in agents.tools.drainCalls()) {
      _audit(
        id,
        'checker',
        t.allowed ? 'allowed' : 'blocked',
        'tool ${t.name} (${t.caller})',
        'result: ${jsonEncode(t.result)}',
        rule: t.allowed ? 'READ_ONLY_TOOL' : 'TOOL_ALLOWLIST',
        tool: t.name,
        args: t.args,
      );
    }
    final blocked = c.check!.status == CheckStatus.blocked;
    _audit(
      id,
      'checker',
      blocked ? 'blocked' : 'allowed',
      c.check!.status.name,
      blocked ? c.check!.injectionEvidence.join(' | ') : c.check!.reasoning,
      rule: blocked ? 'PROMPT_INJECTION' : null,
      tool: 'gemini.check+guard',
      args: {
        'issues': [for (final i in c.check!.issues) i.code],
      },
    );
    return _json(c.check!.toJson());
  }

  Future<Response> _recommend(String id, _Case c) async {
    final inv = c.invoice;
    final chk = c.check;
    if (inv == null || chk == null) return _error(409, 'Check first');
    c.recommendation = await agents.recommend(inv, chk);
    _audit(
      id,
      'approver',
      'pending',
      c.recommendation!.decision,
      c.recommendation!.reasoning,
      rule: 'APPROVAL_REQUIRED',
      tool: 'gemini.recommend',
      args: {'check_status': chk.status.name},
    );
    return _json(c.recommendation!.toJson());
  }

  Future<Response> _export(String id, _Case c, Request req) async {
    final inv = c.invoice;
    final chk = c.check;
    if (inv == null || chk == null) return _error(409, 'Check first');
    final body = jsonDecode(await req.readAsString());
    final by = body is Map ? body['approved_by']?.toString() : null;

    // Hard rules, enforced here and not in the browser.
    String? denied;
    if (chk.status == CheckStatus.blocked) {
      denied = 'Invoice is blocked by the guard';
    } else if (by == 'approver agent' && (chk.status != CheckStatus.ok || c.recommendation?.decision != 'approve')) {
      denied = 'The Approver agent may only approve clean invoices';
    } else if (by != 'human' && by != 'approver agent') {
      denied = 'Missing approval';
    }
    if (denied != null) {
      _audit(
        id,
        'exporter',
        'blocked',
        'export denied',
        denied,
        rule: 'APPROVAL_REQUIRED',
        tool: 'export',
        args: {'approved_by': by},
      );
      return _error(403, denied);
    }

    final booking = await agents.export(inv);
    _audit(
      id,
      'exporter',
      'allowed',
      'booked ${booking.account} (approved by $by)',
      booking.reasoning,
      tool: 'export',
      args: {'approved_by': by, 'account': booking.account},
    );
    agents.tools.markBooked(inv.supplierName, inv.invoiceNumber); // enables the duplicate check
    _cases.remove(id); // done – nothing kept on the server
    return _json(booking.toJson());
  }

  /// Records a rejection (human, Approver agent or guard) and drops the case.
  Future<Response> _reject(String id, Request req) async {
    final body = jsonDecode(await req.readAsString());
    final claimed = body is Map ? body['rejected_by']?.toString() : null;
    final by = const {'human', 'approver agent', 'guard'}.contains(claimed) ? claimed! : 'unknown';
    _audit(
      id,
      by,
      'blocked',
      'rejected',
      'Rejected by $by – nothing written',
      rule: 'APPROVAL_REQUIRED',
      tool: 'export',
      args: {'rejected_by': by},
    );
    _cases.remove(id);
    return _json({'ok': true});
  }

  void _audit(
    String caseId,
    String agent,
    String decision,
    String action,
    String reason, {
    String? rule,
    String? tool,
    Map<String, Object?> args = const {},
  }) {
    final log = auditLog;
    if (log == null) return;
    final entry = {
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'case': caseId,
      'agent': agent,
      'tool': ?tool,
      'args': args,
      'action': action,
      'decision': decision,
      'rule': ?rule,
      'reason': reason,
      'shield': agents.shield ? 'on' : 'off',
    };
    log.writeAsStringSync('${jsonEncode(entry)}\n', mode: FileMode.append);
  }

  // ------------------------------------------------------------------ http helpers

  Handler _cors(Handler inner) => (req) async {
    final origin = req.headers['origin'];
    final ok =
        origin != null &&
        (allowedOrigins.isEmpty
            ? RegExp(r'^http://(localhost|127\.0\.0\.1)(:\d+)?$').hasMatch(origin)
            : allowedOrigins.contains(origin));
    final headers = {
      if (ok) 'Access-Control-Allow-Origin': origin,
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    };
    // A browser page from any other origin is refused outright, so a foreign website
    // cannot fire blind requests at the local API. Non-browser clients send no Origin.
    if (origin != null && !ok) return _error(403, 'Origin not allowed');
    if (req.method == 'OPTIONS') return Response.ok('', headers: headers);
    return (await inner(req)).change(headers: headers);
  };

  static Response _json(Object body) =>
      Response.ok(jsonEncode(body), headers: {'Content-Type': 'application/json; charset=utf-8'});

  static Response _error(int status, String message) => Response(
    status,
    body: jsonEncode({'error': message}),
    headers: {'Content-Type': 'application/json; charset=utf-8'},
  );
}
