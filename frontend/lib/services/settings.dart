// Browser-side settings (localStorage). The Gemini API key and model live on the
// backend – the browser only knows where the backend is.

import 'package:web/web.dart' as web;

class Settings {
  static const _defaultBackend = String.fromEnvironment('BACKEND_URL', defaultValue: 'http://localhost:8080');

  static String? _read(String k) {
    try {
      return web.window.localStorage.getItem(k);
    } catch (_) {
      return null;
    }
  }

  static void _write(String k, String? v) {
    try {
      if (v == null || v.isEmpty) {
        web.window.localStorage.removeItem(k);
      } else {
        web.window.localStorage.setItem(k, v);
      }
    } catch (_) {}
  }

  static String get backendUrl {
    final saved = _read('bg_backend_url');
    return saved == null || saved.isEmpty ? _defaultBackend : saved;
  }

  static set backendUrl(String v) => _write('bg_backend_url', v.trim().replaceAll(RegExp(r'/+$'), ''));

  static bool get autoApprove => _read('bg_auto_approve') == '1';
  static set autoApprove(bool v) => _write('bg_auto_approve', v ? '1' : null);
}
