import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the session token is persisted. The app uses [SecureTokenStorage]; tests use an
/// in-memory implementation.
abstract class TokenStorage {
  Future<String?> read();
  Future<void> write(String token);
  Future<void> delete();
}

/// The session token lives only in the platform's secure storage (iOS Keychain, Android
/// Keystore-backed encrypted storage), never in shared preferences or plain files.
class SecureTokenStorage implements TokenStorage {
  SecureTokenStorage([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(accessibility: KeychainAccessibility.unlocked_this_device),
            );

  static const _key = 'remai.session.token';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() async {
    try {
      final value = await _storage.read(key: _key);
      return value == null || value.isEmpty ? null : value;
    } on Exception {
      // Unreadable entry (e.g. restored backup on a new device): treat as signed out.
      return null;
    }
  }

  @override
  Future<void> write(String token) => _storage.write(key: _key, value: token);

  @override
  Future<void> delete() async {
    try {
      await _storage.delete(key: _key);
    } on Exception {
      // Nothing stored / already gone.
    }
  }
}
