import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the relay connection settings (URL, API key, chosen Foundry world)
/// and persists them locally. No auth/user-management beyond this — per the
/// PoC brief, the API key living in local storage is enough for now.
class RelayConfig extends ChangeNotifier {
  static const _keyBaseUrl = 'relay_base_url';
  static const _keyApiKey = 'relay_api_key';
  static const _keyClientId = 'relay_client_id';
  static const _keyClientLabel = 'relay_client_label';

  String baseUrl = '';
  String apiKey = '';
  String? clientId;
  String? clientLabel;
  bool _loaded = false;

  bool get isLoaded => _loaded;
  bool get hasConnection => baseUrl.isNotEmpty && apiKey.isNotEmpty;
  bool get isComplete => hasConnection && clientId != null && clientId!.isNotEmpty;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    baseUrl = prefs.getString(_keyBaseUrl) ?? '';
    apiKey = prefs.getString(_keyApiKey) ?? '';
    clientId = prefs.getString(_keyClientId);
    clientLabel = prefs.getString(_keyClientLabel);
    _loaded = true;
    notifyListeners();
  }

  Future<void> saveConnection({required String baseUrl, required String apiKey}) async {
    final prefs = await SharedPreferences.getInstance();
    this.baseUrl = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    this.apiKey = apiKey.trim();
    await prefs.setString(_keyBaseUrl, this.baseUrl);
    await prefs.setString(_keyApiKey, this.apiKey);
    notifyListeners();
  }

  Future<void> selectClient({required String clientId, required String label}) async {
    final prefs = await SharedPreferences.getInstance();
    this.clientId = clientId;
    clientLabel = label;
    await prefs.setString(_keyClientId, clientId);
    await prefs.setString(_keyClientLabel, label);
    notifyListeners();
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyBaseUrl);
    await prefs.remove(_keyApiKey);
    await prefs.remove(_keyClientId);
    await prefs.remove(_keyClientLabel);
    baseUrl = '';
    apiKey = '';
    clientId = null;
    clientLabel = null;
    notifyListeners();
  }
}
