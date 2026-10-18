import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettingsController extends ChangeNotifier {
  static const _themeKey = 'app_theme_mode';
  static const _languageKey = 'app_language';

  ThemeMode _themeMode = ThemeMode.system;
  Locale _locale = const Locale('en');

  ThemeMode get themeMode => _themeMode;
  Locale get locale => _locale;

  static ThemeMode decodeThemeMode(String? value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String encodeThemeMode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  static Locale decodeLocale(String? value) {
    return value == 'bn' ? const Locale('bn') : const Locale('en');
  }

  static String encodeLocale(Locale locale) {
    return locale.languageCode == 'bn' ? 'bn' : 'en';
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _themeMode = decodeThemeMode(prefs.getString(_themeKey));
    _locale = decodeLocale(prefs.getString(_languageKey));
    notifyListeners();
  }

  Future<void> updateThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, encodeThemeMode(mode));
    notifyListeners();
  }

  Future<void> updateLocale(Locale locale) async {
    final normalized = decodeLocale(locale.languageCode);
    if (_locale == normalized) return;
    _locale = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, encodeLocale(normalized));
    notifyListeners();
  }
}
