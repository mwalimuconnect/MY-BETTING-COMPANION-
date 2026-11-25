import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixture_model.dart';
import 'notification_service.dart';
import 'prediction_log.dart';
import 'slip_generator.dart';

// ===========================================================================
// Saved Slips (User-bookmarked / manually tracked legs, rolling 7-day window)
// ===========================================================================

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

  /// Helper to get the date string (YYYY-MM-DD) for grouping by day.
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

  bool get isWon => status == 'Won';
  bool get isLost => status == 'Lost';
  bool get isSettled => isWon || isLost;
}

/// Formats a DateTime into YYYY-MM-DD in local time.
String formatLocalDayKey(DateTime dt) {
  final local = dt.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}

/// Today's local date key (YYYY-MM-DD).
String todayDayKey([DateTime? now]) => formatLocalDayKey(now ?? DateTime.now());

/// Yesterday's local date key (YYYY-MM-DD).
String yesterdayDayKey([DateTime? now]) =>
    formatLocalDayKey((now ?? DateTime.now()).subtract(const Duration(days: 1)));

/// Keeps only legs within a rolling 7-day window (today + 6 prior days).
List<SlipLeg> keepLast7DaysLegs(List<SlipLeg> legs, [DateTime? now]) {
  final current = (now ?? DateTime.now()).toLocal();
  final cutoff = DateTime(current.year, current.month, current.day)
      .subtract(const Duration(days: 6));
  final cutoffKey = formatLocalDayKey(cutoff);
  return legs.where((leg) => leg.dayKey.compareTo(cutoffKey) >= 0).toList();
}

/// Header widget rendering MY PICKS in bold Teal Green capital letters.
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

/// Bright day and date header formatted purely in standard Dart.
Widget buildBrightDayHeader(String dateStr) {
  final dt = DateTime.tryParse(dateStr);
  String formatted = dateStr;
  if (dt != null) {
    const months = [
      'JAN',
      'FEB',
      'MAR',
      'APR',
      'MAY',
      'JUN',
      'JUL',
      'AUG',
      'SEP',
      'OCT',
      'NOV',
      'DEC'
    ];
    const days = [
      'MONDAY',
      'TUESDAY',
      'WEDNESDAY',
      'THURSDAY',
      'FRIDAY',
      'SATURDAY',
      'SUNDAY'
    ];
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

Widget _statusPill(String label, Color fg, Color bg) {
  return Container(
    margin: const EdgeInsets.only(right: 4),
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: fg),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: fg,
        fontSize: 10,
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}

Widget _buildLegStatusChip(String status) {
  switch (status) {
    case 'won':
      return _statusPill(
        'WON',
        Colors.green.shade400,
        Colors.green.shade900.withOpacity(0.35),
      );
    case 'lost':
      return _statusPill(
        'LOST',
        Colors.red.shade400,
        Colors.red.shade900.withOpacity(0.35),
      );
    case 'void':
      return _statusPill(
        'VOID',
        Colors.amber.shade300,
        Colors.amber.shade900.withOpacity(0.35),
      );
    default:
      return const SizedBox.shrink();
  }
}

Widget _buildLegCard(
  SlipLeg leg,
  int index,
  Function(String key) onDelete,
) {
  return Card(
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
    child: ListTile(
      leading: CircleAvatar(
        backgroundColor: const Color(0xFF008080), // Teal Green badge
        child: Text(
          '${index + 1}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text('${leg.home} vs ${leg.away}'),
      subtitle: Text(
        'Kickoff: ${leg.kickoff.isNotEmpty ? leg.kickoff : "TBD"}\n'
        'Tip: ${leg.tip.isNotEmpty ? leg.tip : "None"} | '
        'Score: ${leg.score.isNotEmpty ? leg.score : "Pending"}',
      ),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildLegStatusChip(leg.status),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            onPressed: () => onDelete(leg.key),
          ),
        ],
      ),
    ),
  );
}

/// Renders today's saved picks at the top and puts previous days (up to 7 days,
/// starting with yesterday) inside a foldable flap that unfolds into days.
Widget buildWeeklySavedSlipsList(
  List<SlipLeg> rawLegs,
  Function(String key) onDelete,
) {
  final legs = keepLast7DaysLegs(rawLegs);
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

  final tKey = todayDayKey();
  final yKey = yesterdayDayKey();

  final Map<String, List<SlipLeg>> grouped = {};
  for (final leg in legs) {
    grouped.putIfAbsent(leg.dayKey, () => []).add(leg);
  }

  final todayLegs = grouped[tKey] ?? const <SlipLeg>[];
  final previousDays = grouped.entries
      .where((entry) => entry.key != tKey)
      .toList()
    ..sort((a, b) => b.key.compareTo(a.key)); // Yesterday first, then older days

  final previousSlipCount = previousDays.fold<int>(
    0,
    (sum, entry) => sum + entry.value.length,
  );

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (todayLegs.isNotEmpty) ...[
        buildBrightDayHeader(tKey),
        for (int i = 0; i < todayLegs.length; i++)
          _buildLegCard(todayLegs[i], i, onDelete),
      ] else
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            'No picks saved for today yet.',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ExpansionTile(
            initiallyExpanded: false,
            iconColor: const Color(0xFF008080),
            collapsedIconColor: const Color(0xFF008080),
            title: Text(
              'PREVIOUS DAYS (UP TO 7 DAYS) • $previousSlipCount',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Color(0xFF008080),
                letterSpacing: 0.8,
              ),
            ),
            subtitle: Text(
              previousDays.isEmpty
                  ? 'No slips from previous days in the last 7 days'
                  : 'Tap to unfold days of the week',
            ),
            children: previousDays.map((dayEntry) {
              final day = dayEntry.key;
              final dayLegs = dayEntry.value;
              final prefix = day == yKey ? 'YESTERDAY • ' : '';

              return ExpansionTile(
                title: Text(
                  '$prefix$day',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text('${dayLegs.length} pick(s)'),
                children: [
                  for (int i = 0; i < dayLegs.length; i++)
                    _buildLegCard(dayLegs[i], i, onDelete),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    ],
  );
}

/// Helper builder to render saved picks grouped per day with bright day/date headers.
Widget buildGroupedSlipList(
    List<SlipLeg> legs, Function(String key) onDelete) {
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

  final Map<String, List<SlipLeg>> grouped = {};
  for (final leg in legs) {
    grouped.putIfAbsent(leg.dayKey, () => []).add(leg);
  }

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
            _buildLegCard(dayLegs[i], i, onDelete),
        ],
      );
    },
  );
}

class SlipStore {
  static const String _prefsKey = 'saved_slips_v1';

  static String _matchSignature(String home, String away) =>
      '${home.trim().toLowerCase()} vs ${away.trim().toLowerCase()}';

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

  /// Loads saved slips pruned to the rolling 7-day window.
  static Future<List<SlipLeg>> loadLast7Days() async {
    final all = await load();
    final kept = keepLast7DaysLegs(all);
    if (kept.length != all.length) {
      await _save(kept);
    }
    return kept;
  }

  static Future<void> _save(List<SlipLeg> legs) async {
    try {
      final kept = keepLast7DaysLegs(legs);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _prefsKey, jsonEncode(kept.map((l) => l.toJson()).toList()));
    } catch (e) {
      debugPrint('Could not save slips: $e');
    }
  }

  /// Removes any slips older than 7 days while preserving the rolling week.
  static Future<void> pruneExpiredWeek() async {
    final legs = await load();
    await _save(legs);
  }

  /// Adds the match to saved slips, or removes it if already saved.
  /// Returns true when the match is now saved.
  static Future<bool> toggle(FixtureModel f) async {
    final key = f.key;
    if (key == null) return false;
    final legs = await loadLast7Days();
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
    final legs = await loadLast7Days();
    final byKey = <String, FixtureModel>{};
    final byMatch = <String, FixtureModel>{};
    for (final f in fixtures) {
      final k = f.key;
      if (k != null && k.isNotEmpty) byKey[k] = f;
      byMatch[_matchSignature(f.homeTeam, f.awayTeam)] = f;
    }

    final now = DateTime.now().toUtc();
    final newly = <SlipLeg>[];
    var changed = false;

    for (final leg in legs) {
      if (leg.status != 'pending') continue;
      final f = byKey[leg.key] ?? byMatch[_matchSignature(leg.home, leg.away)];

      if (f != null && f.effectiveIsFinished) {
        leg.score = f.actualScore;
        if (leg.tip.trim().isEmpty) {
          leg.status = 'none';
        } else {
          final result =
              f.evaluateMarketOutcome(predictionText: leg.tip) ??
                  evaluateTip(leg.tip, leg.home, leg.away, f.actualScore);
          leg.status = result == null ? 'void' : (result ? 'won' : 'lost');
          if (result != null) newly.add(leg);
        }
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

  /// Groups legs by YYYY-MM-DD dayKey and computes each day's SlipSummary.
  static Map<String, SlipSummary> summariesByDay(List<SlipLeg> legs) {
    final grouped = <String, List<SlipLeg>>{};
    for (final leg in legs) {
      grouped.putIfAbsent(leg.dayKey, () => []).add(leg);
    }
    return {
      for (final entry in grouped.entries) entry.key: summary(entry.value),
    };
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

// ===========================================================================
// Suggested Slip (5-10 combined odds), built automatically from fixtures daily
// ===========================================================================

class SuggestedSlip {
  final String title;
  final double totalOdds;
  final List> selections;
  

  final double stake;
  final double potentialPayout;
  final String date;

  /// '' while open, 'won' or 'lost' once settled. Stored so an old slip never
  /// goes back to PENDING after its matches drop out of the fixtures feed.
  final String result;

  const SuggestedSlip({
    required this.title,
    required this.totalOdds,
    required this.selections,
    this.stake = 200.0,
    double? potentialPayout,
    required this.date,
    this.result = '',
  }) : potentialPayout = potentialPayout ?? (totalOdds * stake);

  SuggestedSlip copyWith({double? stake, String? result}) {
    return SuggestedSlip(
      title: title,
      totalOdds: totalOdds,
      selections: selections,
      stake: stake ?? this.stake,
      // A new stake means the payout must be recalculated.
      potentialPayout: stake == null ? potentialPayout : null,
      date: date,
      result: result ?? this.result,
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'totalOdds': totalOdds,
        'selections': selections,
        'stake': stake,
        'potentialPayout': potentialPayout,
        'date': date,
        'result': result,
      };

  factory SuggestedSlip.fromJson(Map<String, dynamic> j) {
    final List> sel = [];

    final raw = j['selections'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          sel.add(Map<String, dynamic>.from(e));
        }
      }
    }
    final double odds =
        j['totalOdds'] is num ? (j['totalOdds'] as num).toDouble() : 0;
    final double parsedStake =
        j['stake'] is num ? (j['stake'] as num).toDouble() : 200.0;
    final double parsedPayout = j['potentialPayout'] is num
        ? (j['potentialPayout'] as num).toDouble()
        : (odds * parsedStake);

    return SuggestedSlip(
      title: j['title']?.toString() ?? 'Suggested slip',
      totalOdds: odds,
      selections: sel,
      stake: parsedStake,
      potentialPayout: parsedPayout,
      date: j['date']?.toString() ?? SuggestedSlipStore.todayString(),
      result: j['result']?.toString() ?? '',
    );
  }
}

class SuggestedSlipStore {
  static const String _slipKey = 'suggested_slip_v2';
  static const String _historyKey = 'suggested_slip_history_7d_v1';
  static const String _notifiedDayKey = 'suggested_slip_notified_day';

  /// Days of slips to keep, counting today. The "Previous 7 days" card reads
  /// from this, so change both together.
  static const int keepDays = 7;

  static const String note =
      'Odds are model-implied (100 divided by win probability), not bookmaker odds. '
      'Real bookmaker odds will be lower. No slip is guaranteed to win.';

  // ------------------------------------------------------------- date helpers
  static String _dayString(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Today's date as YYYY-MM-DD (phone time).
  static String todayString() => _dayString(DateTime.now());

  static String yesterdayString() =>
      _dayString(DateTime.now().subtract(const Duration(days: 1)));

  static String _cutoffDateString() {
    final now = DateTime.now();
    final cutoff = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: keepDays - 1));
    return _dayString(cutoff);
  }

  static Map<String, SuggestedSlip> _prune(Map<String, SuggestedSlip> source) {
    final cutoff = _cutoffDateString();
    final entries = source.entries
        .where((e) => e.key.compareTo(cutoff) >= 0)
        .toList()
      ..sort((a, b) => b.key.compareTo(a.key)); // newest day first
    return {for (final e in entries) e.key: e.value};
  }

  // ------------------------------------------------------------ write queue
  // Every history read-modify-write goes through this queue. Without it, two
  // callers running at once (startup archive + Fixtures refresh, say) can each
  // read the old map and the last one to write silently drops the other's slip.
  static Future<void> _lock = Future<void>.value();

  static Future<T> _serial<T>(Future<T> Function() job) {
    final Future<T> run = _lock.then((_) => job());
    _lock = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  // ------------------------------------------------------- history (private)
  static Future> _readHistoryRaw() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_historyKey);
    if (raw == null || raw.isEmpty) return {};
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return {};

    final map = <String, SuggestedSlip>{};
    decoded.forEach((key, value) {
      if (value is Map) {
        map[key.toString()] =
            SuggestedSlip.fromJson(Map<String, dynamic>.from(value));
      }
    });
    return map;
  }

  static Future<void> _writeHistory(Map<String, SuggestedSlip> map) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _historyKey,
      jsonEncode({for (final e in map.entries) e.key: e.value.toJson()}),
    );
  }

  // -------------------------------------------------------- history (public)
  static Future> loadHistory7Days() {
    return _serial(() async {
      try {
        final pruned = _prune(await _readHistoryRaw());
        await _writeHistory(pruned);
        return pruned;
      } catch (e) {
        debugPrint('Could not load suggested slip history: $e');
        return <String, SuggestedSlip>{};
      }
    });
  }

  static Future<void> saveSlipForHistory(SuggestedSlip slip) {
    return _serial(() async {
      try {
        final history = await _readHistoryRaw();
        final key = slip.date.isNotEmpty ? slip.date : todayString();

        // Re-saving the active slip must not wipe a result already stored.
        final old = history[key];
        history[key] =
            (slip.result.isEmpty && old != null && old.result.isNotEmpty)
                ? slip.copyWith(result: old.result)
                : slip;

        await _writeHistory(_prune(history));
      } catch (e) {
        debugPrint('Could not save slip to history: $e');
      }
    });
  }

  /// Stores the final result of a past slip so it keeps WON / LOST for good.
  static Future<void> saveResult(String date, bool won) {
    return _serial(() async {
      try {
        final history = await _readHistoryRaw();
        final slip = history[date];
        if (slip == null) return;
        history[date] = slip.copyWith(result: won ? 'won' : 'lost');
        await _writeHistory(_prune(history));
      } catch (e) {
        debugPrint('Could not save slip result: $e');
      }
    });
  }

  // ------------------------------------------------------------ active slip
  static Future<SuggestedSlip?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_slipKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return SuggestedSlip.fromJson(Map<String, dynamic>.from(decoded));
    } catch (e) {
      debugPrint('Could not load suggested slip: $e');
      return null;
    }
  }

  /// If the active slip belongs to an earlier day, copy it into history.
  /// Safe to call any time (app start, opening the slips tab), so archiving no
  /// longer depends on the Fixtures tab having been opened.
  static Future<void> archiveStaleActive() async {
    final existing = await load();
    if (existing != null &&
        existing.date.isNotEmpty &&
        existing.date != todayString()) {
      await saveSlipForHistory(existing);
    }
  }

  /// Saves a custom stake for today's active slip and updates history.
  static Future<void> updateStake(double newStake) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final slip = await load();
      if (slip == null) return;
      final updated = slip.copyWith(stake: newStake);
      await prefs.setString(_slipKey, jsonEncode(updated.toJson()));
      await saveSlipForHistory(updated);
    } catch (e) {
      debugPrint('Could not update suggested slip stake: $e');
    }
  }

  /// Builds one slip per day from the latest fixtures, archives it into
  /// history, and sends one notification for it.
  static Future<void> refresh(List<FixtureModel> fixtures) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final todayStr = todayString();
      final existing = await load();

      // Today's slip already exists: keep it and make sure it is in history.
      if (existing != null && existing.date == todayStr) {
        await saveSlipForHistory(existing);
        return;
      }

      // Archive the earlier day's slip before replacing the active slot.
      await archiveStaleActive();

      final generated = SlipGenerator.generateTargetSlip(fixtures);
      if (generated == null) {
        if (existing != null) await prefs.remove(_slipKey);
        return;
      }

      final slip = SuggestedSlip(
        title: generated.title,
        totalOdds: generated.totalOdds,
        selections: [
          for (final s in generated.selections)
            Map<String, dynamic>.from(s as Map),
        ],
        date: todayStr,
      );

      await prefs.setString(_slipKey, jsonEncode(slip.toJson()));
      await saveSlipForHistory(slip);

      if (prefs.getString(_notifiedDayKey) != todayStr) {
        await prefs.setString(_notifiedDayKey, todayStr);
        await NotificationService.showNow(
          slip.title,
          'New daily slip ready: ${slip.totalOdds.toStringAsFixed(2)}x. Open the Slips tab to view the picks.',
        );
      }
    } catch (e) {
      debugPrint('Suggested slip refresh failed: $e');
    }
  }
}
