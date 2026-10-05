import 'dart:convert';

import 'package:odoo_network_kit/odoo_network_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists the Odoo session across app restarts.
/// In production prefer flutter_secure_storage — same 3 methods.
class PrefsSessionStore implements OdooSessionStore {
  static const _key = 'odoo_session';

  @override
  Future<OdooSession?> read() async {
    final p = await SharedPreferences.getInstance();
    final v = p.getString(_key);
    return v == null ? null : OdooSession.fromJson(jsonDecode(v));
  }

  @override
  Future<void> write(OdooSession session) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(session.toJson()));
  }

  @override
  Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_key);
  }
}
