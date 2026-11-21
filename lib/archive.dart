// Receipt archive ("Belegkonto"): approved receipts are copied and filed here.
//
// Storage is this browser's localStorage (hackathon scope, no backend):
//  * bg_archive        – JSON list of filed receipts (metadata + booking)
//  * bg_file_<id>      – base64 copy of the original file
// localStorage holds roughly 5 MB per site. If a copy does not fit, the record
// is still filed but marked as "original not stored".

import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'models.dart';

class Archive {
  static const _indexKey = 'bg_archive';
  static String _fileKey(String id) => 'bg_file_$id';

  static List<InvoiceCase> load() {
    try {
      final raw = web.window.localStorage.getItem(_indexKey);
      if (raw == null || raw.isEmpty) return [];
      return (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((m) => InvoiceCase.fromJson(m.cast<String, dynamic>()))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static void _saveIndex(List<InvoiceCase> all) =>
      web.window.localStorage.setItem(_indexKey, jsonEncode(all.map((c) => c.toJson()).toList()));

  /// Files an approved receipt. Returns false if the original file could not
  /// be copied (storage full); the booking record is kept anyway.
  static bool file(InvoiceCase c, List<InvoiceCase> all) {
    var copied = false;
    final bytes = c.bytes;
    if (bytes != null) {
      try {
        web.window.localStorage.setItem(_fileKey(c.id), base64Encode(bytes));
        copied = true;
      } catch (_) {
        copied = false;
      }
    }
    c.hasOriginal = copied;
    all.removeWhere((e) => e.id == c.id);
    all.add(c);
    _saveIndex(all);
    return copied;
  }

  static void remove(InvoiceCase c, List<InvoiceCase> all) {
    all.removeWhere((e) => e.id == c.id);
    try {
      web.window.localStorage.removeItem(_fileKey(c.id));
      _saveIndex(all);
    } catch (_) {}
  }

  static Uint8List? original(InvoiceCase c) {
    try {
      final b64 = web.window.localStorage.getItem(_fileKey(c.id));
      return b64 == null ? null : base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  /// Triggers a browser download of the stored original.
  static bool downloadOriginal(InvoiceCase c) {
    final bytes = original(c);
    if (bytes == null) return false;
    final blob = web.Blob(<JSAny>[bytes.toJS].toJS, web.BlobPropertyBag(type: c.mimeType));
    final url = web.URL.createObjectURL(blob);
    (web.document.createElement('a') as web.HTMLAnchorElement)
      ..href = url
      ..download = c.fileName
      ..click();
    web.URL.revokeObjectURL(url);
    return true;
  }
}
