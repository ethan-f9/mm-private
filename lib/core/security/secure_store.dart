import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Penyimpanan secret di Android Keystore. API key AI (BYOK) hanya di sini,
/// bukan di `.env`, bukan di asset, bukan di repo.
class SecureStore {
  SecureStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _aiKey = 'ai_api_key';

  Future<String?> readAiKey() => _storage.read(key: _aiKey);

  Future<void> writeAiKey(String value) =>
      _storage.write(key: _aiKey, value: value.trim());

  Future<void> deleteAiKey() => _storage.delete(key: _aiKey);
}
