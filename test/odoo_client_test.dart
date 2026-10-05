import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:odoo_network_kit/odoo_network_kit.dart';
import 'package:test/test.dart';

/// Fake server: maps path -> (json body, headers).
class FakeAdapter implements HttpClientAdapter {
  final Map<String, Map<String, dynamic>> responses;
  final Map<String, List<String>> extraHeaders;
  final requests = <RequestOptions>[];
  FakeAdapter(this.responses, {this.extraHeaders = const {}});

  @override
  Future<ResponseBody> fetch(
      RequestOptions o, Stream<Uint8List>? _, Future<void>? __) async {
    requests.add(o);
    final body = responses[o.path] ??
        {
          'error': {'code': 404, 'message': 'nf'}
        };
    return ResponseBody.fromString(jsonEncode(body), 200, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
      ...extraHeaders,
    });
  }

  @override
  void close({bool force = false}) {}
}

OdooClient makeClient(FakeAdapter a) {
  final c = OdooClient(const OdooConfig(
      baseUrl: 'https://odoo.test',
      database: 'db',
      logLevel: OdooLogLevel.none));
  c.dio.httpClientAdapter = a;
  return c;
}

void main() {
  test('login stores session from cookie', () async {
    final a = FakeAdapter({
      '/web/session/authenticate': {
        'result': {
          'uid': 2,
          'db': 'db',
          'username': 'admin',
          'user_context': {'lang': 'en_US'}
        }
      },
    }, extraHeaders: {
      'set-cookie': ['session_id=abc123; Path=/; HttpOnly']
    });
    final c = makeClient(a);
    final s = await c.login('admin', 'admin');
    expect(s.sessionId, 'abc123');
    expect(s.userId, 2);
    expect(c.isLoggedIn, isTrue);
  });

  test('wrong password throws OdooAuthException', () async {
    final c = makeClient(FakeAdapter({
      '/web/session/authenticate': {
        'error': {
          'code': 200,
          'message': 'Odoo Server Error',
          'data': {
            'name': 'odoo.exceptions.AccessDenied',
            'message': 'Access Denied'
          }
        }
      },
    }));
    expect(c.login('x', 'y'), throwsA(isA<OdooAuthException>()));
  });

  test('searchRead sends cookie, context and parses result', () async {
    final a = FakeAdapter({
      '/web/session/authenticate': {
        'result': {
          'uid': 2,
          'user_context': {'lang': 'en_US'}
        }
      },
      '/web/dataset/call_kw/res.partner/search_read': {
        'result': [
          {'id': 1, 'name': 'Azure'}
        ]
      },
    }, extraHeaders: {
      'set-cookie': ['session_id=s1']
    });
    final c = makeClient(a);
    await c.login('a', 'b');
    final r = await c.searchRead('res.partner', fields: ['name'], limit: 1);
    expect(r.single['name'], 'Azure');
    final req = a.requests.last;
    expect(req.headers['Cookie'], 'session_id=s1');
    expect(req.data['params']['kwargs']['context']['lang'], 'en_US');
  });

  test('session expired clears session and fires callback', () async {
    final a = FakeAdapter({
      '/web/session/authenticate': {
        'result': {'uid': 2}
      },
      '/web/dataset/call_kw/res.partner/search_read': {
        'error': {
          'code': 100,
          'message': 'Odoo Session Expired',
          'data': {
            'name': 'odoo.http.SessionExpiredException',
            'message': 'Session expired'
          }
        }
      },
    }, extraHeaders: {
      'set-cookie': ['session_id=s1']
    });
    final c = makeClient(a);
    var fired = false;
    c.onSessionExpired = () => fired = true;
    await c.login('a', 'b');
    await expectLater(c.searchRead('res.partner'),
        throwsA(isA<OdooSessionExpiredException>()));
    expect(fired, isTrue);
    expect(c.isLoggedIn, isFalse);
  });

  test('ValidationError maps to OdooServerException', () async {
    final c = makeClient(FakeAdapter({
      '/web/dataset/call_kw/res.partner/create': {
        'error': {
          'code': 200,
          'message': 'x',
          'data': {
            'name': 'odoo.exceptions.ValidationError',
            'message': 'Email invalid'
          }
        }
      },
    }));
    await expectLater(
        c.create('res.partner', {'name': 'X'}),
        throwsA(isA<OdooServerException>()
            .having((e) => e.isValidationError, 'validation', true)
            .having((e) => e.message, 'msg', 'Email invalid')));
  });

  test('logger masks passwords', () {
    final out = OdooLogger().formatBody({
      'params': {'login': 'a', 'password': 'secret'}
    });
    expect(out, isNot(contains('secret')));
  });

  test('domain builder', () {
    expect(OdooDomain().or().where('a', '=', 1).where('b', '=', 2).build(), [
      '|',
      ['a', '=', 1],
      ['b', '=', 2]
    ]);
  });

  test('searchReadPaginated combines count', () async {
    final c = makeClient(FakeAdapter({
      '/web/dataset/call_kw/res.partner/search_read': {
        'result': [
          {'id': 1},
          {'id': 2}
        ]
      },
      '/web/dataset/call_kw/res.partner/search_count': {'result': 10},
    }));
    final page = await c.searchReadPaginated('res.partner', limit: 2);
    expect(page.total, 10);
    expect(page.hasMore, isTrue);
    expect(page.nextOffset, 2);
  });

  test('nameSearch returns id/name tuples', () async {
    final c = makeClient(FakeAdapter({
      '/web/dataset/call_kw/res.partner/name_search': {
        'result': [
          [1, 'Azure'],
          [2, 'Deco']
        ]
      },
    }));
    final r = await c.nameSearch('res.partner', name: 'a');
    expect(r.first, (1, 'Azure'));
  });

  test('readGroup and defaultGet', () async {
    final c = makeClient(FakeAdapter({
      '/web/dataset/call_kw/sale.order/read_group': {
        'result': [
          {'state': 'sale', 'state_count': 3}
        ]
      },
      '/web/dataset/call_kw/sale.order/default_get': {
        'result': {'state': 'draft'}
      },
    }));
    final g = await c.readGroup('sale.order', groupBy: ['state']);
    expect(g.single['state_count'], 3);
    expect((await c.defaultGet('sale.order', ['state']))['state'], 'draft');
  });

  test('upload attachment encodes base64 and readBinaryField decodes',
      () async {
    final a = FakeAdapter({
      '/web/dataset/call_kw/ir.attachment/create': {'result': 77},
      '/web/dataset/call_kw/ir.attachment/read': {
        'result': [
          {
            'id': 77,
            'datas': base64Encode([1, 2, 3])
          }
        ]
      },
    });
    final c = makeClient(a);
    final id = await c.uploadAttachment(
        fileName: 'a.bin', bytes: Uint8List.fromList([1, 2, 3]));
    expect(id, 77);
    expect(a.requests.last.data['params']['args'][0]['datas'], 'AQID');
    expect(await c.readBinaryField('ir.attachment', 77, 'datas'), [1, 2, 3]);
  });

  test('imageUrl and sessionHeaders', () async {
    final c = makeClient(FakeAdapter({
      '/web/session/authenticate': {
        'result': {'uid': 2}
      },
    }, extraHeaders: {
      'set-cookie': ['session_id=zz']
    }));
    await c.login('a', 'b');
    expect(c.imageUrl('res.partner', 5),
        'https://odoo.test/web/image?model=res.partner&id=5&field=image_128');
    expect(c.sessionHeaders, {'Cookie': 'session_id=zz'});
  });

  test('API key auth routes callKw through /jsonrpc execute_kw', () async {
    final a = FakeAdapter({
      '/jsonrpc': {'result': 7},
    });
    final c = makeClient(a);
    final s = await c.loginWithApiKey('bot@x.com', 'KEY123');
    expect(s.userId, 7);
    expect(s.usesApiKey, isTrue);
    a.responses['/jsonrpc'] = {
      'result': [
        {'id': 1, 'name': 'A'}
      ]
    };
    final r = await c.searchRead('res.partner', fields: ['name']);
    expect(r.single['name'], 'A');
    final p = a.requests.last.data['params'];
    expect(p['service'], 'object');
    expect(p['method'], 'execute_kw');
    expect(p['args'].sublist(0, 5),
        ['db', 7, 'KEY123', 'res.partner', 'search_read']);
    expect(a.requests.last.headers.containsKey('Cookie'), isFalse);
  });

  test('invalid API key throws OdooAuthException', () async {
    final c = makeClient(FakeAdapter({
      '/jsonrpc': {'result': false}
    }));
    expect(c.loginWithApiKey('a', 'bad'), throwsA(isA<OdooAuthException>()));
  });

  test('session json roundtrip keeps apiKey', () {
    final s = OdooSession.fromJson(const OdooSession(
            sessionId: '', userId: 1, database: 'd', username: 'u', apiKey: 'k')
        .toJson());
    expect(s.apiKey, 'k');
  });
}
