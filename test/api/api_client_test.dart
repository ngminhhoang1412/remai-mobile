import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:remai/api/api_client.dart';
import 'package:remai/models/models.dart';

// Synthetic test values only.
const testToken = 'test-token';
final testPassword = 'p' * 10;

class _Setup {
  _Setup(Future<http.Response> Function(http.Request req) respond, {String? token = testToken}) {
    api = ApiClient(
      baseUrl: 'http://10.0.2.2:8080/',
      httpClient: MockClient((req) {
        calls.add(req);
        return respond(req);
      }),
      getToken: () => token,
      onUnauthorized: unauthorized.add,
      timeout: null,
    );
  }

  late final ApiClient api;
  final calls = <http.Request>[];
  final unauthorized = <String?>[];
}

http.Response json(int status, Object? body) =>
    http.Response.bytes(body == null ? const [] : utf8.encode(jsonEncode(body)), status,
        headers: {'content-type': 'application/json'});

Future<http.Response> Function(http.Request) reply(http.Response res) => (_) async => res;

TypeMatcher<ApiException> apiError(int status, String code) =>
    isA<ApiException>().having((e) => e.status, 'status', status).having((e) => e.code, 'code', code);

void main() {
  group('API client', () {
    test('authenticated requests send the bearer token to REMAI_API_URL + /api/v1', () async {
      final s = _Setup(reply(json(200, {'pages': []})));
      expect(await s.api.listPages(), isEmpty);
      expect(s.calls.single.url.toString(), 'http://10.0.2.2:8080/api/v1/pages');
      expect(s.calls.single.headers['Authorization'], 'Bearer $testToken');
    });

    test('login sends no bearer token and a JSON body', () async {
      final s = _Setup(reply(json(200, {
        'token': 't',
        'user': {'id': 'u', 'email': 'ada@example.com', 'name': 'Ada', 'createdAt': 'now'},
      })));
      final res = await s.api.login('ada@example.com', testPassword);
      expect(res.user.name, 'Ada');
      final req = s.calls.single;
      expect(req.url.toString(), 'http://10.0.2.2:8080/api/v1/auth/login');
      expect(req.method, 'POST');
      expect(req.headers.containsKey('Authorization'), isFalse);
      expect(req.headers['Content-Type'], startsWith('application/json'));
      expect(jsonDecode(req.body), {'email': 'ada@example.com', 'password': testPassword});
    });

    test('error envelope is parsed into ApiException code and message', () async {
      final s = _Setup(reply(json(400, {
        'error': {'code': 'invalid_parent', 'message': 'parentId is not a live page'},
      })));
      await expectLater(
        s.api.createPage(parentId: 'x'),
        throwsA(apiError(400, 'invalid_parent').having((e) => e.message, 'message', 'parentId is not a live page')),
      );
    });

    test('a non-JSON error body still yields an ApiException', () async {
      final s = _Setup(reply(http.Response('<html>Bad gateway</html>', 502)));
      await expectLater(s.api.listTrash(), throwsA(apiError(502, 'http_error')));
    });

    test('a platform 413 without the envelope is reported as too large', () async {
      final s = _Setup(reply(http.Response('{"message":"Request Entity Too Large"}', 413)));
      await expectLater(
        s.api.saveBlocks('p1', const []),
        throwsA(apiError(413, 'http_error').having((e) => e.message, 'message', contains('too large'))),
      );
    });

    test('429 is "slow down" whatever the body (API Gateway sends no envelope)', () async {
      for (final body in ['{"message":"Too Many Requests"}', '', 'not json']) {
        final s = _Setup(reply(http.Response(body, 429)));
        await expectLater(s.api.listPages(), throwsA(apiError(429, 'rate_limited')));
        expect(s.unauthorized, isEmpty);
      }
      // Even a 429 that happens to carry an envelope is treated the same way.
      final s = _Setup(reply(json(429, {
        'error': {'code': 'unauthorized', 'message': 'x'},
      })));
      await expectLater(s.api.me(), throwsA(apiError(429, 'rate_limited')));
      expect(s.unauthorized, isEmpty);
      expect(isRetryableSaveError(const ApiException(429, 'rate_limited', '')), isTrue);
    });

    test('Token rejected: any API call returning 401 triggers the sign-out callback', () async {
      final s = _Setup(reply(json(401, {
        'error': {'code': 'unauthorized', 'message': 'invalid token'},
      })));
      await expectLater(s.api.getPage('p1'), throwsA(apiError(401, 'unauthorized')));
      expect(s.unauthorized, [testToken]);
    });

    test('Wrong credentials on login is an error, not a session expiry', () async {
      final s = _Setup(
        reply(json(401, {
          'error': {'code': 'invalid_credentials', 'message': 'Invalid email or password.'},
        })),
        token: null,
      );
      await expectLater(s.api.login('a@b.co', testPassword), throwsA(apiError(401, 'invalid_credentials')));
      expect(s.unauthorized, isEmpty);
    });

    test('network failure becomes ApiException status 0 without signing out', () async {
      final s = _Setup((_) async => throw http.ClientException('Connection refused'));
      await expectLater(s.api.me(), throwsA(apiError(0, 'network_error')));
      expect(s.unauthorized, isEmpty);
    });

    test('Sign out: with no stored token, authenticated calls fail locally without a request', () async {
      final s = _Setup(reply(json(200, {'pages': []})), token: null);
      await expectLater(s.api.listPages(), throwsA(apiError(401, 'unauthorized')));
      expect(s.calls, isEmpty);
      expect(s.unauthorized, isEmpty);
    });

    test('204 responses complete without a body', () async {
      final s = _Setup(reply(http.Response('', 204)));
      await s.api.deleteForever('p1');
      expect(s.calls.single.url.toString(), 'http://10.0.2.2:8080/api/v1/trash/p1');
      expect(s.calls.single.method, 'DELETE');
    });

    test('saveBlocks PUTs the whole ordered list with only BlockInput fields', () async {
      final s = _Setup(reply(json(200, {'blocks': [], 'updatedAt': 'now'})));
      const blocks = [
        Block(id: 'b1', type: BlockType.todo, text: 'Ship', checked: true),
        Block(id: 'b2', type: BlockType.paragraph, text: 'Notes · ünïcödé 🚀'),
      ];
      await s.api.saveBlocks('p1', blocks);
      final req = s.calls.single;
      expect(req.url.toString(), 'http://10.0.2.2:8080/api/v1/pages/p1/blocks');
      expect(req.method, 'PUT');
      expect(jsonDecode(utf8.decode(req.bodyBytes)), {
        'blocks': [
          {'id': 'b1', 'type': 'todo', 'text': 'Ship', 'checked': true},
          {'id': 'b2', 'type': 'paragraph', 'text': 'Notes · ünïcödé 🚀', 'checked': false},
        ],
      });
    });

    test('updatePage sends only the given fields', () async {
      final s = _Setup(reply(json(200, {
        'id': 'p1',
        'parentId': null,
        'title': 'Roadmap',
        'icon': '',
        'createdAt': 'c',
        'updatedAt': 'u',
      })));
      final page = await s.api.updatePage('p1', title: 'Roadmap');
      expect(page.title, 'Roadmap');
      expect(s.calls.single.method, 'PATCH');
      expect(jsonDecode(s.calls.single.body), {'title': 'Roadmap'});
    });

    test('createPage sends parentId (null for a top-level page)', () async {
      final body = {'id': 'n', 'parentId': null, 'title': '', 'icon': '', 'createdAt': 'c', 'updatedAt': 'u'};
      final s = _Setup(reply(json(201, body)));
      await s.api.createPage();
      expect(jsonDecode(s.calls.single.body), {'parentId': null});
    });

    test('UTF-8 response bodies decode correctly without a charset header', () async {
      final s = _Setup(reply(http.Response.bytes(
        utf8.encode(jsonEncode({
          'results': [
            {'id': '1', 'parentId': null, 'title': 'Café ☕', 'icon': '☕', 'snippet': '…'},
          ],
        })),
        200,
      )));
      final results = await s.api.search('café');
      expect(results.single.title, 'Café ☕');
    });

    test('search encodes the query literally', () async {
      final s = _Setup(reply(json(200, {'results': []})));
      await s.api.search('100% & more');
      expect(s.calls.single.url.toString(), 'http://10.0.2.2:8080/api/v1/search?q=100%25%20%26%20more');
    });

    test('base URL is normalised (whitespace, trailing slashes, empty → localhost)', () {
      expect(normalizeBaseUrl(' https://api.example.com// '), 'https://api.example.com');
      expect(normalizeBaseUrl(''), 'http://localhost:8080');
    });
  });
}
