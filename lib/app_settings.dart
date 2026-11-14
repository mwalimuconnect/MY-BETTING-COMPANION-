import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Color kPrimary = Color(0xFF0D6EFD);

// ---------------------------------------------------------------------------
// Theme-aware colours (so every screen works in light and dark mode)
// ---------------------------------------------------------------------------
bool isDarkMode(BuildContext c) => Theme.of(c).brightness == Brightness.dark;

Color cardBg(BuildContext c) =>
    isDarkMode(c) ? const Color(0xFF1E2228) : Colors.white;

Color headBg(BuildContext c) =>
    isDarkMode(c) ? const Color(0xFF243447) : const Color(0xFFE8F1FF);

Color lineColor(BuildContext c) =>
    isDarkMode(c) ? const Color(0xFF2E343C) : const Color(0xFFE9ECEF);

Color mutedText(BuildContext c) =>
    isDarkMode(c) ? Colors.grey.shade400 : Colors.grey.shade700;

// ---------------------------------------------------------------------------
// Settings that survive app restarts
// ---------------------------------------------------------------------------
class AppSettings {
  static final ValueNotifier<ThemeMode> themeMode =
      ValueNotifier<ThemeMode>(ThemeMode.light);
  static final ValueNotifier<bool> notificationsOn = ValueNotifier<bool>(false);
  static final ValueNotifier<Set<String>> favorites =
      ValueNotifier<Set<String>>(<String>{});

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      themeMode.value =
          (p.getBool('dark_mode') ?? false) ? ThemeMode.dark : ThemeMode.light;
      notificationsOn.value = p.getBool('notifications_on') ?? false;
      favorites.value = (p.getStringList('favorite_teams') ?? <String>[]).toSet();
    } catch (e) {
      debugPrint('Could not load settings: $e');
    }
  }

  static Future<void> setDark(bool dark) async {
    themeMode.value = dark ? ThemeMode.dark : ThemeMode.light;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('dark_mode', dark);
    } catch (e) {
      debugPrint('Could not save dark mode: $e');
    }
  }

  static Future<void> setNotifications(bool on) async {
    notificationsOn.value = on;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('notifications_on', on);
    } catch (e) {
      debugPrint('Could not save notification setting: $e');
    }
  }

  static Future<void> toggleFavorite(String team) async {
    final next = Set<String>.from(favorites.value);
    if (!next.remove(team)) next.add(team);
    favorites.value = next; // new object so listeners fire
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList('favorite_teams', next.toList());
    } catch (e) {
      debugPrint('Could not save favourites: $e');
    }
  }
}
