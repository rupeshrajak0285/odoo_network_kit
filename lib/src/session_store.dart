import 'odoo_session.dart';

/// Persist the session between app launches. Implement with
/// SharedPreferences / flutter_secure_storage / Hive in your app.
abstract class OdooSessionStore {
  Future<OdooSession?> read();
  Future<void> write(OdooSession session);
  Future<void> clear();
}

/// Default non-persistent store.
class InMemorySessionStore implements OdooSessionStore {
  OdooSession? _session;
  @override
  Future<OdooSession?> read() async => _session;
  @override
  Future<void> write(OdooSession session) async => _session = session;
  @override
  Future<void> clear() async => _session = null;
}
