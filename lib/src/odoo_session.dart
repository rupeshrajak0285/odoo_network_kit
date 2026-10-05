/// Authenticated Odoo session.
class OdooSession {
  final String sessionId;
  final int userId;
  final int? partnerId;
  final int? companyId;
  final List<int> allowedCompanyIds;
  final String database;
  final String username;
  final String? userName;
  final String? serverVersion;
  final Map<String, dynamic> userContext;
  final bool isAdmin;

  /// Set when authenticated with an API key (Odoo 14+). In that mode calls
  /// go through `/jsonrpc` `execute_kw` instead of the web session.
  final String? apiKey;

  const OdooSession({
    required this.sessionId,
    required this.userId,
    required this.database,
    required this.username,
    this.partnerId,
    this.companyId,
    this.allowedCompanyIds = const [],
    this.userName,
    this.serverVersion,
    this.userContext = const {},
    this.isAdmin = false,
    this.apiKey,
  });

  /// Parses `/web/session/authenticate` result.
  factory OdooSession.fromAuthResult(String sessionId, Map<String, dynamic> r) {
    final companies = r['user_companies'];
    List<int> allowed = const [];
    int? companyId = r['company_id'] is int ? r['company_id'] as int : null;
    if (companies is Map) {
      final cur = companies['current_company'];
      companyId ??= cur is List ? cur.first as int : cur as int?;
      final list = companies['allowed_companies'];
      if (list is Map) {
        allowed = list.keys.map((k) => int.parse(k.toString())).toList();
      } else if (list is List) {
        allowed = list.map((e) => (e is List ? e.first : e) as int).toList();
      }
    }
    return OdooSession(
      sessionId: sessionId,
      userId: r['uid'] as int,
      partnerId: r['partner_id'] as int?,
      companyId: companyId,
      allowedCompanyIds: allowed,
      database: (r['db'] ?? '').toString(),
      username: (r['username'] ?? '').toString(),
      userName: r['name']?.toString(),
      serverVersion: r['server_version']?.toString(),
      userContext:
          (r['user_context'] as Map?)?.cast<String, dynamic>() ?? const {},
      isAdmin: r['is_admin'] == true,
    );
  }

  bool get usesApiKey => apiKey != null;

  OdooSession copyWith({String? sessionId}) => OdooSession(
        sessionId: sessionId ?? this.sessionId,
        apiKey: apiKey,
        userId: userId,
        partnerId: partnerId,
        companyId: companyId,
        allowedCompanyIds: allowedCompanyIds,
        database: database,
        username: username,
        userName: userName,
        serverVersion: serverVersion,
        userContext: userContext,
        isAdmin: isAdmin,
      );

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'userId': userId,
        'partnerId': partnerId,
        'companyId': companyId,
        'allowedCompanyIds': allowedCompanyIds,
        'database': database,
        'username': username,
        'userName': userName,
        'serverVersion': serverVersion,
        'userContext': userContext,
        'isAdmin': isAdmin,
        'apiKey': apiKey,
      };

  factory OdooSession.fromJson(Map<String, dynamic> j) => OdooSession(
        sessionId: j['sessionId'] as String,
        userId: j['userId'] as int,
        partnerId: j['partnerId'] as int?,
        companyId: j['companyId'] as int?,
        allowedCompanyIds:
            (j['allowedCompanyIds'] as List? ?? []).cast<int>().toList(),
        database: j['database'] as String,
        username: j['username'] as String,
        userName: j['userName'] as String?,
        serverVersion: j['serverVersion'] as String?,
        userContext:
            (j['userContext'] as Map?)?.cast<String, dynamic>() ?? const {},
        isAdmin: j['isAdmin'] == true,
        apiKey: j['apiKey'] as String?,
      );
}
