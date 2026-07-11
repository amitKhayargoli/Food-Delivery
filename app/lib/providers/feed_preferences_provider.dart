import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stores the user's feed personalization preferences in SharedPreferences.
///
/// Each toggle corresponds to a home screen feature the user can turn on/off
/// from the Customize Feed screen in settings.
class FeedPreferencesProvider with ChangeNotifier {
  final SharedPreferences _prefs;

  static const String _timeOfDayKey = 'feed_time_of_day_enabled';
  static const String _personalizedSuggestionsKey = 'feed_personalized_enabled';
  static const String _quickReorderKey = 'feed_quick_reorder_enabled';

  bool _timeOfDayEnabled = true;
  bool _personalizedSuggestionsEnabled = true;
  bool _quickReorderEnabled = true;

  FeedPreferencesProvider(this._prefs) {
    _loadFromPrefs();
  }

  // ── Getters ──

  /// Show the time-of-day greeting and meal-type suggestions on the home screen.
  bool get timeOfDayEnabled => _timeOfDayEnabled;

  /// Show personalized food suggestions based on order history.
  bool get personalizedSuggestionsEnabled => _personalizedSuggestionsEnabled;

  /// Show the "Quick Reorder" section on the home screen.
  bool get quickReorderEnabled => _quickReorderEnabled;

  // ── Setters ──

  /// Toggle the time-of-day greeting & meal suggestions.
  Future<void> setTimeOfDayEnabled(bool value) async {
    if (_timeOfDayEnabled == value) return;
    _timeOfDayEnabled = value;
    notifyListeners();
    await _prefs.setBool(_timeOfDayKey, value);
  }

  /// Toggle personalized food suggestions.
  Future<void> setPersonalizedSuggestionsEnabled(bool value) async {
    if (_personalizedSuggestionsEnabled == value) return;
    _personalizedSuggestionsEnabled = value;
    notifyListeners();
    await _prefs.setBool(_personalizedSuggestionsKey, value);
  }

  /// Toggle the quick reorder section.
  Future<void> setQuickReorderEnabled(bool value) async {
    if (_quickReorderEnabled == value) return;
    _quickReorderEnabled = value;
    notifyListeners();
    await _prefs.setBool(_quickReorderKey, value);
  }

  /// Reset all preferences to their defaults (enabled).
  Future<void> resetToDefaults() async {
    _timeOfDayEnabled = true;
    _personalizedSuggestionsEnabled = true;
    _quickReorderEnabled = true;
    notifyListeners();
    await _prefs.setBool(_timeOfDayKey, true);
    await _prefs.setBool(_personalizedSuggestionsKey, true);
    await _prefs.setBool(_quickReorderKey, true);
  }

  /// Number of features that are currently disabled.
  int get disabledCount {
    int count = 0;
    if (!_timeOfDayEnabled) count++;
    if (!_personalizedSuggestionsEnabled) count++;
    if (!_quickReorderEnabled) count++;
    return count;
  }

  // ── Persistence ──

  void _loadFromPrefs() {
    _timeOfDayEnabled = _prefs.getBool(_timeOfDayKey) ?? true;
    _personalizedSuggestionsEnabled = _prefs.getBool(_personalizedSuggestionsKey) ?? true;
    _quickReorderEnabled = _prefs.getBool(_quickReorderKey) ?? true;
  }
}
