// Receipt archive ("Belegkonto"): approved receipts are copied and filed here.
//
// Storage stays in this browser (hackathon scope, no backend):
//  * localStorage "bg_archive" – JSON list of filed receipts (metadata + booking, small)
//  * IndexedDB "belegguard"/"files" – copy of each original file as raw bytes,
//    keyed by receipt id (hundreds of MB available, unlike localStorage's ~5 MB)
// Older originals saved as base64 in localStorage ("bg_file_<id>") are still read.

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'models.dart';

class Archive {
  static const _indexKey = 'bg_archive';
  static const _dbName = 'belegguard';
  static const _store = 'files';
  static String _legacyKey(String id) => 'bg_file_$id';

  static Future<web.IDBDatabase>? _dbFuture;

  static Future<web.IDBDatabase> _db() => _dbFuture ??= () {
        final c = Completer<web.IDBDatabase>();
        final req = web.window.indexedDB.open(_dbName, 1);
        req.onupgradeneeded = ((web.Event _) {
          final db = req.result as web.IDBDatabase;
          if (!db.objectStoreNames.contains(_store)) db.createObjectStore(_store);
        }).toJS;
        req.onsuccess = ((web.Event _) => c.complete(req.result as web.IDBDatabase)).toJS;
        req.onerror = ((web.Event _) {
          _dbFuture = null;
          c.completeError(StateError('IndexedDB unavailable: ${req.error?.message ?? 'unknown error'}'));
        }).toJS;
        return c.future;
      }();

  static Future<JSAny?> _request(web.IDBRequest r) {
    final c = Completer<JSAny?>();
    r.onsuccess = ((web.Event _) => c.complete(r.result)).toJS;
    r.onerror = ((web.Event _) => c.completeError(StateError(r.error?.message ?? 'IndexedDB error'))).toJS;
    return c.future;
  }

  static Future<web.IDBObjectStore> _files(String mode) async =>
      (await _db()).transaction(_store.toJS, mode).objectStore(_store);

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
  /// be copied; the booking record is kept anyway.
  static Future<bool> file(InvoiceCase c, List<InvoiceCase> all) async {
    var copied = false;
    final bytes = c.bytes;
    if (bytes != null) {
      try {
        await _request((await _files('readwrite')).put(bytes.toJS, c.id.toJS));
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

  static Future<void> remove(InvoiceCase c, List<InvoiceCase> all) async {
    all.removeWhere((e) => e.id == c.id);
    try {
      _saveIndex(all);
      web.window.localStorage.removeItem(_legacyKey(c.id));
      await _request((await _files('readwrite')).delete(c.id.toJS));
    } catch (_) {}
  }

  static Future<Uint8List?> original(InvoiceCase c) async {
    try {
      final r = await _request((await _files('readonly')).get(c.id.toJS));
      if (r != null) return (r as JSUint8Array).toDart;
    } catch (_) {}
    try {
      final b64 = web.window.localStorage.getItem(_legacyKey(c.id));
      return b64 == null ? null : base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  /// Triggers a browser download of the stored original.
  static Future<bool> downloadOriginal(InvoiceCase c) async {
    final bytes = await original(c);
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
