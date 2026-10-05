import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:odoo_network_kit/odoo_network_kit.dart';
import 'package:test/test.dart';

class FakeAdapter implements HttpClientAdapter {
  final Map<String, Map<String, dynamic>> responses;
  FakeAdapter(this.responses);
  @override
  Future<ResponseBody> fetch(
          RequestOptions o, Stream<Uint8List>? _, Future<void>? __) async =>
      ResponseBody.fromString(jsonEncode(responses[o.path] ?? {}), 200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType]
          });
  @override
  void close({bool force = false}) {}
}

class Partner {
  final int id;
  final String name;
  final String? email;
  final int? countryId;
  final DateTime? created;
  Partner.fromJson(Map<String, dynamic> j)
      : id = OdooRecord(j).id,
        name = OdooRecord(j).str('name'),
        email = OdooRecord(j).strOrNull('email'),
        countryId = OdooRecord(j).many2oneId('country_id'),
        created = OdooRecord(j).dateTime('create_date');
}

class PartnerRepo extends OdooRepository<Partner> {
  const PartnerRepo({super.client})
      : super('res.partner',
            fields: const ['name', 'email', 'country_id', 'create_date'],
            fromJson: Partner.fromJson);
}

void main() {
  tearDown(Odoo.disposeAll);

  test('OdooConfig.fromMap', () {
    final c = OdooConfig.fromMap({
      'baseUrl': 'https://x.com',
      'database': 'db',
      'logLevel': 'none',
      'timeoutSeconds': 10,
      'context': {'lang': 'hi_IN'},
    });
    expect(c.database, 'db');
    expect(c.logLevel, OdooLogLevel.none);
    expect(c.receiveTimeout, const Duration(seconds: 10));
    expect(c.defaultContext['lang'], 'hi_IN');
  });

  test('Odoo singleton + named instances', () async {
    expect(() => Odoo.instance, throwsStateError);
    await Odoo.init(
        const OdooConfig(baseUrl: 'https://a', logLevel: OdooLogLevel.none));
    await Odoo.init(
        const OdooConfig(baseUrl: 'https://b', logLevel: OdooLogLevel.none),
        name: 'shop');
    expect(Odoo.instance.dio.options.baseUrl, 'https://a');
    expect(Odoo.named('shop').dio.options.baseUrl, 'https://b');
  });

  test('OdooRecord handles false, many2one and dates', () {
    final r = OdooRecord({
      'id': 1,
      'email': false,
      'country_id': [104, 'India'],
      'tag_ids': [1, 2],
      'amount': 12,
      'create_date': '2026-01-05 10:00:00',
      'date': '2026-01-05',
    });
    expect(r.strOrNull('email'), isNull);
    expect(r.str('email'), '');
    expect(r.many2oneId('country_id'), 104);
    expect(r.many2oneName('country_id'), 'India');
    expect(r.many2manyIds('tag_ids'), [1, 2]);
    expect(r.number('amount'), 12.0);
    expect(r.dateTime('create_date', toLocal: false),
        DateTime.utc(2026, 1, 5, 10));
    expect(r.dateTime('date'), DateTime(2026, 1, 5));
    expect(
        odooDateTime(DateTime.utc(2026, 1, 5, 10, 30)), '2026-01-05 10:30:00');
    expect(odooDate(DateTime(2026, 1, 5)), '2026-01-05');
  });

  test('OdooRepository maps typed models via global client', () async {
    final client = await Odoo.init(
        const OdooConfig(baseUrl: 'https://x', logLevel: OdooLogLevel.none));
    client.dio.httpClientAdapter = FakeAdapter({
      '/web/dataset/call_kw/res.partner/search_read': {
        'result': [
          {
            'id': 1,
            'name': 'Azure',
            'email': false,
            'country_id': [104, 'IN'],
            'create_date': '2026-01-01 00:00:00'
          }
        ]
      },
      '/web/dataset/call_kw/res.partner/search_count': {'result': 1},
      '/web/dataset/call_kw/res.partner/create': {'result': 9},
      '/web/dataset/call_kw/res.partner/action_archive': {'result': true},
    });
    const repo = PartnerRepo();
    final all = await repo.findAll();
    expect(all.single.name, 'Azure');
    expect(all.single.email, isNull);
    expect(all.single.countryId, 104);
    final page = await repo.findPage();
    expect(page.records.single, isA<Partner>());
    expect(page.total, 1);
    expect(await repo.create({'name': 'N'}), 9);
    expect(await repo.call('action_archive', ids: [1]), true);
  });
}
