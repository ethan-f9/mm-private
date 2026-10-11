import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Penyimpanan secret di Android Keystore. Groq API key (BYOK) hanya di sini,
/// bukan di `.env`, bukan di asset, bukan di repo.
class SecureStore {
  SecureStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const _groqKey = 'groq_api_key';

  Future<String?> readGroqKey() => _storage.read(key: _groqKey);

  Future<void> writeGroqKey(String value) =>
      _storage.write(key: _groqKey, value: value.trim());

  Future<void> deleteGroqKey() => _storage.delete(key: _groqKey);
}
