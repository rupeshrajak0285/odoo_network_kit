import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'interceptors/logging_interceptor.dart';
import 'interceptors/retry_interceptor.dart';
import 'odoo_config.dart';
import 'odoo_exception.dart';
import 'odoo_logger.dart';
import 'odoo_page.dart';
import 'odoo_session.dart';
import 'session_store.dart';

/// Main entry point: one instance per Odoo server.
///
/// ```dart
/// final odoo = OdooClient(OdooConfig(baseUrl: 'https://erp.x.com', database: 'prod'));
/// await odoo.restoreSession();
/// if (!odoo.isLoggedIn) await odoo.login('admin', 'admin');
/// final partners = await odoo.searchRead('res.partner', fields: ['name']);
/// ```
class OdooClient {
  final OdooConfig config;
  final OdooSessionStore sessionStore;
  late final Dio dio;
  late final OdooLogger logger;

  OdooSession? _session;
  int _rpcId = 0;

  final _sessionController = StreamController<OdooSession?>.broadcast();

  /// Emits on login, logout and session expiry (null = logged out).
  Stream<OdooSession?> get sessionStream => _sessionController.stream;

  /// Called when the server reports the session expired.
  /// Use it to navigate to the login screen.
  void Function()? onSessionExpired;

  OdooClient(
    this.config, {
    OdooSessionStore? sessionStore,
    Dio? dio,
    this.onSessionExpired,
  }) : sessionStore = sessionStore ?? InMemorySessionStore() {
    logger = config.logger ?? OdooLogger();
    this.dio = dio ??
        Dio(BaseOptions(
          baseUrl: config.baseUrl.replaceAll(RegExp(r'/+$'), ''),
          connectTimeout: config.connectTimeout,
          receiveTimeout: config.receiveTimeout,
          sendTimeout: config.sendTimeout,
          contentType: Headers.jsonContentType,
          responseType: ResponseType.json,
          headers: config.headers,
        ));
    this.dio.interceptors.addAll([
      InterceptorsWrapper(onRequest: (o, h) {
        final sid = _session?.sessionId;
        if (sid != null && sid.isNotEmpty) {
          o.headers['Cookie'] = 'session_id=$sid';
        }
        h.next(o);
      }, onResponse: (r, h) {
        _captureSessionCookie(r.headers);
        h.next(r);
      }),
      OdooLoggingInterceptor(logger, config.logLevel),
      OdooRetryInterceptor(
        dio: this.dio,
        maxRetries: config.maxRetries,
        delay: config.retryDelay,
        logger: config.logLevel == OdooLogLevel.none ? null : logger,
      ),
    ]);
  }

  OdooSession? get session => _session;
  bool get isLoggedIn => _session != null;

  // ---------------------------------------------------------------- session

  /// Loads a saved session from [sessionStore]. Returns true if found.
  /// Pass [validate] to also check it against the server.
  Future<bool> restoreSession({bool validate = false}) async {
    final s = await sessionStore.read();
    if (s == null) return false;
    _setSession(s, persist: false);
    if (!validate) return true;
    try {
      if (s.usesApiKey) {
        await callKw('res.users', 'read', args: [
          [s.userId]
        ], kwargs: {
          'fields': ['id']
        });
      } else {
        await rpc('/web/session/get_session_info');
      }
      return true;
    } on OdooSessionExpiredException {
      return false;
    } on OdooAuthException {
      await _clearSession();
      return false;
    }
  }

  Future<OdooSession> login(String login, String password,
      {String? database}) async {
    final db = database ?? config.database;
    _session = null;
    _pendingSessionId = null;
    final Map<String, dynamic> result;
    try {
      result = await rpc('/web/session/authenticate', params: {
        'db': db,
        'login': login,
        'password': password,
      }) as Map<String, dynamic>;
    } on OdooServerException catch (e) {
      throw OdooAuthException(e.message);
    }
    if (result['uid'] == null || result['uid'] == false) {
      throw const OdooAuthException('Invalid login or password');
    }
    final sid = _pendingSessionId;
    if (sid == null) {
      throw const OdooAuthException('Server did not return a session cookie');
    }
    final s = OdooSession.fromAuthResult(sid, result);
    await _setSession(s.database.isEmpty && db != null
        ? OdooSession.fromAuthResult(sid, {...result, 'db': db})
        : s);
    logger.info('✅ Logged in as ${s.username} (uid ${s.userId})');
    return _session!;
  }

  /// Authenticates with an Odoo **API key** (Settings → My Profile → Account
  /// Security → New API Key). Recommended for production: keys can be revoked
  /// and are not affected by password changes or 2FA.
  ///
  /// In this mode all model calls use `/jsonrpc` (`execute_kw`). Custom
  /// `type='json'` controllers via [rpc] need a web session, so use [login]
  /// for those.
  Future<OdooSession> loginWithApiKey(String login, String apiKey,
      {String? database}) async {
    final db = database ?? config.database;
    if (db == null) {
      throw const OdooAuthException('database is required for API key auth');
    }
    _session = null;
    final uid = await rpc('/jsonrpc', params: {
      'service': 'common',
      'method': 'authenticate',
      'args': [db, login, apiKey, <String, dynamic>{}],
    });
    if (uid is! int || uid <= 0) {
      throw const OdooAuthException('Invalid login or API key');
    }
    final s = OdooSession(
      sessionId: '',
      userId: uid,
      database: db,
      username: login,
      apiKey: apiKey,
    );
    await _setSession(s);
    logger.info('✅ API key auth OK for $login (uid $uid)');
    return s;
  }

  Future<void> logout() async {
    try {
      if (isLoggedIn && !(_session!.usesApiKey)) {
        await rpc('/web/session/destroy');
      }
    } catch (_) {
      // ignore: server-side logout is best effort
    }
    await _clearSession();
  }

  // ------------------------------------------------------------------- rpc

  /// Low-level JSON-RPC call to any Odoo route (including custom controllers
  /// declared with `type='json'`).
  Future<dynamic> rpc(String path,
      {Map<String, dynamic> params = const {},
      CancelToken? cancelToken}) async {
    final Response response;
    try {
      response = await dio.post(
        path,
        data: {
          'jsonrpc': '2.0',
          'method': 'call',
          'id': ++_rpcId,
          'params': params,
        },
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      throw _mapDioError(e);
    }

    final body = response.data;
    if (body is! Map) {
      throw OdooHttpException(
          'Unexpected response: not JSON (is the URL '
          'correct?)',
          statusCode: response.statusCode);
    }
    final error = body['error'];
    if (error is Map) {
      final ex = OdooServerException.fromRpcError(error.cast());
      if (ex is OdooSessionExpiredException) await _handleExpired();
      throw ex;
    }
    return body['result'];
  }

  /// Calls `/web/dataset/call_kw` — any model method.
  Future<dynamic> callKw(
    String model,
    String method, {
    List<dynamic> args = const [],
    Map<String, dynamic> kwargs = const {},
    Map<String, dynamic>? context,
    CancelToken? cancelToken,
  }) {
    final ctx = {
      ...?_session?.userContext,
      ...config.defaultContext,
      ...?kwargs['context'] as Map<String, dynamic>?,
      ...?context,
    };
    final s = _session;
    if (s != null && s.usesApiKey) {
      return rpc('/jsonrpc',
          params: {
            'service': 'object',
            'method': 'execute_kw',
            'args': [
              s.database,
              s.userId,
              s.apiKey,
              model,
              method,
              args,
              {...kwargs, 'context': ctx},
            ],
          },
          cancelToken: cancelToken);
    }
    return rpc('/web/dataset/call_kw/$model/$method',
        params: {
          'model': model,
          'method': method,
          'args': args,
          'kwargs': {...kwargs, 'context': ctx},
        },
        cancelToken: cancelToken);
  }

  // ------------------------------------------------------------ ORM helpers

  Future<List<Map<String, dynamic>>> searchRead(
    String model, {
    List<dynamic> domain = const [],
    List<String> fields = const [],
    int? limit,
    int offset = 0,
    String? order,
    Map<String, dynamic>? context,
    CancelToken? cancelToken,
  }) async {
    final res = await callKw(model, 'search_read',
        kwargs: {
          'domain': domain,
          'fields': fields,
          'offset': offset,
          if (limit != null) 'limit': limit,
          if (order != null) 'order': order,
        },
        context: context,
        cancelToken: cancelToken);
    return (res as List)
        .cast<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  Future<List<Map<String, dynamic>>> read(String model, List<int> ids,
      {List<String> fields = const [], Map<String, dynamic>? context}) async {
    final res = await callKw(model, 'read',
        args: [ids], kwargs: {'fields': fields}, context: context);
    return (res as List)
        .cast<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  Future<List<int>> search(String model,
      {List<dynamic> domain = const [],
      int? limit,
      int offset = 0,
      String? order}) async {
    final res = await callKw(model, 'search', args: [
      domain
    ], kwargs: {
      'offset': offset,
      if (limit != null) 'limit': limit,
      if (order != null) 'order': order,
    });
    return (res as List).cast<int>();
  }

  Future<int> searchCount(String model,
          {List<dynamic> domain = const []}) async =>
      await callKw(model, 'search_count', args: [domain]) as int;

  /// Creates one record and returns its id.
  Future<int> create(String model, Map<String, dynamic> values,
      {Map<String, dynamic>? context}) async {
    final res = await callKw(model, 'create', args: [values], context: context);
    return res is List ? res.first as int : res as int;
  }

  Future<bool> write(String model, List<int> ids, Map<String, dynamic> values,
          {Map<String, dynamic>? context}) async =>
      await callKw(model, 'write', args: [ids, values], context: context) ==
      true;

  Future<bool> unlink(String model, List<int> ids) async =>
      await callKw(model, 'unlink', args: [ids]) == true;

  Future<Map<String, dynamic>> fieldsGet(String model,
          {List<String> attributes = const [
            'string',
            'type',
            'required'
          ]}) async =>
      (await callKw(model, 'fields_get', kwargs: {'attributes': attributes})
              as Map)
          .cast<String, dynamic>();

  /// `search_read` + `search_count` together. Use for lists with paging.
  Future<OdooPage<Map<String, dynamic>>> searchReadPaginated(
    String model, {
    List<dynamic> domain = const [],
    List<String> fields = const [],
    int limit = 40,
    int offset = 0,
    String? order,
    Map<String, dynamic>? context,
  }) async {
    final results = await Future.wait([
      searchRead(model,
          domain: domain,
          fields: fields,
          limit: limit,
          offset: offset,
          order: order,
          context: context),
      searchCount(model, domain: domain),
    ]);
    return OdooPage(
      records: results[0] as List<Map<String, dynamic>>,
      total: results[1] as int,
      offset: offset,
      limit: limit,
    );
  }

  /// `name_search` — for dropdowns / autocomplete. Returns `(id, displayName)`.
  Future<List<(int, String)>> nameSearch(
    String model, {
    String name = '',
    List<dynamic> domain = const [],
    String operator = 'ilike',
    int limit = 100,
    Map<String, dynamic>? context,
  }) async {
    final res = await callKw(model, 'name_search',
        kwargs: {
          'name': name,
          'args': domain,
          'operator': operator,
          'limit': limit,
        },
        context: context);
    return (res as List)
        .map((e) => ((e as List)[0] as int, e[1].toString()))
        .toList();
  }

  /// `name_create` — create a record from only its display name.
  Future<int> nameCreate(String model, String name,
      {Map<String, dynamic>? context}) async {
    final res =
        await callKw(model, 'name_create', args: [name], context: context);
    return (res as List).first as int;
  }

  /// `read_group` — aggregated data for dashboards / reports.
  Future<List<Map<String, dynamic>>> readGroup(
    String model, {
    List<dynamic> domain = const [],
    List<String> fields = const [],
    required List<String> groupBy,
    int? limit,
    int offset = 0,
    String? orderBy,
    bool lazy = true,
    Map<String, dynamic>? context,
  }) async {
    final res = await callKw(model, 'read_group',
        kwargs: {
          'domain': domain,
          'fields': fields,
          'groupby': groupBy,
          'offset': offset,
          'lazy': lazy,
          if (limit != null) 'limit': limit,
          if (orderBy != null) 'orderby': orderBy,
        },
        context: context);
    return _asMapList(res);
  }

  /// `default_get` — default values for a new form.
  Future<Map<String, dynamic>> defaultGet(String model, List<String> fields,
          {Map<String, dynamic>? context}) async =>
      (await callKw(model, 'default_get', args: [fields], context: context)
              as Map)
          .cast<String, dynamic>();

  /// `copy` — duplicates a record, returns the new id.
  Future<int> copy(String model, int id,
      {Map<String, dynamic>? defaults, Map<String, dynamic>? context}) async {
    final res = await callKw(model, 'copy',
        args: [id],
        kwargs: {if (defaults != null) 'default': defaults},
        context: context);
    return res is List ? res.first as int : res as int;
  }

  /// Returns true if the current user has [operation] rights on [model]
  /// (`read`, `write`, `create`, `unlink`). Never throws.
  Future<bool> checkAccess(String model, String operation) async {
    try {
      await callKw(model, 'check_access_rights',
          args: [operation], kwargs: {'raise_exception': false});
      return true;
    } on OdooServerException {
      return false;
    }
  }

  // ------------------------------------------------------- attachments/binary

  /// Uploads a file as `ir.attachment`. Returns the attachment id.
  Future<int> uploadAttachment({
    required String fileName,
    required Uint8List bytes,
    String? resModel,
    int? resId,
    String? mimeType,
  }) =>
      create('ir.attachment', {
        'name': fileName,
        'datas': base64Encode(bytes),
        'type': 'binary',
        if (resModel != null) 'res_model': resModel,
        if (resId != null) 'res_id': resId,
        if (mimeType != null) 'mimetype': mimeType,
      });

  /// Downloads a binary field (e.g. `image_1920`, `datas`) as bytes.
  Future<Uint8List?> readBinaryField(String model, int id, String field) async {
    final rows = await read(model, [id], fields: [field]);
    final v = rows.isEmpty ? null : rows.first[field];
    if (v is! String || v.isEmpty) return null;
    return base64Decode(v);
  }

  /// Raw GET to any Odoo URL (e.g. `/web/content/123`, `/report/pdf/...`),
  /// authenticated with the current session cookie.
  Future<Uint8List> downloadBytes(String path,
      {Map<String, dynamic>? query, CancelToken? cancelToken}) async {
    try {
      final r = await dio.get<List<int>>(path,
          queryParameters: query,
          cancelToken: cancelToken,
          options: Options(responseType: ResponseType.bytes));
      return Uint8List.fromList(r.data ?? const []);
    } on DioException catch (e) {
      throw _mapDioError(e);
    }
  }

  /// Absolute URL of a record image, for `Image.network`.
  /// Pass [sessionHeaders] to the image widget for authentication.
  String imageUrl(String model, int id,
      {String field = 'image_128', String? unique}) {
    final base = dio.options.baseUrl;
    final u = unique != null ? '&unique=$unique' : '';
    return '$base/web/image?model=$model&id=$id&field=$field$u';
  }

  /// Headers needed to fetch authenticated resources (images, downloads)
  /// outside this client, e.g. `Image.network(url, headers: odoo.sessionHeaders)`.
  Map<String, String> get sessionHeaders {
    final sid = _session?.sessionId;
    return sid == null ? const {} : {'Cookie': 'session_id=$sid'};
  }

  /// Server version info (no login required).
  Future<Map<String, dynamic>> versionInfo() async =>
      (await rpc('/web/webclient/version_info') as Map).cast<String, dynamic>();

  /// List databases (if `list_db` is enabled on the server).
  Future<List<String>> listDatabases() async =>
      (await rpc('/web/database/list') as List).cast<String>();

  void dispose() {
    _sessionController.close();
    dio.close();
  }

  // --------------------------------------------------------------- internal

  String? _pendingSessionId;

  void _captureSessionCookie(Headers headers) {
    for (final c in headers['set-cookie'] ?? const <String>[]) {
      final m = RegExp(r'session_id=([^;]+)').firstMatch(c);
      if (m == null) continue;
      final sid = m.group(1)!;
      _pendingSessionId = sid;
      final s = _session;
      if (s != null && s.sessionId != sid) {
        // Odoo rotated the session id — keep it in sync.
        _setSession(s.copyWith(sessionId: sid));
      }
    }
  }

  Future<void> _setSession(OdooSession s, {bool persist = true}) async {
    _session = s;
    _sessionController.add(s);
    if (persist) await sessionStore.write(s);
  }

  Future<void> _clearSession() async {
    _session = null;
    _pendingSessionId = null;
    _sessionController.add(null);
    await sessionStore.clear();
  }

  Future<void> _handleExpired() async {
    if (_session == null) return;
    logger.error('Session expired');
    await _clearSession();
    onSessionExpired?.call();
  }

  List<Map<String, dynamic>> _asMapList(dynamic res) =>
      (res as List).cast<Map>().map((e) => e.cast<String, dynamic>()).toList();

  OdooException _mapDioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return OdooNetworkException('Request timed out', cause: e);
      case DioExceptionType.connectionError:
        return OdooNetworkException('No connection to server', cause: e);
      case DioExceptionType.badResponse:
        final code = e.response?.statusCode;
        final loc = e.response?.headers.value('location');
        if (code != null && code >= 300 && code < 400 && loc != null) {
          return OdooHttpException(
              'Server redirected to $loc — set baseUrl to that host '
              '(check http vs https / www)',
              statusCode: code);
        }
        if (code == 404) {
          return OdooHttpException('Route not found: ${e.requestOptions.path}',
              statusCode: code);
        }
        return OdooHttpException('HTTP $code', statusCode: code);
      case DioExceptionType.cancel:
        return OdooNetworkException('Request cancelled', cause: e);
      default:
        return OdooNetworkException(e.message ?? 'Network error', cause: e);
    }
  }
}
