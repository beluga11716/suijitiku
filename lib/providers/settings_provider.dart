import 'package:flutter/foundation.dart';
import '../database/dao.dart';

class SettingsProvider extends ChangeNotifier {
  final Dao _dao = Dao();

  String? _apiKey;
  String? _baseUrl;
  String? _modelName;

  String? get apiKey => _apiKey;
  String? get baseUrl => _baseUrl;
  String? get modelName => _modelName;

  bool get hasLLM => _apiKey != null && _apiKey!.isNotEmpty && _baseUrl != null && _baseUrl!.isNotEmpty;

  Future<void> loadSettings() async {
    _apiKey = await _dao.getSetting('api_key');
    _baseUrl = await _dao.getSetting('base_url');
    _modelName = await _dao.getSetting('model_name');
    notifyListeners();
  }

  Future<void> setApiKey(String value) async {
    _apiKey = value;
    await _dao.setSetting('api_key', value);
    notifyListeners();
  }

  Future<void> setBaseUrl(String value) async {
    _baseUrl = value;
    await _dao.setSetting('base_url', value);
    notifyListeners();
  }

  Future<void> setModelName(String value) async {
    _modelName = value;
    await _dao.setSetting('model_name', value);
    notifyListeners();
  }
}
