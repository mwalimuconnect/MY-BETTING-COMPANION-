import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'fixture_model.dart';
import 'prediction_log.dart';

/// One saved tip. status: pending, won, lost, void, none (saved without a tip).
class SlipLeg {
  final String key;
  final String home;
  final String away;
  final String league;
  final String tip;
  final String kickoff; // label shown in the list
  final String utcDate;
  final int savedAt;
  String status;
  String score;

  SlipLeg({
    required this.key,
    required this.home,
    required this.away,
    required this.league,
    required this.tip,
    required this.kickoff,
    required this.utcDate,
    required this.savedAt,
    this.status = 'pending',
    this.score = '',
  });

  /// Helper to get the date string (YYYY-MM-DD) for grouping by day
  String get dayKey {
    final dt = DateTime.tryParse(utcDate)?.toLocal() ??
        DateTime.fromMillisecondsSinceEpoch(savedAt).toLocal();
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'home': home,
        'away': away,
        'league': league,
        'tip': tip,
        'kickoff': kickoff,
        'utcDate': utcDate,
        'savedAt': savedAt,
        'status': status,
        'score': score,
      };

  factory SlipLeg.fromJson(Map<String, dynamic> j) {
    return SlipLeg(
      key: j['key']?.toString() ?? '',
      home: j['home']?.toString() ?? '',
      away: j['away']?.toString() ?? '',
      league: j['league']?.toString() ?? '',
      tip: j['tip']?.toString() ?? '',
      kickoff: j['kickoff']?.toString() ?? '',
      utcDate: j['utcDate']?.toString() ?? '',
      savedAt: j['savedAt'] is num ? (j['savedAt'] as num).toInt() : 0,
      status: j['status']?.toString() ?? 'pending',
      score: j['score']?.toString() ?? '',
    );
  }
}

class SlipSummary {
  final int won;
  final int lost;
  final int pending;
  final int voided;
  final int noTip;

  /// Accumulator result: Lost if any leg lost, Pending while legs are open,
  /// Won when every judged leg won, Empty when nothing can be judged.
  final String status;

  const SlipSummary({
    required this.won,
    required this.lost,
    required this.pending,
    required this.voided,
    required this.noTip,
    required this.status,
  });
}

/// Header widget rendering MY PICKS in bold Teal Green capital letters
Widget buildMyPicksHeader() {
  return const Padding(
    padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Text(
      'MY PICKS',
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Color(0xFF008080), // Teal Green
        letterSpacing: 1.2,
      ),
    ),
  );
}

/// Bright day and date header formatted purely in standard Dart
Widget buildBrightDayHeader(String dateStr) {
  final dt = DateTime.tryParse(dateStr);
  String formatted = dateStr;
  if (dt != null) {
    const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
    const days = ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY'];
    final dayName = days[dt.weekday - 1];
    final monthName = months[dt.month - 1];
    formatted = '$dayName, ${dt.day} $monthName ${dt.year}';
  }

  return Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
    child: Text(
      formatted.toUpperCase(),
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.bold,
        color: Color(0xFF00E5FF), // Bright Cyan highlight
        letterSpacing: 1.2,
      ),
    ),
  );
}

/// Helper builder to render saved picks grouped per day with bright day/date headers
Widget buildGroupedSlipList(List<SlipLeg> legs, Function(String key) onDelete) {
  if (legs.isEmpty) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Text(
        'No picks saved yet. Tap the bookmark icon on any fixture to add it here.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey),
      ),
    );
  }

  // Group legs by dayKey (YYYY-MM-DD)
  final Map<String, List<SlipLeg>> grouped = {};
  for (final leg in legs) {
    grouped.putIfAbsent(leg.dayKey, () => []).add(leg);
  }

  // Sort dates descending (newest/upcoming first)
  final sortedDays = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

  return ListView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    itemCount: sortedDays.length,
    itemBuilder: (context, dayIndex) {
      final day = sortedDays[dayIndex];
      final dayLegs = grouped[day]!;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildBrightDayHeader(day),
          for (int i = 0; i < dayLegs.length; i++)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFF008080), // Teal Green badge
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                title: Text('${dayLegs[i].home} vs ${dayLegs[i].away}'),
                subtitle: Text(
                  'Kickoff: ${dayLegs[i].kickoff.isNotEmpty ? dayLegs[i].kickoff : "TBD"}\n'
                  'Tip: ${dayLegs[i].tip.isNotEmpty ? dayLegs[i].tip : "None"} | '
                  'Score: ${dayLegs[i].score.isNotEmpty ? dayLegs[i].score : "Pending"}',
                ),
                isThreeLine: true,
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => onDelete(dayLegs[i].key),
                ),
              ),
            ),
        ],
      );
    },
  );
}

class SlipStore {
  static const String _prefsKey = 'saved_slips_v1';

  static Future<List<SlipLeg>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final out = <SlipLeg>[];
      for (final e in decoded) {
        if (e is Map) out.add(SlipLeg.fromJson(Map<String, dynamic>.from(e)));
      }
      return out;
    } catch (e) {
      debugPrint('Could not load saved slips: $e');
      return [];
    }
  }

  static Future<void> _save(List<SlipLeg> legs) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _prefsKey, jsonEncode(legs.map((l) => l.toJson()).toList()));
    } catch (e) {
      debugPrint('Could not save slips: $e');
    }
  }

  /// Adds the match to saved slips, or removes it if already saved.
  /// Returns true when the match is now saved.
  static Future<bool> toggle(FixtureModel f) async {
    final key = f.key;
    if (key == null) return false;
    final legs = await load();
    final index = legs.indexWhere((l) => l.key == key);
    if (index >= 0) {
      legs.removeAt(index);
      await _save(legs);
      return false;
    }
    legs.add(SlipLeg(
      key: key,
      home: f.homeTeam,
      away: f.awayTeam,
      league: f.league,
      tip: f.topTip,
      kickoff: f.timeLabel,
      utcDate: f.utcDate,
      savedAt: DateTime.now().millisecondsSinceEpoch,
      status: f.topTip.isEmpty ? 'none' : 'pending',
    ));
    await _save(legs);
    return true;
  }

  static Future<void> remove(String key) async {
    final legs = await load();
    legs.removeWhere((l) => l.key == key);
    await _save(legs);
  }

  /// Removes every leg that has a final result (won, lost or void).
  static Future<void> clearSettled() async {
    final legs = await load();
    legs.removeWhere(
        (l) => l.status == 'won' || l.status == 'lost' || l.status == 'void');
    await _save(legs);
  }

  /// Settles pending legs using finished matches. Returns the legs that were
  /// newly won or lost (so the app can tell the user).
  static Future<List<SlipLeg>> settle(List<FixtureModel> fixtures) async {
    final legs = await load();
    final byKey = <String, FixtureModel>{};
    for (final f in fixtures) {
      final k = f.key;
      if (k != null) byKey[k] = f;
    }

    final now = DateTime.now().toUtc();
    final newly = <SlipLeg>[];
    var changed = false;

    for (final leg in legs) {
      if (leg.status != 'pending') continue;
      final f = byKey[leg.key];

      if (f != null && f.isFinished) {
        final result = evaluateTip(leg.tip, leg.home, leg.away, f.actualScore);
        leg.score = f.actualScore;
        leg.status = result == null ? 'void' : (result ? 'won' : 'lost');
        if (result != null) newly.add(leg);
        changed = true;
      } else {
        final ko = DateTime.tryParse(leg.utcDate);
        if (ko != null && now.difference(ko).inDays > 14) {
          leg.status = 'void'; // result never arrived
          changed = true;
        }
      }
    }

    if (changed) await _save(legs);
    return newly;
  }

  static SlipSummary summary(List<SlipLeg> legs) {
    var won = 0, lost = 0, pending = 0, voided = 0, noTip = 0;
    for (final l in legs) {
      switch (l.status) {
        case 'won':
          won++;
          break;
        case 'lost':
          lost++;
          break;
        case 'pending':
          pending++;
          break;
        case 'void':
          voided++;
          break;
        default:
          noTip++;
      }
    }
    String status;
    if (lost > 0) {
      status = 'Lost';
    } else if (pending > 0) {
      status = 'Pending';
    } else if (won > 0) {
      status = 'Won';
    } else {
      status = 'Empty';
    }
    return SlipSummary(
      won: won,
      lost: lost,
      pending: pending,
      voided: voided,
      noTip: noTip,
      status: status,
    );
  }
}
