import 'package:flutter/material.dart';
import '../database/dao.dart';
import '../ai/llm_client.dart';
import '../models/theme/theme_type.dart';
import '../models/theme/theme_color_type.dart';

class SettingsProvider extends ChangeNotifier {
  final Dao _dao = Dao();

  String? _apiKey;
  String? _baseUrl;
  String? _modelName;
  String? _startTab;
  bool _showWrongTitle = true;
  String? _aiPrompt;
  bool _autoLlmAnalyze = false;
  int _themeModeIndex = 2; // 默认跟随系统
  int _themeColorIndex = 0; // 默认蓝色

  String? get apiKey => _apiKey;
  String? get baseUrl => _baseUrl;
  String? get modelName => _modelName;

  bool get hasLLM => _apiKey != null && _apiKey!.isNotEmpty && _baseUrl != null && _baseUrl!.isNotEmpty;

  /// 启动时默认打开的 tab: 'home' / 'tests' / 'wrongbook'
  String get startTab => _startTab ?? 'home';

  /// 首页是否显示错题提醒卡片（默认显示）
  bool get showWrongTitle => _showWrongTitle;

  /// LLM 分析用的 prompt 模板
  String get aiPrompt => _aiPrompt ?? LlmClient.defaultPrompt;

  /// 导入题库后是否自动调用 LLM 分析（默认关闭）
  bool get autoLlmAnalyze => _autoLlmAnalyze;

  /// 主题模式: 0=浅色, 1=深色, 2=跟随系统
  int get themeModeIndex => _themeModeIndex;
  ThemeType get themeType => ThemeType.values[_themeModeIndex.clamp(0, 2)];

  /// 主题颜色索引
  int get themeColorIndex => _themeColorIndex;
  Color get themeColor => themeColorPresets[_themeColorIndex.clamp(0, themeColorPresets.length - 1)].color;

  Future<void> loadSettings() async {
    _apiKey = await _dao.getSetting('api_key');
    _baseUrl = await _dao.getSetting('base_url');
    _modelName = await _dao.getSetting('model_name');
    _startTab = await _dao.getSetting('start_tab');
    final showWrong = await _dao.getSetting('show_wrong_title');
    _showWrongTitle = showWrong != 'false'; // 默认 true
    _aiPrompt = await _dao.getSetting('ai_prompt');
    final autoLlm = await _dao.getSetting('auto_llm_analyze');
    _autoLlmAnalyze = autoLlm == 'true'; // 默认 false
    final themeMode = await _dao.getSetting('theme_mode');
    _themeModeIndex = int.tryParse(themeMode ?? '') ?? 2; // 默认跟随系统
    final themeColor = await _dao.getSetting('theme_color');
    _themeColorIndex = int.tryParse(themeColor ?? '') ?? 0; // 默认蓝色
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

  Future<void> setStartTab(String value) async {
    _startTab = value;
    await _dao.setSetting('start_tab', value);
    notifyListeners();
  }

  Future<void> setShowWrongTitle(bool value) async {
    _showWrongTitle = value;
    await _dao.setSetting('show_wrong_title', value.toString());
    notifyListeners();
  }

  Future<void> setAiPrompt(String value) async {
    _aiPrompt = value;
    await _dao.setSetting('ai_prompt', value);
    notifyListeners();
  }

  Future<void> setAutoLlmAnalyze(bool value) async {
    _autoLlmAnalyze = value;
    await _dao.setSetting('auto_llm_analyze', value.toString());
    notifyListeners();
  }

  Future<void> setThemeModeIndex(int value) async {
    _themeModeIndex = value.clamp(0, 2);
    await _dao.setSetting('theme_mode', _themeModeIndex.toString());
    notifyListeners();
  }

  Future<void> setThemeColorIndex(int value) async {
    _themeColorIndex = value.clamp(0, themeColorPresets.length - 1);
    await _dao.setSetting('theme_color', _themeColorIndex.toString());
    notifyListeners();
  }
}
