import 'odoo_client.dart';
import 'odoo_config.dart';
import 'session_store.dart';

/// Global access point so any file in any project can call
/// `Odoo.instance.searchRead(...)` without passing the client around.
///
/// ```dart
/// // main.dart (once)
/// await Odoo.init(OdooConfig.fromEnvironment(), sessionStore: SecureStore());
///
/// // anywhere
/// final orders = await Odoo.instance.searchRead('sale.order');
/// ```
///
/// Multiple servers (e.g. ERP + eCommerce): `Odoo.init(cfg, name: 'shop')`
/// then `Odoo.named('shop')`.
class Odoo {
  Odoo._();

  static final Map<String, OdooClient> _clients = {};
  static const _defaultName = 'default';

  static Future<OdooClient> init(
    OdooConfig config, {
    String name = _defaultName,
    OdooSessionStore? sessionStore,
    void Function()? onSessionExpired,
    bool restoreSession = true,
  }) async {
    _clients[name]?.dispose();
    final client = OdooClient(config,
        sessionStore: sessionStore, onSessionExpired: onSessionExpired);
    _clients[name] = client;
    if (restoreSession) await client.restoreSession();
    return client;
  }

  static OdooClient get instance => named(_defaultName);

  static OdooClient named(String name) {
    final c = _clients[name];
    if (c == null) {
      throw StateError('Odoo client "$name" not initialised. '
          'Call Odoo.init(config${name == _defaultName ? '' : ', name: "$name"'}) first.');
    }
    return c;
  }

  static bool get isInitialized => _clients.containsKey(_defaultName);

  /// Swap server at runtime (e.g. user types a URL on login screen).
  static Future<OdooClient> reconfigure(OdooConfig config,
          {String name = _defaultName, OdooSessionStore? sessionStore}) =>
      init(config,
          name: name, sessionStore: sessionStore, restoreSession: false);

  static void disposeAll() {
    for (final c in _clients.values) {
      c.dispose();
    }
    _clients.clear();
  }
}
