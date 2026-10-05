# odoo_network_kit

A reusable network layer for **Odoo** (v14–v18+) for Dart & Flutter apps.

- 🔐 Login with password **or API key** (`loginWithApiKey`), logout, session restore (pluggable storage)
- 🍪 Automatic `session_id` cookie handling (works on mobile, no cookie jar needed)
- 📦 ORM helpers: `searchRead`, `searchReadPaginated`, `read`, `search`, `searchCount`, `create`, `write`, `unlink`, `copy`, `nameSearch`, `nameCreate`, `readGroup`, `defaultGet`, `fieldsGet`, `checkAccess`, `callKw`
- 📎 Attachments & binaries: `uploadAttachment`, `readBinaryField`, `downloadBytes`, `imageUrl` + `sessionHeaders` for `Image.network`
- 🛠️ `rpc()` for any custom `type='json'` controller
- 🧾 Pretty logs (none / basic / body) with password masking and a custom sink
- 🔁 Automatic retry on timeouts / connection errors / 5xx
- 🚨 Typed exceptions: `OdooAuthException`, `OdooSessionExpiredException`, `OdooServerException` (ValidationError, UserError, AccessError…), `OdooNetworkException`, `OdooHttpException`
- 📡 `sessionStream` + `onSessionExpired` callback for auto-logout
- 🧩 `Odoo.init()` global instance, `OdooConfig.fromEnvironment()/fromMap()`, typed `OdooRepository<T>`, `OdooRecord` JSON helpers (handles `false`, `[id, name]`, dates)

## Use in any Flutter project (3 steps)

Nothing project-specific lives in this package — only the config changes.

**1. Config per environment** — `--dart-define`, never hard-coded:

```bash
flutter run --dart-define=ODOO_URL=https://erp.client.com --dart-define=ODOO_DB=prod --dart-define=ODOO_LOG_LEVEL=body
```

**2. Initialise once** in `main.dart`:

```dart
await Odoo.init(
  OdooConfig.fromEnvironment(logger: OdooLogger(sink: debugPrint)),
  sessionStore: SecureSessionStore(),           // see below
  onSessionExpired: () => router.go('/login'),
);
```

Or from a JSON asset / remote config: `OdooConfig.fromMap(jsonDecode(asset))`.

**3. Define your models + repositories** — CRUD, paging and typing come free:

```dart
class SaleOrder {
  final int id; final String name; final double total; final int? partnerId; final DateTime? date;
  SaleOrder.fromJson(Map<String, dynamic> j)
      : id = OdooRecord(j).id,
        name = OdooRecord(j).str('name'),
        total = OdooRecord(j).number('amount_total'),
        partnerId = OdooRecord(j).many2oneId('partner_id'),
        date = OdooRecord(j).dateTime('date_order');
}

class SaleOrderRepo extends OdooRepository<SaleOrder> {
  const SaleOrderRepo()
      : super('sale.order',
            fields: const ['name', 'amount_total', 'partner_id', 'date_order'],
            fromJson: SaleOrder.fromJson, defaultOrder: 'date_order desc');
}

// anywhere in the app
final repo = const SaleOrderRepo();
final page = await repo.findPage(domain: OdooDomain().where('state', '=', 'sale').build());
await repo.call('action_confirm', ids: [page.records.first.id]);
```

`Odoo.instance` is available everywhere; multiple servers via `Odoo.init(cfg, name: 'shop')` / `Odoo.named('shop')`.

## Install

```yaml
dependencies:
  odoo_network_kit: ^0.1.0
```

## Usage

```dart
final odoo = OdooClient(
  OdooConfig(
    baseUrl: 'https://erp.mycompany.com',
    database: 'prod',
    logLevel: kDebugMode ? OdooLogLevel.body : OdooLogLevel.none,
    logger: OdooLogger(sink: debugPrint),
    defaultContext: {'lang': 'en_US'},
  ),
  sessionStore: MySecureSessionStore(),
  onSessionExpired: () => navigatorKey.currentState?.pushReplacementNamed('/login'),
);

await odoo.login('user@x.com', 'password');

final orders = await odoo.searchRead(
  'sale.order',
  domain: OdooDomain().where('state', '=', 'sale').build(),
  fields: ['name', 'amount_total'],
  limit: 20,
  order: 'date_order desc',
);
```

### API key auth (recommended for production / integrations)

```dart
// Odoo: Settings → My Profile → Account Security → New API Key
await odoo.loginWithApiKey('bot@mycompany.com', apiKeyFromEnv);
// All ORM calls now use /jsonrpc execute_kw with the key.
```

Keep per-project values (URL, DB, API key) out of code — e.g. `--dart-define`
or a `.env` — so the same package works unchanged across projects.

### Persist session (Flutter)

```dart
class MySecureSessionStore implements OdooSessionStore {
  final _s = const FlutterSecureStorage();
  @override
  Future<OdooSession?> read() async {
    final v = await _s.read(key: 'odoo_session');
    return v == null ? null : OdooSession.fromJson(jsonDecode(v));
  }
  @override
  Future<void> write(OdooSession s) => _s.write(key: 'odoo_session', value: jsonEncode(s.toJson()));
  @override
  Future<void> clear() => _s.delete(key: 'odoo_session');
}
```

### Paging / dropdowns / dashboards

```dart
final page = await odoo.searchReadPaginated('sale.order', limit: 40, offset: 0);
if (page.hasMore) loadMore(page.nextOffset);

final options = await odoo.nameSearch('res.partner', name: 'azu'); // [(id, name)]
final byState = await odoo.readGroup('sale.order', fields: ['amount_total'], groupBy: ['state']);
```

### Images & files

```dart
Image.network(odoo.imageUrl('res.partner', id, field: 'image_256'), headers: odoo.sessionHeaders);
final pdf = await odoo.downloadBytes('/report/pdf/sale.report_saleorder/$orderId');
await odoo.uploadAttachment(fileName: 'photo.jpg', bytes: bytes, resModel: 'sale.order', resId: orderId);
```

### Error handling

```dart
try {
  await odoo.create('res.partner', {'name': ''});
} on OdooServerException catch (e) {
  if (e.isValidationError) showSnack(e.message);
} on OdooNetworkException {
  showSnack('Check your internet connection');
}
```

### Extending

`odoo.dio` is exposed — add your own interceptors (auth headers, Sentry, caching).
