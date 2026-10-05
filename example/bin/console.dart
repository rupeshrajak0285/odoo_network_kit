// ignore_for_file: avoid_print
// Quick test without a phone:
//   cd example
//   dart run bin/console.dart https://your-odoo.com yourdb admin admin
//   dart run bin/console.dart https://your-odoo.com yourdb bot@x.com API_KEY --api-key
import 'dart:io';

import 'package:odoo_network_kit/odoo_network_kit.dart';

Future<void> main(List<String> a) async {
  if (a.length < 4) {
    stderr.writeln(
      'usage: console.dart <url> <db> <login> <password|apikey> [--api-key]',
    );
    exit(64);
  }
  final odoo = OdooClient(
    OdooConfig(baseUrl: a[0], database: a[1], logLevel: OdooLogLevel.body),
  );
  try {
    print(await odoo.versionInfo());
    if (a.contains('--api-key')) {
      await odoo.loginWithApiKey(a[2], a[3]);
    } else {
      await odoo.login(a[2], a[3]);
    }
    final page = await odoo.searchReadPaginated(
      'res.partner',
      domain: OdooDomain().where('is_company', '=', true).build(),
      fields: ['name', 'email', 'country_id'],
      limit: 5,
    );
    print('total companies: ${page.total}');
    for (final r in page.records) {
      final rec = OdooRecord(r);
      print(
        '  ${rec.id}  ${rec.str('name')}  ${rec.many2oneName('country_id') ?? ''}',
      );
    }
    print(await odoo.nameSearch('res.country', name: 'ind', limit: 3));
    print(
      await odoo.readGroup(
        'res.partner',
        fields: ['id'],
        groupBy: ['country_id'],
        limit: 3,
      ),
    );
  } on OdooException catch (e) {
    stderr.writeln('FAILED: $e');
    exit(1);
  } finally {
    odoo.dispose();
  }
}
