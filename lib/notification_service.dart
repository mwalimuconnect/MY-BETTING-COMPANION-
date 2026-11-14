import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'fixture_model.dart';

/// Local (on-device) notifications. Kickoff reminders are scheduled whenever
/// the app loads fixtures. There is no background server push, so result
/// alerts only appear when the app is opened.
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'kickoff_reminders',
      'Kickoff reminders',
      channelDescription: 'Reminders before saved and favourite matches start',
      importance: Importance.high,
      priority: Priority.high,
    ),
  );

  static Future<void> init() async {
    try {
      tzdata.initializeTimeZones();
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      await _plugin.initialize(const InitializationSettings(android: android));
      _ready = true;
    } catch (e) {
      debugPrint('Notification init failed: $e');
    }
  }

  /// Asks for the Android 13+ notification permission.
  static Future<bool> requestPermission() async {
    if (!_ready) return false;
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission();
      return granted ?? false;
    } catch (e) {
      debugPrint('Notification permission failed: $e');
      return false;
    }
  }

  /// Replaces all scheduled reminders with fresh ones: 15 minutes before
  /// kickoff for saved matches and matches of favourite teams.
  static Future<void> scheduleKickoffReminders(
    List<FixtureModel> fixtures,
    Set<String> savedKeys,
    Set<String> favorites,
  ) async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
      final now = DateTime.now().toUtc();
      var scheduled = 0;

      for (final f in fixtures) {
        if (scheduled >= 40) break;
        if (f.isFinished || f.isLive) continue;
        final key = f.key;
        if (key == null) continue;

        final relevant = savedKeys.contains(key) ||
            favorites.contains(f.homeTeam) ||
            favorites.contains(f.awayTeam);
        if (!relevant) continue;

        final kickoff = f.kickoff;
        if (kickoff == null) continue;
        final remindAt = kickoff.toUtc().subtract(const Duration(minutes: 15));
        if (!remindAt.isAfter(now)) continue;

        try {
          await _plugin.zonedSchedule(
            key.hashCode & 0x7fffffff,
            'Kickoff soon',
            '${f.homeTeam} vs ${f.awayTeam} starts in 15 minutes.',
            tz.TZDateTime.from(remindAt, tz.UTC),
            _details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
          );
          scheduled++;
        } catch (e) {
          debugPrint('Could not schedule reminder for $key: $e');
        }
      }
      debugPrint('Scheduled $scheduled kickoff reminders');
    } catch (e) {
      debugPrint('Scheduling reminders failed: $e');
    }
  }

  /// Scans fixtures and sends an immediate notification if an accumulator 
  /// slip targeting 5.00 - 10.00 odds is successfully generated.
  static Future<void> checkAndNotifyAutoSlip(List<dynamic> fixtures) async {
    if (!_ready) return;

    double cumulativeOdds = 1.0;
    int selectionCount = 0;

    for (final f in fixtures) {
      double odds = 1.5; // Fallback odds or pull from model property
      try {
        if (f is Map && f['odds'] != null) {
          odds = double.tryParse(f['odds'].toString()) ?? 1.5;
        } else if (f is FixtureModel) {
          // Adjust if your model exposes an odds field
          odds = 1.6; 
        }
      } catch (_) {}

      if (cumulativeOdds * odds <= 12.0) {
        cumulativeOdds *= odds;
        selectionCount++;
      }

      // Check if cumulative odds fall inside the target [5.00 - 10.00] window
      if (cumulativeOdds >= 5.00 && cumulativeOdds <= 10.00) {
        await showNow(
          '🔥 Prolific Slip Ready!',
          'Your accumulator slip with total odds of ${cumulativeOdds.toStringAsFixed(2)}x ($selectionCount matches) is ready!',
        );
        break; // Triggered once per check
      }
    }
  }

  static Future<void> cancelAll() async {
    if (!_ready) return;
    try {
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint('Cancel notifications failed: $e');
    }
  }

  static Future<void> showNow(String title, String body) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        DateTime.now().millisecondsSinceEpoch & 0x7fffffff,
        title,
        body,
        _details,
      );
    } catch (e) {
      debugPrint('Show notification failed: $e');
    }
  }
}
