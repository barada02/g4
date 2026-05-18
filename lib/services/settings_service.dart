import 'package:shared_preferences/shared_preferences.dart';

/// Settings service for managing model parameters
class SettingsService {
  SettingsService._internal();
  static final SettingsService instance = SettingsService._internal();

  static const String _temperatureKey = 'model_temperature';
  static const String _topKKey = 'model_topk';
  static const String _topPKey = 'model_topp';
  static const String _maxTokensKey = 'model_max_tokens';

  // Default values
  static const double defaultTemperature = 0.7;
  static const int defaultTopK = 40;
  static const double defaultTopP = 0.95;
  static const int defaultMaxTokens = 2048;

  late SharedPreferences _prefs;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    _initialized = true;
  }

  // Temperature (0.0 - 2.0)
  double get temperature => _prefs.getDouble(_temperatureKey) ?? defaultTemperature;
  Future<void> setTemperature(double value) async {
    await _prefs.setDouble(_temperatureKey, value);
  }

  // Top K (1 - 100)
  int get topK => _prefs.getInt(_topKKey) ?? defaultTopK;
  Future<void> setTopK(int value) async {
    await _prefs.setInt(_topKKey, value);
  }

  // Top P (0.0 - 1.0)
  double get topP => _prefs.getDouble(_topPKey) ?? defaultTopP;
  Future<void> setTopP(double value) async {
    await _prefs.setDouble(_topPKey, value);
  }

  // Max Tokens (256 - 4096)
  int get maxTokens => _prefs.getInt(_maxTokensKey) ?? defaultMaxTokens;
  Future<void> setMaxTokens(int value) async {
    await _prefs.setInt(_maxTokensKey, value);
  }

  /// Reset all settings to defaults
  Future<void> resetToDefaults() async {
    await _prefs.remove(_temperatureKey);
    await _prefs.remove(_topKKey);
    await _prefs.remove(_topPKey);
    await _prefs.remove(_maxTokensKey);
  }
}
