import 'package:dio/dio.dart';

import '../odoo_logger.dart';

/// Retries only transient network failures, with linear backoff.
class OdooRetryInterceptor extends Interceptor {
  final Dio dio;
  final int maxRetries;
  final Duration delay;
  final OdooLogger? logger;

  OdooRetryInterceptor({
    required this.dio,
    required this.maxRetries,
    required this.delay,
    this.logger,
  });

  static const _attemptKey = '_odoo_attempt';

  bool _shouldRetry(DioException e) =>
      e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.sendTimeout ||
      e.type == DioExceptionType.connectionError ||
      (e.response?.statusCode ?? 0) >= 502;

  @override
  Future<void> onError(
      DioException err, ErrorInterceptorHandler handler) async {
    final attempt = (err.requestOptions.extra[_attemptKey] as int?) ?? 0;
    if (attempt >= maxRetries || !_shouldRetry(err)) {
      return handler.next(err);
    }
    final next = attempt + 1;
    logger?.info('🔁 Retry $next/$maxRetries ${err.requestOptions.uri}');
    await Future.delayed(delay * next);
    err.requestOptions.extra[_attemptKey] = next;
    try {
      handler.resolve(await dio.fetch(err.requestOptions));
    } on DioException catch (e) {
      handler.next(e);
    }
  }
}
