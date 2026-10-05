/// Helpers for reading Odoo JSON — handles `false` for empty values,
/// `[id, name]` many2one pairs, dates, etc.
///
/// ```dart
/// final r = OdooRecord(json);
/// r.id;                       // int
/// r.str('name');              // '' if false
/// r.many2oneId('partner_id'); // int?
/// r.many2oneName('partner_id');
/// r.many2manyIds('tag_ids');  // List<int>
/// r.dateTime('date_order');   // DateTime? (UTC → local)
/// ```
extension type OdooRecord(Map<String, dynamic> json) {
  int get id => json['id'] as int;

  /// Raw value, or null when Odoo returns `false`.
  Object? value(String f) {
    final v = json[f];
    return v == false ? null : v;
  }

  String str(String f) => value(f)?.toString() ?? '';
  String? strOrNull(String f) => value(f)?.toString();
  int? intOrNull(String f) => (value(f) as num?)?.toInt();
  int integer(String f) => intOrNull(f) ?? 0;
  double number(String f) => (value(f) as num?)?.toDouble() ?? 0;
  bool boolean(String f) => json[f] == true;

  int? many2oneId(String f) {
    final v = value(f);
    if (v is List && v.isNotEmpty) return v[0] as int?;
    if (v is int) return v;
    return null;
  }

  String? many2oneName(String f) {
    final v = value(f);
    return (v is List && v.length > 1) ? v[1]?.toString() : null;
  }

  List<int> many2manyIds(String f) =>
      (value(f) as List?)?.cast<int>() ?? const [];

  /// Parses Odoo `YYYY-MM-DD` or `YYYY-MM-DD HH:MM:SS` (server time is UTC).
  DateTime? dateTime(String f, {bool toLocal = true}) {
    final v = strOrNull(f);
    if (v == null) return null;
    final dt =
        DateTime.tryParse(v.length > 10 ? '${v.replaceFirst(' ', 'T')}Z' : v);
    return toLocal && dt != null && v.length > 10 ? dt.toLocal() : dt;
  }
}

/// Format a [DateTime] for an Odoo datetime field (UTC, `YYYY-MM-DD HH:MM:SS`).
String odooDateTime(DateTime dt) =>
    dt.toUtc().toIso8601String().substring(0, 19).replaceFirst('T', ' ');

/// Format a [DateTime] for an Odoo date field (`YYYY-MM-DD`).
String odooDate(DateTime dt) => dt.toIso8601String().substring(0, 10);
