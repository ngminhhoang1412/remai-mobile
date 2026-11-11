import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';

/// Error raised for every failed API call. [status] is the HTTP status (0 for a network failure or
/// timeout) and [code] is the envelope's snake_case code (`{"error":{"code","message"}}`), or a
/// client-side code when the server sent none.
class ApiException implements Exception {
  const ApiException(this.status, this.code, this.message);

  final int status;
  final String code;
  final String message;

  bool get isNetworkError => status == 0;

  @override
  String toString() => 'ApiException($status, $code)';
}

/// Statuses where sending the same save again can't succeed (add-notion-core D10): autosave shows
/// "Couldn't save" instead of retrying. 429 (slow down), 5xx and network failures are retried.
const Set<int> nonRetryableSaveStatuses = {400, 401, 404, 413};

bool isRetryableSaveError(Object error) =>
    error is! ApiException || !nonRetryableSaveStatuses.contains(error.status);

/// A user-facing message for any thrown value.
String errorMessage(Object error) =>
    error is ApiException ? error.message : 'Something went wrong. Please try again.';

/// Base URL of remai-backend, set at build time with `--dart-define=REMAI_API_URL=...`.
/// Android emulator: `http://10.0.2.2:8080`; physical device: `http://<PC LAN IP>:8080`.
const String _apiUrlDefine = String.fromEnvironment('REMAI_API_URL', defaultValue: 'http://localhost:8080');

String get configuredApiUrl => normalizeBaseUrl(_apiUrlDefine);

String normalizeBaseUrl(String url) {
  final trimmed = url.trim();
  return (trimmed.isEmpty ? 'http://localhost:8080' : trimmed).replaceAll(RegExp(r'/+$'), '');
}

/// remai REST client (docs/api/openapi.yaml): bearer token, error envelope, 401 → sign-out callback,
/// 429 → "slow down" regardless of body (design D9: the platform's 429 body isn't an envelope).
class ApiClient {
  ApiClient({
    required String baseUrl,
    required http.Client httpClient,
    required String? Function() getToken,
    required void Function(String? tokenUsed) onUnauthorized,
    this.timeout = const Duration(seconds: 30),
  })  : baseUrl = normalizeBaseUrl(baseUrl),
        _http = httpClient,
        _getToken = getToken,
        _onUnauthorized = onUnauthorized;

  final String baseUrl;

  /// Per-request timeout (null: none, used by widget tests so no timer outlives a test).
  final Duration? timeout;
  final http.Client _http;
  final String? Function() _getToken;

  /// Called when an authenticated request gets 401: the session must be discarded. Receives the
  /// token that request used, so a late 401 for an old token can be ignored after a new sign-in.
  final void Function(String? tokenUsed) _onUnauthorized;

  static const _networkMessage = 'Can’t reach the server. Check your connection.';
  static const _rateLimitMessage = 'Too many requests. Please wait a moment and try again.';

  /// [auth] is false for register/login: no bearer header, and a 401 there is not a session expiry.
  Future<Object?> _request(String method, String path, {Object? body, bool auth = true}) async {
    final token = auth ? _getToken() : null;
    // Signed out: never hit the network for an authenticated endpoint.
    if (auth && token == null) throw const ApiException(401, 'unauthorized', 'You are signed out.');

    final req = http.Request(method, Uri.parse('$baseUrl$path'));
    req.headers['Accept'] = 'application/json';
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.bodyBytes = utf8.encode(jsonEncode(body));
    }

    final http.Response res;
    try {
      final t = timeout;
      final sent = t == null ? _http.send(req) : _http.send(req).timeout(t);
      final read = http.Response.fromStream(await sent);
      res = await (t == null ? read : read.timeout(t));
    } on TimeoutException {
      throw const ApiException(0, 'network_error', _networkMessage);
    } on http.ClientException {
      throw const ApiException(0, 'network_error', _networkMessage);
    } on Exception {
      // SocketException, HandshakeException, ... (dart:io isn't imported so tests stay platform-free).
      throw const ApiException(0, 'network_error', _networkMessage);
    }

    if (res.statusCode == 429) {
      throw const ApiException(429, 'rate_limited', _rateLimitMessage);
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final err = _parseError(res);
      if (res.statusCode == 401 && auth) _onUnauthorized(token);
      throw err;
    }
    if (res.statusCode == 204 || res.bodyBytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      throw ApiException(res.statusCode, 'invalid_response', 'The server sent an unexpected response.');
    }
  }

  static ApiException _parseError(http.Response res) {
    var code = 'http_error';
    var message = 'Request failed (${res.statusCode}).';
    if (res.statusCode == 413) message = 'This page is too large to save.';
    try {
      final data = jsonDecode(utf8.decode(res.bodyBytes));
      if (data is Map && data['error'] is Map) {
        final error = data['error'] as Map;
        if (error['code'] is String) {
          code = error['code'] as String;
          final m = error['message'];
          if (m is String && m.isNotEmpty) message = m;
        }
      }
    } on FormatException {
      // Non-JSON body (proxy / platform error page, empty body...): keep the generic message.
    }
    return ApiException(res.statusCode, code, message);
  }

  static Map<String, dynamic> _map(Object? json) => json as Map<String, dynamic>;

  static String _enc(String s) => Uri.encodeComponent(s);

  // ---- auth ----
  Future<AuthResponse> register(String email, String name, String password) async => AuthResponse.fromJson(_map(
      await _request('POST', '/api/v1/auth/register',
          body: {'email': email, 'name': name, 'password': password}, auth: false)));

  Future<AuthResponse> login(String email, String password) async => AuthResponse.fromJson(
      _map(await _request('POST', '/api/v1/auth/login', body: {'email': email, 'password': password}, auth: false)));

  Future<User> me() async => User.fromJson(_map(await _request('GET', '/api/v1/auth/me')));

  // ---- pages ----
  Future<List<PageInfo>> listPages() async {
    final json = _map(await _request('GET', '/api/v1/pages'));
    return [for (final p in json['pages'] as List<dynamic>) PageInfo.fromJson(p as Map<String, dynamic>)];
  }

  /// [parentId] null creates a top-level page.
  Future<PageInfo> createPage({String? parentId, String? title}) async => PageInfo.fromJson(_map(await _request(
      'POST', '/api/v1/pages',
      body: {'parentId': parentId, 'title': ?title})));

  Future<PageWithBlocks> getPage(String id) async =>
      PageWithBlocks.fromJson(_map(await _request('GET', '/api/v1/pages/${_enc(id)}')));

  /// Fields left null are not sent and stay unchanged on the server.
  Future<PageInfo> updatePage(String id, {String? title, String? icon}) async => PageInfo.fromJson(
      _map(await _request('PATCH', '/api/v1/pages/${_enc(id)}', body: {'title': ?title, 'icon': ?icon})));

  Future<void> trashPage(String id) async {
    await _request('DELETE', '/api/v1/pages/${_enc(id)}');
  }

  /// Replaces the page's whole ordered block list (client-generated UUIDs are kept).
  Future<void> saveBlocks(String id, List<Block> blocks) async {
    await _request('PUT', '/api/v1/pages/${_enc(id)}/blocks', body: {
      'blocks': [for (final b in blocks) b.toJson()],
    });
  }

  // ---- search ----
  Future<List<SearchResult>> search(String query) async {
    final json = _map(await _request('GET', '/api/v1/search?q=${_enc(query)}'));
    return [for (final r in json['results'] as List<dynamic>) SearchResult.fromJson(r as Map<String, dynamic>)];
  }

  // ---- trash ----
  Future<List<TrashedPage>> listTrash() async {
    final json = _map(await _request('GET', '/api/v1/trash'));
    return [for (final p in json['pages'] as List<dynamic>) TrashedPage.fromJson(p as Map<String, dynamic>)];
  }

  Future<PageInfo> restorePage(String id) async =>
      PageInfo.fromJson(_map(await _request('POST', '/api/v1/trash/${_enc(id)}/restore')));

  Future<void> deleteForever(String id) async {
    await _request('DELETE', '/api/v1/trash/${_enc(id)}');
  }
}
