import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:remai/api/token_storage.dart';
import 'package:remai/app.dart';
import 'package:remai/state/session.dart';

// Synthetic credentials only.
const validToken = 'valid-test-token';

/// Minimal in-memory remai backend for widget tests (subset of docs/api/openapi.yaml).
class FakeBackend {
  final pages = <String, Map<String, dynamic>>{};
  final blocks = <String, List<Map<String, dynamic>>>{};
  final trash = <Map<String, dynamic>>[];
  final requests = <http.Request>[];

  /// When set, every request fails like a dropped connection.
  bool offline = false;

  /// When set, the session token is rejected (expired) and every authenticated call returns 401.
  bool revoked = false;
  int _seq = 0;

  void addPage(String id, {String title = '', String icon = '', String? parentId, List<Map<String, dynamic>>? content}) {
    final ts = '2026-01-01T00:00:${(_seq++).toString().padLeft(2, '0')}.000Z';
    pages[id] = {'id': id, 'parentId': parentId, 'title': title, 'icon': icon, 'createdAt': ts, 'updatedAt': ts};
    blocks[id] = content ?? [];
  }

  List<http.Request> requestsTo(String method, String pathPrefix) =>
      requests.where((r) => r.method == method && r.url.path.startsWith(pathPrefix)).toList();

  late final http.Client client = MockClient(_handle);

  http.Response _json(int status, Object body) =>
      http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json'});

  http.Response _error(int status, String code) => _json(status, {
        'error': {'code': code, 'message': code},
      });

  Future<http.Response> _handle(http.Request req) async {
    requests.add(req);
    if (offline) throw http.ClientException('offline');
    final path = req.url.path;
    final body = req.bodyBytes.isEmpty ? null : jsonDecode(utf8.decode(req.bodyBytes)) as Map<String, dynamic>;

    if (path == '/api/v1/auth/login') {
      if (body?['password'] == 'correct-horse') {
        return _json(200, {'token': validToken, 'user': _user});
      }
      return _error(401, 'invalid_credentials');
    }
    if (revoked || req.headers['Authorization'] != 'Bearer $validToken') return _error(401, 'unauthorized');

    if (path == '/api/v1/auth/me') return _json(200, _user);
    if (path == '/api/v1/pages' && req.method == 'GET') return _json(200, {'pages': pages.values.toList()});
    if (path == '/api/v1/pages' && req.method == 'POST') {
      final id = 'new-${_seq++}';
      addPage(id, parentId: body?['parentId'] as String?, title: body?['title'] as String? ?? '');
      return _json(201, pages[id]!);
    }
    if (path == '/api/v1/trash' && req.method == 'GET') return _json(200, {'pages': trash});
    if (path == '/api/v1/search') {
      final q = (req.url.queryParameters['q'] ?? '').trim().toLowerCase();
      return _json(200, {
        'results': [
          for (final p in pages.values)
            if ((p['title'] as String).toLowerCase().contains(q))
              {'id': p['id'], 'parentId': p['parentId'], 'title': p['title'], 'icon': p['icon'], 'snippet': p['title']},
        ],
      });
    }

    final segs = req.url.pathSegments; // api, v1, pages|trash, id, ...
    if (segs.length >= 4 && segs[2] == 'pages') {
      final id = segs[3];
      final page = pages[id];
      if (page == null) return _error(404, 'not_found');
      if (segs.length == 5 && segs[4] == 'blocks' && req.method == 'PUT') {
        blocks[id] = (body!['blocks'] as List<dynamic>).cast<Map<String, dynamic>>();
        return _json(200, {'blocks': blocks[id]!, 'updatedAt': 'now'});
      }
      switch (req.method) {
        case 'GET':
          return _json(200, {...page, 'blocks': blocks[id]!});
        case 'PATCH':
          page.addAll(body!);
          return _json(200, page);
        case 'DELETE':
          pages.remove(id);
          trash.add({'id': id, 'title': page['title'], 'icon': page['icon'], 'trashedAt': '2026-01-01T00:00:00Z'});
          return http.Response('', 204);
      }
    }
    if (segs.length >= 4 && segs[2] == 'trash') {
      final id = segs[3];
      final i = trash.indexWhere((p) => p['id'] == id);
      if (i == -1) return _error(404, 'not_found');
      if (req.method == 'DELETE') {
        trash.removeAt(i);
        return http.Response('', 204);
      }
      if (segs.length == 5 && segs[4] == 'restore') {
        final t = trash.removeAt(i);
        addPage(id, title: t['title'] as String, icon: t['icon'] as String);
        return _json(200, pages[id]!);
      }
    }
    return _error(404, 'not_found');
  }

  static const _user = {'id': 'u1', 'email': 'ada@example.com', 'name': 'Ada', 'createdAt': '2026-01-01T00:00:00Z'};
}

/// Pumps the whole app against [backend] with [storage] as the token store.
Future<SessionState> pumpApp(WidgetTester tester, FakeBackend backend, TokenStorage storage) async {
  final session = SessionState(
    storage: storage,
    httpClient: backend.client,
    baseUrl: 'http://remai.test',
    requestTimeout: null, // no timers outliving a test
  );
  await tester.pumpWidget(RemaiApp(session: session));
  await tester.pumpAndSettle();
  return session;
}

/// The block TextField for [blockId].
Finder blockField(String blockId) => find.byKey(ValueKey('block-field-$blockId'));

/// The current text of a block's field (including the sentinel).
String fieldText(WidgetTester tester, String blockId) => tester.widget<TextField>(blockField(blockId)).controller!.text;

/// Whether a block's field has keyboard focus.
bool fieldFocused(WidgetTester tester, String blockId) => tester.widget<TextField>(blockField(blockId)).focusNode!.hasFocus;

/// In-memory storage for tests.
class MemoryTokenStorage implements TokenStorage {
  MemoryTokenStorage([this.token]);

  String? token;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String token) async => this.token = token;

  @override
  Future<void> delete() async => token = null;
}
