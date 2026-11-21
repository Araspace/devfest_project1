// Minimal client for the Google Gemini API (generativelanguage.googleapis.com).
// Called straight from the browser with an API key from Google AI Studio.

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
      'generationConfig': {'responseMimeType': 'application/json', 'temperature': 0},
    };

    final http.Response res;
    try {
      res = await http
          .post(uri,
              headers: {'Content-Type': 'application/json', 'x-goog-api-key': apiKey}, body: jsonEncode(body))
          .timeout(const Duration(seconds: 90));
    } catch (e) {
      throw GeminiException('Could not reach the Gemini API: $e');
    }

    final decoded = jsonDecode(utf8.decode(res.bodyBytes));
    if (res.statusCode != 200) {
      final err = decoded is Map ? decoded['error'] : null;
      final msg = err is Map ? err['message'] : null;
      throw GeminiException('Gemini API error ${res.statusCode}: ${msg ?? res.body}');
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
    final json = jsonDecode(text);
    if (json is! Map<String, dynamic>) throw GeminiException('Gemini did not return a JSON object');
    return json;
  }
}
