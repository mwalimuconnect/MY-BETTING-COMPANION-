import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixture_model.dart';
import 'notification_service.dart';
import 'pick_evaluator.dart';
import 'slip_generator.dart';

//=========================================================================
// suggested_slip_store.dart
//   1. Shared helpers (rolling window, day keys, write queue)
//   2. SlipLeg / SlipSummary / SlipStore  -> picks bookmarked from Fixtures
//   3. Saved-picks widgets
//   4. SuggestedSlip / SuggestedSlipStore -> the daily system accumulator
//=========================================================================

//=========================================================================
// 1. Shared helpers
//=========================================================================

/// Days of history kept, counting today. Used by both stores and by the
/// "Previous days" cards, so change it in one place.
const int kSlipHistoryDays = 7;

/// Formats a DateTime into YYYY-MM-DD in local time.
String formatLocalDayKey(DateTime dt) {
  final local = dt.toLocal();
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  return '${local.year}-$m-$d';
}

/// Today's local date key (YYYY-MM-DD).
String todayDayKey([DateTime? now]) => formatLocalDayKey(now ?? DateTime.now());

/// Yesterday's local date key (YYYY-MM-DD).
String yesterdayDayKey([DateTime? now]) => formatLocalDayKey(
    (now ?? DateTime.now()).subtract(const Duration(days: 1)));

/// Runs read-modify-write jobs one at a time. Without this, two callers
/// running at once can each read the old data and the last one to write
/// silently drops the other's change.
class _WriteQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() job) {
    final Future<T> result = _tail.then((_) => job());
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }
}

//=========================================================================
// 2. Saved picks: SlipLeg, SlipSummary, SlipStore
//=========================================================================

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

  /// Date string (YYYY-MM-DD) used for grouping by day.
  String get dayKey {
    final dt = DateTime.tryParse(utcDate)?.toLocal() ??
        DateTime.fromMillisecondsSinceEpoch(savedAt).toLocal();
    return formatLocalDayKey(dt);
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

/// Keeps only legs inside the rolling window (today + the days before it).
List<SlipLeg> keepLast7DaysLegs(List<SlipLeg> legs, [DateTime? now]) {
  final current = (now ?? DateTime.now()).toLocal();
  final cutoff = DateTime(current.year, current.month, current.day)
      .subtract(Duration(days: kSlipHistoryDays - 1));
  final cutoffKey = formatLocalDayKey(cutoff);
  return legs.where((leg) => leg.dayKey.compareTo(cutoffKey) >= 0).toList();
}

class SlipStore {
  static const String _prefsKey = 'saved_slips_v1';
  static final _WriteQueue _queue = _WriteQueue();

  static String _matchSignature(String home, String away) =>
      '${home.trim().toLowerCase()} vs ${away.trim().toLowerCase()}';

  // Raw read/write helpers: no queue, used inside queued jobs.
  static Future<List<SlipLeg>> _read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return [
        for (final e in decoded)
          if (e is Map) SlipLeg.fromJson(Map<String, dynamic>.from(e)),
      ];
    } catch (e) {
      debugPrint('Could not load saved slips: $e');
      return [];
    }
  }

  static Future<void> _write(List<SlipLeg> legs) async {
    try {
      final kept = keepLast7DaysLegs(legs);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode(kept.map((l) => l.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('Could not save slips: $e');
    }
  }

  static Future<List<SlipLeg>> load() => _read();

  /// Loads saved slips pruned to the rolling window.
  static Future<List<SlipLeg>> loadLast7Days() {
    return _queue.run(() async {
      final all = await _read();
      final kept = keepLast7DaysLegs(all);
      if (kept.length != all.length) await _write(kept);
      return kept;
    });
  }

  /// Removes any slips older than the rolling window.
  static Future<void> pruneExpiredWeek() {
    return _queue.run(() async => _write(await _read()));
  }

  /// Adds the match to saved slips, or removes it if already saved.
  /// Returns true when the match is now saved.
  static Future<bool> toggle(FixtureModel f) {
    final key = f.key;
    if (key == null) return Future.value(false);

    return _queue.run(() async {
      final legs = keepLast7DaysLegs(await _read());
      final index = legs.indexWhere((l) => l.key == key);
      if (index >= 0) {
        legs.removeAt(index);
        await _write(legs);
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
      await _write(legs);
      return true;
    });
  }

  static Future<void> remove(String key) {
    return _queue.run(() async {
      final legs = await _read();
      legs.removeWhere((l) => l.key == key);
      await _write(legs);
    });
  }

  /// Removes every leg that has a final result (won, lost or void).
  static Future<void> clearSettled() {
    return _queue.run(() async {
      final legs = await _read();
      legs.removeWhere(
          (l) => l.status == 'won' || l.status == 'lost' || l.status == 'void');
      await _write(legs);
    });
  }

  /// Settles pending legs using finished matches. Returns the legs that were
  /// newly won or lost (so the app can tell the user).
  static Future<List<SlipLeg>> settle(List<FixtureModel> fixtures) {
    return _queue.run(() async {
      final legs = keepLast7DaysLegs(await _read());
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
        final f =
            byKey[leg.key] ?? byMatch[_matchSignature(leg.home, leg.away)];

        if (f != null && f.effectiveIsFinished) {
          leg.score = f.actualScore;
          if (leg.tip.trim().isEmpty) {
            leg.status = 'none';
          } else {
            final bool? result =
                f.evaluateMarketOutcome(predictionText: leg.tip) ??
                    evaluatePick(
                      pick: leg.tip,
                      home: leg.home,
                      away: leg.away,
                      score: f.actualScore,
                    );
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

      if (changed) await _write(legs);
      return newly;
    });
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

//=========================================================================
// 3. Saved-picks widgets
//=========================================================================

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
      'DEC',
    ];
    const days = [
      'MONDAY',
      'TUESDAY',
      'WEDNESDAY',
      'THURSDAY',
      'FRIDAY',
      'SATURDAY',
      'SUNDAY',
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
/// Renders today's saved picks at the top and puts previous days (up to the
/// rolling window, starting with yesterday) inside a foldable flap.
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
    ..sort((a, b) => b.key.compareTo(a.key)); // Yesterday first, then older

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
              'PREVIOUS DAYS (UP TO $kSlipHistoryDays DAYS) \u2022 $previousSlipCount',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Color(0xFF008080),
                letterSpacing: 0.8,
              ),
            ),
            subtitle: Text(
              previousDays.isEmpty
                  ? 'No slips from previous days in the last $kSlipHistoryDays days'
                  : 'Tap to unfold days of the week',
            ),
            children: previousDays.map((dayEntry) {
              final day = dayEntry.key;
              final dayLegs = dayEntry.value;
              final prefix = day == yKey ? 'YESTERDAY \u2022 ' : '';

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

/// Renders saved picks grouped per day with bright day/date headers
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
            _buildLegCard(dayLegs[i], i, onDelete),
        ],
      );
    },
  );
}

//=========================================================================
// 4. Daily system slip: SuggestedSlip, SuggestedSlipStore
//    (5-10 combined odds, built automatically from fixtures daily)
//=========================================================================
class SuggestedSlip {
  final String title;
  final double totalOdds;
  final List<Map<String, dynamic>> selections;

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
    final List<Map<String, dynamic>> sel = [];

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

  /// Days of slips to keep, counting today.
  static const int keepDays = kSlipHistoryDays;

  static final _WriteQueue _queue = _WriteQueue();

  static const String note =
      'Odds are model-implied (100 divided by win probability), not bookmaker odds. '
      'Real bookmaker odds will be lower. No slip is guaranteed to win.';

  // ------------------------------------------------------------ date helpers
  /// Today's date as YYYY-MM-DD (phone time).
  static String todayString() => todayDayKey();

  static String yesterdayString() => yesterdayDayKey();

  static String _cutoffDateString() {
    final now = DateTime.now();
    final cutoff = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: keepDays - 1));
    return formatLocalDayKey(cutoff);
  }

  static Map<String, SuggestedSlip> _prune(Map<String, SuggestedSlip> source) {
    final cutoff = _cutoffDateString();
    final entries = source.entries
        .where((e) => e.key.compareTo(cutoff) >= 0)
        .toList()
      ..sort((a, b) => b.key.compareTo(a.key)); // newest day first
    return {for (final e in entries) e.key: e.value};
  }

  // ------------------------------------------------------- history (private)
  static Future<Map<String, SuggestedSlip>> _readHistoryRaw() async {
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
  static Future<Map<String, SuggestedSlip>> loadHistory7Days() {
    return _queue.run(() async {
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
    return _queue.run(() async {
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
    return _queue.run(() async {
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

  /// If the active slip belongs to an EARLIER day, copy it into history.
  /// Safe to call any time (app start, opening the slips tab), so archiving
  /// does not depend on the Fixtures tab having been opened.
  static Future<void> archiveStaleActive() async {
    final existing = await load();
    if (existing != null &&
        existing.date.isNotEmpty &&
        existing.date.compareTo(todayString()) < 0) {
      await saveSlipForHistory(existing);
    }
  }

  /// Saves a custom stake for the active slip and updates history.
  static Future<void> updateStake(double newStake) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final slip = await load();
      if (slip == null) return;
      final updated = slip.copyWith(stake: newStake);
      await prefs.setString(_slipKey, jsonEncode(updated.toJson()));
      // A slip prepared for tomorrow goes into history once its day arrives.
      if (updated.date.compareTo(todayString()) <= 0) {
        await saveSlipForHistory(updated);
      }
    } catch (e) {
      debugPrint('Could not update suggested slip stake: $e');
    }
  }

  /// Builds one slip per day from the latest fixtures, archives it into
  /// history, and sends one notification for it.
  ///
  /// The generator only uses matches that have not started yet, so later in
  /// the day there may be too few left to build today's slip. In that case
  /// tomorrow's slip is prepared instead of showing nothing.
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

      // Archive an earlier day's slip before replacing the active slot.
      await archiveStaleActive();

      // A slip for a coming day was already prepared: keep it.
      if (existing != null && existing.date.compareTo(todayStr) > 0) return;

      final now = DateTime.now();
      String slipDate = todayStr;
      var generated =
          SlipGenerator.generateTargetSlip(fixtures, targetDay: now);
      if (generated == null) {
        final tomorrow = now.add(const Duration(days: 1));
        generated =
            SlipGenerator.generateTargetSlip(fixtures, targetDay: tomorrow);
        slipDate = formatLocalDayKey(tomorrow);
      }

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
        date: slipDate,
      );

      await prefs.setString(_slipKey, jsonEncode(slip.toJson()));
      if (slipDate == todayStr) {
        await saveSlipForHistory(slip);
      }

      if (prefs.getString(_notifiedDayKey) != slipDate) {
        await prefs.setString(_notifiedDayKey, slipDate);
        final String when = slipDate == todayStr ? 'New daily slip' : "Tomorrow's slip";
        await NotificationService.showNow(
          slip.title,
          '$when ready: ${slip.totalOdds.toStringAsFixed(2)}x. Open the Slips tab to view the picks.',
        );
      }
    } catch (e) {
      debugPrint('Suggested slip refresh failed: $e');
    }
  }
}
