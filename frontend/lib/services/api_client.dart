// Client for the BelegGuard backend (see backend/lib/api.dart).
// The browser sends the file once; the agents run on the server.

import 'dart:convert';
import 'dart:typed_data';

import 'package:belegguard_shared/models.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

class ApiClient {
  ApiClient(this.baseUrl);
  final String baseUrl;

  static const _timeout = Duration(seconds: 150);

  /// Returns the backend's model and SHIELD state, or null if it is not reachable.
  Future<({String model, bool shield})?> health() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/health')).timeout(const Duration(seconds: 5));
      if (res.statusCode != 200) return null;
      final j = jsonDecode(res.body) as Map;
      return (model: j['model']?.toString() ?? '?', shield: j['shield'] != false);
    } catch (_) {
      return null;
    }
  }

  /// Uploads the receipt and runs the Extractor. Returns the server case id and the fields.
  Future<(String, InvoiceData)> extract(String fileName, String mimeType, Uint8List bytes) async {
    final j = await _post('api/cases', {
      'file_name': fileName,
      'mime_type': mimeType,
      'data_base64': base64Encode(bytes),
    });
    return (j['id'] as String, InvoiceData.fromJson((j['invoice'] as Map).cast<String, dynamic>()));
  }

  Future<CheckResult> check(String id) async => CheckResult.fromJson(await _post('api/cases/$id/check', {}));

  Future<ApprovalRecommendation> recommend(String id) async =>
      ApprovalRecommendation.fromJson(await _post('api/cases/$id/recommend', {}));

  /// Runs the Exporter. The server refuses blocked or unapproved invoices.
  Future<BookingSuggestion> export(String id, {required String approvedBy}) async =>
      BookingSuggestion.fromJson(await _post('api/cases/$id/export', {'approved_by': approvedBy}));

  /// Tells the server about a rejection, so it lands in audit_log.jsonl and the case is dropped.
  Future<void> reject(String id, {required String by}) => _post('api/cases/$id/reject', {'rejected_by': by});

  Future<Map<String, dynamic>> _post(String path, Object body) async {
    final http.Response res;
    try {
      res = await http
          .post(Uri.parse('$baseUrl/$path'), headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
          .timeout(_timeout);
    } catch (e) {
      throw ApiException('Backend not reachable at $baseUrl – is it running? ($e)');
    }
    final Object? j;
    try {
      j = jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      throw ApiException('Backend returned an invalid answer (HTTP ${res.statusCode})');
    }
    if (j is! Map<String, dynamic>) throw ApiException('Backend returned an invalid answer');
    if (res.statusCode != 200) throw ApiException(j['error']?.toString() ?? 'Backend error ${res.statusCode}');
    return j;
  }
}
