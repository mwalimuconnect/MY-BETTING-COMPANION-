import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Color kPrimary = Color(0xFF0D6EFD);
const Color kEmerald = Color(0xFF00C853);
const Color kEmeraldDark = Color(0xFF0F9D58);
const Color kTealAccent = Color(0xFF008080);

// ---------------------------------------------------------------------------
// Theme-aware colours (so every screen works in light and dark mode)
// ---------------------------------------------------------------------------
bool isDarkMode(BuildContext c) => Theme.of(c).brightness == Brightness.dark;

Color cardBg(BuildContext c) =>
    isDarkMode(c) ? const Color(0xFF1E2228) : const Color(0xFFE8F5E9);

Color headBg(BuildContext c) =>
    isDarkMode(c) ? const Color(0xFF243447) : const Color(0xFFE8F1FF);

Color lineColor(BuildContext c) =>
    isDarkMode(c) ? const Color(0xFF2E343C) : const Color(0xFFE9ECEF);

Color mutedText(BuildContext c) =>
    isDarkMode(c) ? Colors.grey.shade400 : Colors.grey.shade700;

Color ticketCardBg(BuildContext c) =>
    isDarkMode(c) ? const Color(0xFF10281E) : const Color(0xFFECFDF3);

Color ticketBorderColor(BuildContext c) =>
    isDarkMode(c) ? const Color(0xFF1E4D38) : const Color(0xFF86EFAC);

Widget ticketStatusPill(String label, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      color: color.withOpacity(0.14),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color.withOpacity(0.65), width: 1),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: color,
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
      ),
    ),
  );
}

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
