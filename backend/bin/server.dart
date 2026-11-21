// Starts the BelegGuard API server.
//
//   GEMINI_API_KEY   required – stays on the server, never sent to the browser
//   GEMINI_MODEL     optional, default gemini-3.6-flash
//   PORT             optional, default 8080
//   ALLOWED_ORIGINS  optional, comma-separated browser origins (default: any localhost)
//
//   cd backend && dart run bin/server.dart

import 'dart:io';

import 'package:belegguard_backend/agents.dart';
import 'package:belegguard_backend/api.dart';
import 'package:belegguard_backend/gemini_client.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

Future<void> main() async {
  final env = {..._readDotEnv(), ...Platform.environment};
  final key = env['GEMINI_API_KEY'] ?? '';
  if (key.isEmpty) {
    stderr.writeln('GEMINI_API_KEY is not set (environment or ../.env).');
    exit(1);
  }
  final model = env['GEMINI_MODEL'] ?? 'gemini-3.6-flash';
  final port = int.tryParse(env['PORT'] ?? '') ?? 8080;
  final shield = (env['SHIELD'] ?? 'on').toLowerCase() != 'off';
  final origins = (env['ALLOWED_ORIGINS'] ?? '').split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  final api = Api(
    Agents(
      GeminiClient(apiKey: key, model: model),
      shield: shield,
    ),
    allowedOrigins: origins,
    auditLog: File('audit_log.jsonl'),
  );
  final handler = const Pipeline().addMiddleware(logRequests()).addHandler(api.handler);
  final server = await io.serve(handler, InternetAddress.loopbackIPv4, port);
  stdout.writeln(
    'BelegGuard API on http://${server.address.host}:${server.port} (model $model, SHIELD=${shield ? 'on' : 'off'})',
  );
  if (!shield) stderr.writeln('WARNING: SHIELD=off – injection guard disabled (demo only).');
}

/// Reads KEY=VALUE lines from the repo's .env (git-ignored) so the demo needs no exports.
Map<String, String> _readDotEnv() {
  final f = File('../.env');
  if (!f.existsSync()) return {};
  return {
    for (final line in f.readAsLinesSync())
      if (line.contains('=') && !line.trimLeft().startsWith('#'))
        line.substring(0, line.indexOf('=')).trim(): line.substring(line.indexOf('=') + 1).trim(),
  };
}
