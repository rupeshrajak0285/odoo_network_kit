import 'package:dio/dio.dart';

import '../odoo_logger.dart';

class OdooLoggingInterceptor extends Interceptor {
  final OdooLogger logger;
  final OdooLogLevel level;

  OdooLoggingInterceptor(this.logger, this.level);

  static const _startKey = '_odoo_start';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startKey] = DateTime.now();
    if (level != OdooLogLevel.none) {
      final b = StringBuffer('➡️  ${options.method} ${options.uri}');
      if (level == OdooLogLevel.body && options.data != null) {
        b.write('\n${logger.formatBody(options.data)}');
      }
      logger.info(b.toString());
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (level != OdooLogLevel.none) {
      final b = StringBuffer('⬅️  ${response.statusCode} '
          '${response.requestOptions.uri} (${_ms(response.requestOptions)}ms)');
      if (level == OdooLogLevel.body) {
        b.write('\n${logger.formatBody(response.data)}');
      }
      logger.info(b.toString());
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (level != OdooLogLevel.none) {
      logger.error('${err.type.name} ${err.requestOptions.uri} '
          '(${_ms(err.requestOptions)}ms) ${err.message ?? ''}');
    }
    handler.next(err);
  }

  int _ms(RequestOptions o) {
    final start = o.extra[_startKey];
    return start is DateTime
        ? DateTime.now().difference(start).inMilliseconds
        : -1;
  }
}
