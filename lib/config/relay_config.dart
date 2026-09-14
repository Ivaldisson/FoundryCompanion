import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the relay connection settings (URL, API key, chosen Foundry world)
/// and persists them locally. No auth/user-management beyond this — a
/// single device-local API key is enough for now.
///
/// The API key specifically lives in `flutter_secure_storage` (Android
/// Keystore-backed), not `shared_preferences` — everything else here
/// (`baseUrl`, `clientId`, `clientLabel`) is non-secret and stays in plain
/// prefs.
class RelayConfig extends ChangeNotifier {
  static const _keyBaseUrl = 'relay_base_url';
  static const _keyApiKey = 'relay_api_key';
  static const _keyClientId = 'relay_client_id';
  static const _keyClientLabel = 'relay_client_label';
  static const _keySystemId = 'relay_system_id';

  static const _secureStorage = FlutterSecureStorage();

  String baseUrl = '';
  String apiKey = '';
  String? clientId;
  String? clientLabel;
  String? systemId;
  bool _loaded = false;

  bool get isLoaded => _loaded;
  bool get hasConnection => baseUrl.isNotEmpty && apiKey.isNotEmpty;
  bool get isComplete => hasConnection && clientId != null && clientId!.isNotEmpty;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    baseUrl = prefs.getString(_keyBaseUrl) ?? '';
    clientId = prefs.getString(_keyClientId);
    clientLabel = prefs.getString(_keyClientLabel);
    systemId = prefs.getString(_keySystemId);

    apiKey = await _secureStorage.read(key: _keyApiKey) ?? '';
    // One-time migration: earlier builds stored the key in plain
    // shared_preferences. Move it over so existing installs don't have to
    // re-enter it, then scrub the plaintext copy.
    if (apiKey.isEmpty) {
      final legacyKey = prefs.getString(_keyApiKey);
      if (legacyKey != null && legacyKey.isNotEmpty) {
        apiKey = legacyKey;
        await _secureStorage.write(key: _keyApiKey, value: legacyKey);
        await prefs.remove(_keyApiKey);
      }
    }

    _loaded = true;
    notifyListeners();
  }

  Future<void> saveConnection({required String baseUrl, required String apiKey}) async {
    final prefs = await SharedPreferences.getInstance();
    this.baseUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    this.apiKey = apiKey.trim();
    await prefs.setString(_keyBaseUrl, this.baseUrl);
    await _secureStorage.write(key: _keyApiKey, value: this.apiKey);
    notifyListeners();
  }

  Future<void> selectClient({required String clientId, required String label, String? systemId}) async {
    final prefs = await SharedPreferences.getInstance();
    this.clientId = clientId;
    clientLabel = label;
    this.systemId = systemId;
    await prefs.setString(_keyClientId, clientId);
    await prefs.setString(_keyClientLabel, label);
    if (systemId != null) {
      await prefs.setString(_keySystemId, systemId);
    } else {
      await prefs.remove(_keySystemId);
    }
    notifyListeners();
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyBaseUrl);
    await prefs.remove(_keyClientId);
    await prefs.remove(_keyClientLabel);
    await prefs.remove(_keySystemId);
    await _secureStorage.delete(key: _keyApiKey);
    baseUrl = '';
    apiKey = '';
    clientId = null;
    clientLabel = null;
    systemId = null;
    notifyListeners();
  }
}
