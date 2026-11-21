// Minimal client for the Google Gemini API (generativelanguage.googleapis.com).
// Called straight from the browser with an API key from Google AI Studio.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

sealed class GeminiPart {
  Map<String, dynamic> toJson();
}

class TextIn extends GeminiPart {
  TextIn(this.text);
  final String text;
  @override
  Map<String, dynamic> toJson() => {'text': text};
}

class FileIn extends GeminiPart {
  FileIn(this.mimeType, this.bytes);
  final String mimeType;
  final Uint8List bytes;
  @override
  Map<String, dynamic> toJson() => {
    'inline_data': {'mime_type': mimeType, 'data': base64Encode(bytes)},
  };
}

class GeminiException implements Exception {
  GeminiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class GeminiClient {
  GeminiClient({required this.apiKey, required this.model});
  final String apiKey;
  final String model;

  /// Tried in order when the chosen model is overloaded or hangs. Gemini capacity
  /// varies a lot per model and minute; during the DevFest the big Flash models
  /// regularly hung while the Lite models still answered in a few seconds.
  static const fallbackModels = [
    'gemini-3.6-flash',
    'gemini-3.5-flash',
    'gemini-3.1-flash-lite',
    'gemini-3.5-flash-lite',
    'gemini-flash-lite-latest',
  ];

  /// Model that answered the last request. Shared by all clients so the next agent
  /// starts with a model that is known to work instead of waiting on a busy one again.
  static String? lastModel;

  static const _timeout = Duration(seconds: 25);

  /// Sends one request with a fixed system instruction and returns the parsed
  /// JSON object the model produced.
  Future<Map<String, dynamic>> generateJson({required String system, required List<GeminiPart> parts}) async {
    final contents = [
      {'role': 'user', 'parts': parts.map((p) => p.toJson()).toList()},
    ];
    Map<String, dynamic> body(String m, String thinkingLevel) {
      final isGemini3 = m.startsWith('gemini-3');
      return {
        'system_instruction': {
          'parts': [
            {'text': system},
          ],
        },
        'contents': contents,
        'generationConfig': {
          'responseMimeType': 'application/json',
          // Gemini 3 models must run at the default temperature (1.0): lower values make them
          // loop until the request times out. Older models stay deterministic.
          if (!isGemini3) 'temperature': 0,
          // Every agent is a pure extract/classify task with fixed rules. Thinking adds
          // tens of seconds per call (default level is "high") without better results.
          if (isGemini3) 'thinkingConfig': {'thinkingLevel': thinkingLevel},
        },
      };
    }

    // Overloaded models either answer 503 or simply hang. Instead of waiting, move on
    // to the next model quickly.
    final models = {?lastModel, model, ...fallbackModels}.toList();
    http.Response? res;
    final problems = <String>[];
    for (final m in models) {
      final uri = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$m:generateContent');
      var thinkingLevel = 'minimal';
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          res = await http
              .post(
                uri,
                headers: {'Content-Type': 'application/json', 'x-goog-api-key': apiKey},
                body: jsonEncode(body(m, thinkingLevel)),
              )
              .timeout(_timeout);
        } on TimeoutException {
          res = null;
          problems.add('$m: no answer within ${_timeout.inSeconds} s');
          break;
        } catch (e) {
          res = null;
          problems.add('$m: $e');
          break;
        }
        // Not every model supports "minimal" thinking – retry the same model with "low".
        if (res.statusCode == 400 && thinkingLevel == 'minimal' && res.body.toLowerCase().contains('thinking')) {
          thinkingLevel = 'low';
          continue;
        }
        break;
      }
      final code = res?.statusCode;
      if (code != null && !const {404, 429, 500, 503}.contains(code)) {
        lastModel = m;
        break;
      }
      if (code != null) problems.add('$m: HTTP $code');
      res = null;
    }
    final r = res;
    if (r == null) {
      throw GeminiException(
        'All Gemini models are busy or unreachable right now – try again in a minute.\n${problems.join('\n')}',
      );
    }

    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(r.bodyBytes));
    } on FormatException {
      decoded = null;
    }
    if (r.statusCode != 200 || decoded is! Map) {
      final err = decoded is Map ? decoded['error'] : null;
      final msg = err is Map ? err['message'] : null;
      final hint = r.statusCode == 404 ? ' → Open Settings (top right) and enter a current model name.' : '';
      throw GeminiException('Gemini API error ${r.statusCode}: ${msg ?? r.body}$hint');
    }

    final candidates = (decoded['candidates'] as List?) ?? const [];
    if (candidates.isEmpty) {
      final reason = decoded['promptFeedback']?['blockReason'];
      throw GeminiException('Gemini returned no answer${reason != null ? ' (blocked: $reason)' : ''}');
    }
    final outParts = (candidates.first['content']?['parts'] as List?) ?? const [];
    var text = outParts.where((p) => p['thought'] != true).map((p) => p['text'] ?? '').join().trim();
    if (text.startsWith('```')) {
      text = text.replaceFirst(RegExp(r'^```(json)?'), '').replaceFirst(RegExp(r'```$'), '').trim();
    }
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      final finish = candidates.first['finishReason'];
      throw GeminiException('Gemini returned invalid JSON${finish != null ? ' (finish reason: $finish)' : ''}');
    }
    if (json is! Map<String, dynamic>) throw GeminiException('Gemini did not return a JSON object');
    return json;
  }
}
