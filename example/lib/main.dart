import 'package:flutter/material.dart';
import 'package:odoo_network_kit/odoo_network_kit.dart';

import 'session_store.dart';

/// Run with your server:
/// flutter run --dart-define=ODOO_URL=https://your-odoo.com --dart-define=ODOO_DB=yourdb
///
/// Without dart-defines it falls back to the public demo server.
const _url = String.fromEnvironment(
  'ODOO_URL',
  defaultValue: 'https://demo.odoo.com',
);
const _defaultDb = String.fromEnvironment('ODOO_DB', defaultValue: '');

final navKey = GlobalKey<NavigatorState>();
final logs = ValueNotifier<List<String>>([]);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Odoo.init(
    OdooConfig(
      baseUrl: _url,
      database: _defaultDb.isEmpty ? null : _defaultDb,
      logLevel: OdooLogLevel.body,
      logger: OdooLogger(
        sink: (m) {
          debugPrint(m);
          logs.value = [...logs.value.take(199), m];
        },
      ),
    ),
    sessionStore: PrefsSessionStore(),
    onSessionExpired: () =>
        navKey.currentState?.pushNamedAndRemoveUntil('/login', (_) => false),
  );
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: navKey,
    theme: ThemeData(
      colorSchemeSeed: const Color(0xFF714B67),
      useMaterial3: true,
    ),
    initialRoute: Odoo.instance.isLoggedIn ? '/home' : '/login',
    routes: {
      '/login': (_) => const LoginPage(),
      '/home': (_) => const HomePage(),
      '/logs': (_) => const LogsPage(),
    },
  );
}

// ----------------------------------------------------------------- login

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _db = TextEditingController(text: _defaultDb);
  final _user = TextEditingController();
  final _pass = TextEditingController();
  bool _useApiKey = false;
  bool _busy = false;
  String? _error;
  List<String> _databases = [];

  @override
  void initState() {
    super.initState();
    Odoo.instance
        .listDatabases()
        .then((d) {
          if (!mounted) return;
          setState(() => _databases = d);
          if (_db.text.isEmpty && d.length == 1) _db.text = d.first;
        })
        .catchError((_) {}); // list_db may be disabled
  }

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final odoo = Odoo.instance;
      if (_useApiKey) {
        await odoo.loginWithApiKey(
          _user.text.trim(),
          _pass.text,
          database: _db.text.trim(),
        );
      } else {
        await odoo.login(
          _user.text.trim(),
          _pass.text,
          database: _db.text.trim().isEmpty ? null : _db.text.trim(),
        );
      }
      if (mounted) Navigator.pushReplacementNamed(context, '/home');
    } on OdooException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Odoo Login'),
      actions: [
        IconButton(
          icon: const Icon(Icons.receipt_long),
          onPressed: () => Navigator.pushNamed(context, '/logs'),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(_url, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 16),
        if (_databases.length > 1)
          DropdownButtonFormField<String>(
            initialValue: _databases.contains(_db.text) ? _db.text : null,
            items: _databases
                .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                .toList(),
            onChanged: (v) => _db.text = v ?? '',
            decoration: const InputDecoration(labelText: 'Database'),
          )
        else
          TextField(
            controller: _db,
            decoration: const InputDecoration(labelText: 'Database (optional)'),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _user,
          decoration: const InputDecoration(labelText: 'Login / Email'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _pass,
          obscureText: true,
          decoration: InputDecoration(
            labelText: _useApiKey ? 'API Key' : 'Password',
          ),
          onSubmitted: (_) => _login(),
        ),
        SwitchListTile(
          title: const Text('Use API key'),
          value: _useApiKey,
          onChanged: (v) => setState(() => _useApiKey = v),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        FilledButton(
          onPressed: _busy ? null : _login,
          child: _busy
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Login'),
        ),
      ],
    ),
  );
}

// ------------------------------------------------------------------ home

class Partner {
  final int id;
  final String name;
  final String? email;
  final String? country;
  Partner.fromJson(Map<String, dynamic> j)
    : id = OdooRecord(j).id,
      name = OdooRecord(j).str('name'),
      email = OdooRecord(j).strOrNull('email'),
      country = OdooRecord(j).many2oneName('country_id');
}

class PartnerRepo extends OdooRepository<Partner> {
  const PartnerRepo()
    : super(
        'res.partner',
        fields: const ['name', 'email', 'country_id'],
        fromJson: Partner.fromJson,
        defaultOrder: 'name',
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _repo = const PartnerRepo();
  final _items = <Partner>[];
  int _total = 0;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
      if (!more) _items.clear();
    });
    try {
      final page = await _repo.findPage(
        domain: OdooDomain().where('is_company', '=', true).build(),
        offset: more ? _items.length : 0,
        limit: 30,
      );
      _items.addAll(page.records);
      _total = page.total;
    } on OdooException catch (e) {
      _error = e.message;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createDemo() async {
    try {
      final id = await _repo.create({
        'name': 'Test from Flutter ${DateTime.now().second}',
        'is_company': true,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Created partner #$id')));
      _load();
    } on OdooException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = Odoo.instance.session;
    return Scaffold(
      appBar: AppBar(
        title: Text('Companies ($_total)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long),
            onPressed: () => Navigator.pushNamed(context, '/logs'),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await Odoo.instance.logout();
              if (context.mounted) {
                Navigator.pushReplacementNamed(context, '/login');
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (s != null)
            ListTile(
              dense: true,
              leading: const Icon(Icons.person),
              title: Text('${s.username} (uid ${s.userId})'),
              subtitle: Text(
                '${s.database} · ${s.usesApiKey ? 'API key' : 'session'}',
              ),
            ),
          if (_error != null)
            MaterialBanner(
              content: Text(_error!),
              actions: [
                TextButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                itemCount: _items.length + 1,
                itemBuilder: (_, i) {
                  if (i == _items.length) {
                    if (_items.length >= _total) {
                      return const SizedBox(height: 80);
                    }
                    _load(more: true);
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }
                  final p = _items[i];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundImage: NetworkImage(
                        Odoo.instance.imageUrl('res.partner', p.id),
                        headers: Odoo.instance.sessionHeaders,
                      ),
                    ),
                    title: Text(p.name),
                    subtitle: Text(
                      [p.email, p.country].whereType<String>().join(' · '),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createDemo,
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ------------------------------------------------------------------ logs

class LogsPage extends StatelessWidget {
  const LogsPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Network logs'),
      actions: [
        IconButton(
          icon: const Icon(Icons.delete),
          onPressed: () => logs.value = [],
        ),
      ],
    ),
    body: ValueListenableBuilder(
      valueListenable: logs,
      builder: (_, list, child) => ListView.builder(
        reverse: true,
        itemCount: list.length,
        itemBuilder: (_, i) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: SelectableText(
            list[list.length - 1 - i],
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ),
      ),
    ),
  );
}
