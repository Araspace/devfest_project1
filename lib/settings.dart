// App settings. The Gemini API key is kept in this browser only (localStorage)
// and can also be baked in at build time with --dart-define=GEMINI_API_KEY=...

import 'package:web/web.dart' as web;

class Settings {
  static const _envKey = String.fromEnvironment('GEMINI_API_KEY');
  static const _envModel = String.fromEnvironment('GEMINI_MODEL', defaultValue: 'gemini-2.5-flash');

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

  static String get apiKey => _read('bg_api_key') ?? _envKey;
  static set apiKey(String v) => _write('bg_api_key', v.trim());

  static String get model => _read('bg_model') ?? _envModel;
  static set model(String v) => _write('bg_model', v.trim());

  static bool get autoApprove => _read('bg_auto_approve') == '1';
  static set autoApprove(bool v) => _write('bg_auto_approve', v ? '1' : null);
}
