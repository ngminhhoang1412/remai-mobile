import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../api/api_client.dart';
import '../api/token_storage.dart';
import '../models/models.dart';

/// - [loading]: reading the stored token / checking it with GET /auth/me
/// - [unreachable]: a token is stored but the server couldn't be reached to check it
enum SessionStatus { loading, signedOut, signedIn, unreachable }

/// Session token + current user. The router listens to this to show sign-in or the app.
class SessionState extends ChangeNotifier {
  SessionState({
    required TokenStorage storage,
    required http.Client httpClient,
    required String baseUrl,
    Duration? requestTimeout = const Duration(seconds: 30),
  }) : _storage = storage {
    api = ApiClient(
      baseUrl: baseUrl,
      httpClient: httpClient,
      getToken: () => _token,
      onUnauthorized: (tokenUsed) {
        // Ignore a late 401 for a token that has already been replaced by a new sign-in.
        if (tokenUsed != null && tokenUsed != _token) return;
        unawaited(signOut());
      },
      timeout: requestTimeout,
    );
  }

  final TokenStorage _storage;
  late final ApiClient api;

  SessionStatus _status = SessionStatus.loading;
  User? _user;
  String? _token;
  int _launchSeq = 0;
  bool _disposed = false;

  SessionStatus get status => _status;
  User? get user => _user;

  /// Launch check: read the stored token and validate it with GET /auth/me. A 401 signs out (via
  /// onUnauthorized); a network failure keeps the token and reports [SessionStatus.unreachable].
  Future<void> checkStoredToken() async {
    final seq = ++_launchSeq;
    _set(SessionStatus.loading);
    final token = await _storage.read();
    if (seq != _launchSeq) return;
    if (token == null) {
      _set(SessionStatus.signedOut);
      return;
    }
    _token = token;
    try {
      final me = await api.me();
      if (seq != _launchSeq) return;
      _user = me;
      _set(SessionStatus.signedIn);
    } on ApiException catch (e) {
      if (seq != _launchSeq) return;
      if (e.status == 401) return; // onUnauthorized already signed out
      _set(SessionStatus.unreachable);
    }
  }

  Future<void> signIn(String email, String password) async {
    final res = await api.login(email.trim(), password);
    await _start(res);
  }

  Future<void> signUp(String email, String name, String password) async {
    final res = await api.register(email.trim(), name.trim(), password);
    await _start(res);
  }

  /// Drops the session locally: forget the token in memory first so nothing sends it again.
  Future<void> signOut() async {
    _launchSeq++;
    _token = null;
    _user = null;
    _set(SessionStatus.signedOut);
    await _storage.delete();
  }

  Future<void> _start(AuthResponse res) async {
    _launchSeq++;
    await _storage.write(res.token);
    _token = res.token;
    _user = res.user;
    _set(SessionStatus.signedIn);
  }

  void _set(SessionStatus status) {
    _status = status;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
