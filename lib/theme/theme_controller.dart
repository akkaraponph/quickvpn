import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the user's theme choice (System / Light / Dark) and persists it across
/// launches with shared_preferences. Defaults to dark — the app's signature look.
class ThemeController extends ChangeNotifier {
  static const _prefsKey = 'theme_mode';

  ThemeMode _mode = ThemeMode.dark;
  ThemeMode get mode => _mode;

  /// Load the saved choice. Safe to call once at startup; falls back to the
  /// default if storage is unavailable.
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      final parsed = _parse(saved);
      if (parsed != _mode) {
        _mode = parsed;
        notifyListeners();
      }
    } catch (_) {
      // Keep the default on any storage error.
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    if (mode == _mode) return;
    _mode = mode;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, mode.name);
    } catch (_) {
      // Best effort — the in-memory choice still applies for this session.
    }
  }

  ThemeMode _parse(String? value) {
    switch (value) {
      case 'light':
        return ThemeMode.light;
      case 'system':
        return ThemeMode.system;
      case 'dark':
      default:
        return ThemeMode.dark;
    }
  }
}
