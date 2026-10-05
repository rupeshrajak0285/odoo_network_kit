import 'odoo_logger.dart';

/// Configuration for an [OdooClient].
class OdooConfig {
  /// Base URL of the Odoo server, e.g. `https://erp.example.com`.
  final String baseUrl;

  /// Default database (optional if the server has only one DB / dbfilter).
  final String? database;

  final Duration connectTimeout;
  final Duration receiveTimeout;
  final Duration sendTimeout;

  /// Number of retries for network errors (timeouts, connection errors).
  /// Odoo business errors are never retried.
  final int maxRetries;
  final Duration retryDelay;

  /// Logging configuration.
  final OdooLogLevel logLevel;
  final OdooLogger? logger;

  /// Extra headers sent with every request.
  final Map<String, String> headers;

  /// Default context merged into every `call_kw` (e.g. `{'lang': 'en_US'}`).
  final Map<String, dynamic> defaultContext;

  const OdooConfig({
    required this.baseUrl,
    this.database,
    this.connectTimeout = const Duration(seconds: 20),
    this.receiveTimeout = const Duration(seconds: 60),
    this.sendTimeout = const Duration(seconds: 60),
    this.maxRetries = 2,
    this.retryDelay = const Duration(milliseconds: 800),
    this.logLevel = OdooLogLevel.basic,
    this.logger,
    this.headers = const {},
    this.defaultContext = const {},
  });

  /// Builds a config from a plain map — JSON asset, `.env`, remote config,
  /// Firebase Remote Config, etc. Keys: `baseUrl`, `database`, `logLevel`
  /// (`none|basic|body`), `timeoutSeconds`, `maxRetries`, `headers`, `context`.
  factory OdooConfig.fromMap(Map<String, dynamic> m, {OdooLogger? logger}) {
    final timeout =
        Duration(seconds: (m['timeoutSeconds'] as num?)?.toInt() ?? 60);
    return OdooConfig(
      baseUrl: m['baseUrl'] as String,
      database: m['database'] as String?,
      connectTimeout: timeout,
      receiveTimeout: timeout,
      sendTimeout: timeout,
      maxRetries: (m['maxRetries'] as num?)?.toInt() ?? 2,
      logLevel:
          OdooLogLevel.values.byName((m['logLevel'] as String?) ?? 'basic'),
      logger: logger,
      headers: (m['headers'] as Map?)?.cast<String, String>() ?? const {},
      defaultContext:
          (m['context'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

  /// Reads `--dart-define=ODOO_URL=... --dart-define=ODOO_DB=...`
  /// (also `ODOO_LOG_LEVEL`). Same app binary → different server per build.
  factory OdooConfig.fromEnvironment({OdooLogger? logger}) {
    const url = String.fromEnvironment('ODOO_URL');
    const db = String.fromEnvironment('ODOO_DB');
    const level =
        String.fromEnvironment('ODOO_LOG_LEVEL', defaultValue: 'basic');
    if (url.isEmpty) {
      throw StateError(
          'ODOO_URL not set. Run with --dart-define=ODOO_URL=https://...');
    }
    return OdooConfig(
      baseUrl: url,
      database: db.isEmpty ? null : db,
      logLevel: OdooLogLevel.values.byName(level),
      logger: logger,
    );
  }

  OdooConfig copyWith(
          {String? baseUrl, String? database, OdooLogLevel? logLevel}) =>
      OdooConfig(
        baseUrl: baseUrl ?? this.baseUrl,
        database: database ?? this.database,
        connectTimeout: connectTimeout,
        receiveTimeout: receiveTimeout,
        sendTimeout: sendTimeout,
        maxRetries: maxRetries,
        retryDelay: retryDelay,
        logLevel: logLevel ?? this.logLevel,
        logger: logger,
        headers: headers,
        defaultContext: defaultContext,
      );
}
