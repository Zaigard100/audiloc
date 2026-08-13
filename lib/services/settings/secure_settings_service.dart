import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The one real secret AudiLoc holds: the local Syncthing instance's API
/// key (ТЗ п.3, "Безопасное хранение ключей устройства" →
/// flutter_secure_storage). The CRDT layer's own node id doesn't need this
/// treatment — it isn't a secret, see `DeviceIdentityService`.
class SecureSettingsService {
  SecureSettingsService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _syncthingApiKeyKey = 'syncthing_api_key';

  final FlutterSecureStorage _storage;

  Future<String?> getSyncthingApiKey() => _storage.read(key: _syncthingApiKeyKey);

  Future<void> setSyncthingApiKey(String value) =>
      _storage.write(key: _syncthingApiKeyKey, value: value);
}
