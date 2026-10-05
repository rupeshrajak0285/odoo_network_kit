/// Base class for every error thrown by the package.
sealed class OdooException implements Exception {
  final String message;
  const OdooException(this.message);
  @override
  String toString() => '$runtimeType: $message';
}

/// No connection / timeout / DNS failure.
class OdooNetworkException extends OdooException {
  final Object? cause;
  const OdooNetworkException(super.message, {this.cause});
}

/// Non-200 HTTP status.
class OdooHttpException extends OdooException {
  final int? statusCode;
  const OdooHttpException(super.message, {this.statusCode});
}

/// Wrong login / password / database.
class OdooAuthException extends OdooException {
  const OdooAuthException(super.message);
}

/// Session expired or invalid — user must log in again.
class OdooSessionExpiredException extends OdooException {
  const OdooSessionExpiredException([super.message = 'Odoo session expired']);
}

/// Error returned by Odoo server code (UserError, ValidationError,
/// AccessError, MissingError, ...).
class OdooServerException extends OdooException {
  /// Python exception name, e.g. `odoo.exceptions.ValidationError`.
  final String? exceptionType;
  final String? debug;
  final int? code;
  final Object? raw;

  const OdooServerException(
    super.message, {
    this.exceptionType,
    this.debug,
    this.code,
    this.raw,
  });

  bool get isAccessError => exceptionType?.contains('AccessError') ?? false;
  bool get isValidationError =>
      exceptionType?.contains('ValidationError') ?? false;
  bool get isUserError => exceptionType?.contains('UserError') ?? false;
  bool get isMissingError => exceptionType?.contains('MissingError') ?? false;

  /// Builds the right exception from an Odoo JSON-RPC `error` object.
  static OdooException fromRpcError(Map<String, dynamic> error) {
    final data = (error['data'] as Map?)?.cast<String, dynamic>() ?? {};
    final name = data['name'] as String?;
    final msg = (data['message'] ?? error['message'] ?? 'Unknown Odoo error')
        .toString();
    final code = error['code'] as int?;
    if (code == 100 || (name?.contains('SessionExpired') ?? false)) {
      return OdooSessionExpiredException(msg);
    }
    if (name?.contains('AccessDenied') ?? false) {
      return OdooAuthException(msg);
    }
    return OdooServerException(
      msg,
      exceptionType: name,
      debug: data['debug'] as String?,
      code: code,
      raw: error,
    );
  }
}
