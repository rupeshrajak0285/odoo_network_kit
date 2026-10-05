import 'odoo.dart';
import 'odoo_client.dart';
import 'odoo_page.dart';

/// Typed data-access layer for one Odoo model. Each project only defines
/// its model classes + `fromJson`; CRUD comes for free.
///
/// ```dart
/// class Partner {
///   final int id; final String name; final String? email;
///   Partner.fromJson(Map<String, dynamic> j)
///     : id = j['id'], name = j['name'], email = OdooRecord(j).strOrNull('email');
/// }
///
/// class PartnerRepo extends OdooRepository<Partner> {
///   PartnerRepo() : super('res.partner', fields: ['name', 'email'], fromJson: Partner.fromJson);
/// }
///
/// final partners = await PartnerRepo().findAll(domain: [['is_company', '=', true]]);
/// ```
class OdooRepository<T> {
  final String model;
  final List<String> fields;
  final T Function(Map<String, dynamic> json) fromJson;
  final String? defaultOrder;
  final OdooClient? _client;

  const OdooRepository(
    this.model, {
    required this.fields,
    required this.fromJson,
    this.defaultOrder,
    OdooClient? client,
  }) : _client = client;

  /// Explicit client, else the global [Odoo.instance].
  OdooClient get client => _client ?? Odoo.instance;

  Future<List<T>> findAll({
    List<dynamic> domain = const [],
    int? limit,
    int offset = 0,
    String? order,
    Map<String, dynamic>? context,
  }) async {
    final rows = await client.searchRead(model,
        domain: domain,
        fields: fields,
        limit: limit,
        offset: offset,
        order: order ?? defaultOrder,
        context: context);
    return rows.map(fromJson).toList();
  }

  Future<OdooPage<T>> findPage({
    List<dynamic> domain = const [],
    int limit = 40,
    int offset = 0,
    String? order,
  }) async {
    final p = await client.searchReadPaginated(model,
        domain: domain,
        fields: fields,
        limit: limit,
        offset: offset,
        order: order ?? defaultOrder);
    return OdooPage(
        records: p.records.map(fromJson).toList(),
        total: p.total,
        offset: p.offset,
        limit: p.limit);
  }

  Future<T?> findById(int id) async {
    final rows = await client.read(model, [id], fields: fields);
    return rows.isEmpty ? null : fromJson(rows.first);
  }

  Future<T?> findOne(List<dynamic> domain) async {
    final rows = await findAll(domain: domain, limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> count([List<dynamic> domain = const []]) =>
      client.searchCount(model, domain: domain);

  Future<int> create(Map<String, dynamic> values) =>
      client.create(model, values);

  Future<bool> update(int id, Map<String, dynamic> values) =>
      client.write(model, [id], values);

  Future<bool> updateMany(List<int> ids, Map<String, dynamic> values) =>
      client.write(model, ids, values);

  Future<bool> delete(int id) => client.unlink(model, [id]);

  /// Call any method on records of this model, e.g. `action_confirm`.
  Future<dynamic> call(String method,
          {List<int> ids = const [],
          List<dynamic> args = const [],
          Map<String, dynamic> kwargs = const {}}) =>
      client.callKw(model, method,
          args: [if (ids.isNotEmpty) ids, ...args], kwargs: kwargs);
}
