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

  bool get _isGemini3 => model.startsWith('gemini-3');

  /// Sends one request with a fixed system instruction and returns the parsed
  /// JSON object the model produced.
  Future<Map<String, dynamic>> generateJson({
    required String system,
    required List<GeminiPart> parts,
  }) async {
    final uri = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent');
    final body = {
      'system_instruction': {
        'parts': [
          {'text': system},
        ],
      },
      'contents': [
        {'role': 'user', 'parts': parts.map((p) => p.toJson()).toList()},
      ],
      'generationConfig': {
        'responseMimeType': 'application/json',
        // Gemini 3 models must run at the default temperature (1.0): lower values make them
        // loop until the request times out. Older models stay deterministic.
        if (!_isGemini3) 'temperature': 0,
        // Default thinking level is "high", which is far too slow for a live demo.
        if (_isGemini3) 'thinkingConfig': {'thinkingLevel': 'low'},
      },
    };

    // Retry transient errors (rate limit / overload) – common during live demos.
    http.Response? res;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        res = await http
            .post(uri,
                headers: {'Content-Type': 'application/json', 'x-goog-api-key': apiKey}, body: jsonEncode(body))
            .timeout(const Duration(seconds: 120));
      } on TimeoutException {
        // Retrying a request that already took two minutes only multiplies the wait.
        throw GeminiException('Gemini did not answer within 120 s. Try again or pick a faster model in Settings.');
      } catch (e) {
        if (attempt == 2) throw GeminiException('Could not reach the Gemini API: $e');
        await Future.delayed(Duration(seconds: 2 << attempt));
        continue;
      }
      if (!const {429, 500, 503}.contains(res.statusCode) || attempt == 2) break;
      await Future.delayed(Duration(seconds: 2 << attempt));
    }

    final r = res!;
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
