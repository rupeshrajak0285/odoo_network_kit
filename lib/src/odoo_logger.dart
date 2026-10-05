import 'dart:convert';

/// How much network traffic is logged.
enum OdooLogLevel {
  /// Nothing.
  none,

  /// Method, URL, status and duration.
  basic,

  /// [basic] + request/response bodies (passwords masked).
  body,
}

/// Plug in your own sink (Crashlytics, Sentry, `debugPrint`, file...).
typedef OdooLogSink = void Function(String message);

/// Default logger. Override [sink] to redirect output.
class OdooLogger {
  final OdooLogSink sink;
  final int maxBodyLength;

  /// Keys whose values are masked in logs.
  final Set<String> sensitiveKeys;

  OdooLogger({
    OdooLogSink? sink,
    this.maxBodyLength = 4000,
    this.sensitiveKeys = const {
      'password',
      'login_password',
      'api_key',
      'session_id'
    },
  }) : sink = sink ?? print;

  static const _encoder = JsonEncoder.withIndent('  ');

  void info(String msg) => sink('[Odoo] $msg');
  void error(String msg) => sink('[Odoo] ❌ $msg');

  String formatBody(Object? body) {
    if (body == null) return '';
    String text;
    try {
      text = _encoder.convert(_mask(body is String ? jsonDecode(body) : body));
    } catch (_) {
      text = body.toString();
    }
    return text.length > maxBodyLength
        ? '${text.substring(0, maxBodyLength)}… (${text.length} chars)'
        : text;
  }

  Object? _mask(Object? v) {
    if (v is Map) {
      return v.map((k, val) =>
          MapEntry(k, sensitiveKeys.contains(k) ? '***' : _mask(val)));
    }
    if (v is List) return v.map(_mask).toList();
    return v;
  }
}
