import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_service.dart';
import 'app_settings.dart';
import 'fixture_model.dart';
import 'pick_evaluator.dart';
import 'slip_generator.dart' show SlipGenerator;
import 'suggested_slip_store.dart'
    show WriteQueue, formatLocalDayKey, todayDayKey;

const Color _teal = Color(0xFF008080);
const Color _safaricomGreen = Color(0xFF3AA335);

//=========================
// Insight dialog
//=========================

/// Dialog shown when a logged prediction is tapped. It only states things the
/// app really knows: the tip, its confidence, the data saved when the tip was
/// made, and the result. It does not invent match-specific reasons.
class PredictionInsightHelper {
  static void show(
    BuildContext context,
    String matchTitle,
    String prediction,
    int? prob, {
    String league = '',
    String kickoff = '',
    String status = '',
    String score = '',
    String detail = '',
  }) {
    final int? confidence = (prob != null && prob > 0) ? prob : null;
    final double? fairOdds = confidence == null ? null : 100 / confidence;

    Widget heading(String text) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text(
            text,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: _teal,
              letterSpacing: 0.5,
            ),
          ),
        );

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.insights, color: _teal),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Why this prediction',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                matchTitle,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: _teal,
                ),
              ),
              if (league.isNotEmpty || kickoff.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    [league, kickoff].where((t) => t.isNotEmpty).join('  |  '),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'Selection: $prediction',
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              heading('WHAT THE MODEL SAID'),
              Text(
                confidence != null
                    ? 'Confidence: $confidence%'
                    : 'Confidence was not recorded for this tip.',
                style: const TextStyle(fontSize: 13),
              ),
              if (fairOdds != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Model odds: ${fairOdds.toStringAsFixed(2)} '
                    '(100 divided by the confidence). '
                    'These are not bookmaker odds.',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              if (detail.isNotEmpty) ...[
                heading('DATA BEHIND IT (SAVED WHEN THE TIP WAS MADE)'),
                Text(detail,
                    style: const TextStyle(fontSize: 13, height: 1.35)),
              ],
              if (status.isNotEmpty) ...[
                heading('RESULT'),
                Text(
                  score.isNotEmpty ? '$status (final score $score)' : status,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
              heading('HOW IT IS CALCULATED'),
              const Text(
                'The model counts the goals each team has scored and conceded '
                'in this season\'s finished matches in the same competition, '
                'adjusts for home advantage, and pulls small samples toward '
                'the league average. It then simulates the possible scorelines '
                'to get win, draw and goals chances. It does not know about '
                'injuries, suspensions, lineups or bookmaker odds, and no tip '
                'is guaranteed.',
                style: TextStyle(fontSize: 12, height: 1.4, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _teal,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

//=========================
// Tip evaluation
//=========================

/// Kept so existing call sites keep working. The logic lives in
/// pick_evaluator.dart and is shared with the slip generator.
bool? evaluateTip(String tip, String home, String away, String score) =>
    evaluatePick(pick: tip, home: home, away: away, score: score);

//=========================
// Models
//=========================
class LogEntry {
  final String key;
  final String home;
  final String away;
  final String league;
  final String tip;
  final int? tipProb;
  final String kickoff; // label shown in the list
  final String utcDate;
  final String detail; // summary of the data behind the tip
  bool settled;
  bool isVoid;
  bool? won;
  String score;

  LogEntry({
    required this.key,
    required this.home,
    required this.away,
    required this.league,
    required this.tip,
    required this.kickoff,
    required this.utcDate,
    this.tipProb,
    this.detail = '',
    this.settled = false,
    this.isVoid = false,
    this.won,
    this.score = '',
  });

  String get statusText {
    if (!settled) return 'Pending';
    if (isVoid) return 'Void';
    return won == true ? 'Won' : 'Lost';
  }

  Color get statusColor {
    if (!settled) return Colors.orange;
    if (isVoid) return Colors.grey;
    return won == true ? _safaricomGreen : Colors.red;
  }

  Map<String, dynamic> toJson() => {
        'key': key,
        'home': home,
        'away': away,
        'league': league,
        'tip': tip,
        'tipProb': tipProb,
        'kickoff': kickoff,
        'utcDate': utcDate,
        'detail': detail,
        'settled': settled,
        'isVoid': isVoid,
        'won': won,
        'score': score,
      };

  factory LogEntry.fromJson(Map<String, dynamic> j) {
    return LogEntry(
      key: j['key']?.toString() ?? '',
      home: j['home']?.toString() ?? '',
      away: j['away']?.toString() ?? '',
      league: j['league']?.toString() ?? '',
      tip: j['tip']?.toString() ?? '',
      tipProb: j['tipProb'] is num ? (j['tipProb'] as num).toInt() : null,
      kickoff: j['kickoff']?.toString() ?? '',
      utcDate: j['utcDate']?.toString() ?? '',
      detail: j['detail']?.toString() ?? '',
      settled: j['settled'] == true,
      isVoid: j['isVoid'] == true,
      won: j['won'] is bool ? j['won'] as bool : null,
      score: j['score']?.toString() ?? '',
    );
  }
}

class LogStats {
  final int total;
  final int pending;
  final int voided;
  final int settled; // settled and not void
  final int wins;

  const LogStats({
    required this.total,
    required this.pending,
    required this.voided,
    required this.settled,
    required this.wins,
  });

  double get hitRate => settled == 0 ? 0 : wins / settled;
}

class LeagueStats {
  final String league;
  final int settled;
  final int wins;

  const LeagueStats({
    required this.league,
    required this.settled,
    required this.wins,
  });

  double get hitRate => settled == 0 ? 0 : wins / settled;
}

/// Hit rate per market (Double Chance, Over 1.5, GG, ...).
class MarketStats {
  final String market;
  final int settled;
  final int wins;

  const MarketStats({
    required this.market,
    required this.settled,
    required this.wins,
  });

  double get hitRate => settled == 0 ? 0 : wins / settled;
}

/// Compares what the model claimed with what actually happened.
class CalibrationStats {
  final int count; // settled tips that had a confidence recorded
  final double avgConfidence; // average claimed confidence, 0-100
  final double hitRate; // actual win rate, 0-1

  const CalibrationStats({
    required this.count,
    required this.avgConfidence,
    required this.hitRate,
  });

  /// Actual minus claimed, in percentage points. Negative = overconfident.
  double get gap => hitRate * 100 - avgConfidence;
}

//=========================
// UI helpers
//=========================

/// Bold teal PROLIFIC section header (with the fire emoji).
Widget buildProlificHeader() {
  return const Padding(
    padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Text(
      'PROLIFIC \u{1F525}',
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: _teal,
        letterSpacing: 1.2,
      ),
    ),
  );
}

/// Opens the insight dialog for a logged prediction.
void showLogEntryInsight(BuildContext context, LogEntry entry) {
  PredictionInsightHelper.show(
    context,
    '${entry.home} vs ${entry.away}',
    entry.tip,
    entry.tipProb,
    league: entry.league,
    kickoff: entry.kickoff,
    status: entry.statusText,
    score: entry.score,
    detail: entry.detail,
  );
}

String _dayBucketLabel(String utcDate) {
  final dt = DateTime.tryParse(utcDate)?.toLocal();
  if (dt == null) return 'Scheduled';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(dt.year, dt.month, dt.day);
  final diff = target.difference(today).inDays;

  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

/// Renders logged predictions grouped by Today / Tomorrow; tapping opens insight.
Widget buildPredictionLogList(List<LogEntry> entries) {
  if (entries.isEmpty) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Text(
        'No prediction logs found.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.grey),
      ),
    );
  }

  final sorted = List<LogEntry>.from(entries)
    ..sort((a, b) {
      final da = DateTime.tryParse(a.utcDate);
      final db = DateTime.tryParse(b.utcDate);
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });

  return ListView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    itemCount: sorted.length,
    itemBuilder: (context, index) {
      final entry = sorted[index];
      final currentLabel = _dayBucketLabel(entry.utcDate);
      final prevLabel =
          index > 0 ? _dayBucketLabel(sorted[index - 1].utcDate) : null;
      final showHeader = index == 0 || currentLabel != prevLabel;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeader)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                currentLabel.toUpperCase(),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                  color: _teal,
                ),
              ),
            ),
          _LogEntryCard(entry: entry),
        ],
      );
    },
  );
}

class _LogEntryCard extends StatelessWidget {
  final LogEntry entry;

  const _LogEntryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => showLogEntryInsight(context, entry),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${entry.home} vs ${entry.away}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Tip: ${entry.tip}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: _teal,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.info_outline,
                            size: 12, color: Colors.grey),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.kickoff.isNotEmpty
                          ? '${entry.league}  |  ${entry.kickoff}'
                          : 'League: ${entry.league}',
                      style:
                          const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              Chip(
                label: Text(
                  entry.statusText,
                  style: const TextStyle(color: Colors.white, fontSize: 10),
                ),
                backgroundColor: entry.statusColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

//=========================
// PredictionLog storage
//=========================
class PredictionLog {
  static const String _prefsKey = 'prediction_log_v2';
  static const int _maxEntries = 500;
  static const int _voidAfterDays = 14;
  static final WriteQueue _queue = WriteQueue();

  static Future<List<LogEntry>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return [
        for (final e in decoded)
          if (e is Map) LogEntry.fromJson(Map<String, dynamic>.from(e)),
      ];
    } catch (e) {
      debugPrint('Could not load prediction log: $e');
      return [];
    }
  }

  static Future<void> _save(List<LogEntry> entries) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode(entries.map((e) => e.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('Could not save prediction log: $e');
    }
  }

  static int _formPoints(List<String> form) {
    var total = 0;
    for (final r in form) {
      if (r == 'W') {
        total += 3;
      } else if (r == 'D') {
        total += 1;
      }
    }
    return total;
  }

  /// Selects a market using league-specific tendencies:
  /// - Bundesliga & Eredivisie: prioritize Over 2.5, GG (BTTS), and Over 1.5.
  /// - Premier League (EPL): avoid straight 1X2 unless overwhelming; favor
  ///   Double Chance (1X, X2, 12), Over 1.5, GG, or Over 2.5.
  /// - Other leagues: use straight 1X2 only on clear edges (>= 56%),
  ///   otherwise pivot to Double Chance (1X, X2, 12), Over 1.5, Over 2.5, or GG.
  static ({String tip, int? prob}) _selectLeagueAwareTip(FixtureModel f) {
    // Same league names and probability estimates as the slip generator.
    final league = SlipGenerator.normalizeLeague(f.league);
    final isGoalHeavyLeague = league == 'Bundesliga' || league == 'Eredivisie';
    final isEpl = league == 'Premier League';

    final int homeProb = f.homeWinProb.round();
    final int drawProb = f.drawProb.round();
    final int awayProb = f.awayWinProb.round();
    final int? ov25Prob = SlipGenerator.percent(f.over25Goals)?.round();
    final int? ov15Prob = SlipGenerator.estimateOver15(f)?.round();
    final int? ggProb = SlipGenerator.percent(f.btts)?.round();

    final bool homeFav = homeProb >= awayProb;
    final int favWinProb = homeFav ? homeProb : awayProb;
    final String favWinTip =
        homeFav ? '${f.homeTeam} Win' : '${f.awayTeam} Win';

    // Best Double Chance option across 1X, X2, and 12 (Home or Away)
    final int dc1XProb = (homeProb + drawProb).clamp(0, 95).toInt();
    final int dcX2Prob = (awayProb + drawProb).clamp(0, 95).toInt();
    final int dc12Prob = (homeProb + awayProb).clamp(0, 95).toInt();

    final dcCandidates = <({String tip, int prob})>[
      (tip: 'Double Chance (1X)', prob: dc1XProb),
      (tip: 'Double Chance (X2)', prob: dcX2Prob),
      if (drawProb <= 24) (tip: 'Double Chance (12)', prob: dc12Prob),
    ]..sort((a, b) => b.prob.compareTo(a.prob));

    final bestDc = dcCandidates.first;

    // Pick strongest primary goals market (Over 2.5 vs GG)
    ({String tip, int prob})? bestGoalsPick(int minThreshold) {
      final candidates = <({String tip, int prob})>[
        if (ov25Prob != null && ov25Prob >= minThreshold)
          (tip: 'Over 2.5 Goals', prob: ov25Prob),
        if (ggProb != null && ggProb >= minThreshold)
          (tip: 'GG', prob: ggProb),
      ];
      if (candidates.isEmpty) return null;
      candidates.sort((a, b) => b.prob.compareTo(a.prob));
      return candidates.first;
    }

    if (f.hasPrediction) {
      // 1. Bundesliga & Eredivisie -> favor Over 2.5, GG, or safe Over 1.5
      if (isGoalHeavyLeague) {
        final goalPick = bestGoalsPick(54);
        if (goalPick != null) {
          return (tip: goalPick.tip, prob: goalPick.prob);
        }
        if (ov15Prob != null && ov15Prob >= 72) {
          return (tip: 'Over 1.5 Goals', prob: ov15Prob);
        }
        if (favWinProb >= 62) {
          return (tip: favWinTip, prob: favWinProb);
        }
        return (tip: bestDc.tip, prob: bestDc.prob);
      }

      // 2. Premier League (EPL) -> avoid risky 1X2; prefer DC / GG / Over 2.5 / Over 1.5
      if (isEpl) {
        if (favWinProb >= 68) {
          return (tip: favWinTip, prob: favWinProb);
        }
        final goalPick = bestGoalsPick(58);
        if (goalPick != null && goalPick.prob >= bestDc.prob - 8) {
          return (tip: goalPick.tip, prob: goalPick.prob);
        }
        if (ov15Prob != null && ov15Prob >= 76 && ov15Prob >= bestDc.prob) {
          return (tip: 'Over 1.5 Goals', prob: ov15Prob);
        }
        return (tip: bestDc.tip, prob: bestDc.prob);
      }

      // 3. All other leagues (Championship, La Liga, Serie A, etc.)
      if (favWinProb >= 56) {
        return (tip: favWinTip, prob: favWinProb);
      }
      final goalPick = bestGoalsPick(58);
      if (goalPick != null && goalPick.prob >= bestDc.prob - 6) {
        return (tip: goalPick.tip, prob: goalPick.prob);
      }
      if (ov15Prob != null && ov15Prob >= 76 && ov15Prob >= bestDc.prob) {
        return (tip: 'Over 1.5 Goals', prob: ov15Prob);
      }
      if (bestDc.prob >= 65) {
        return (tip: bestDc.tip, prob: bestDc.prob);
      }
    }

    return (tip: f.topTip, prob: f.tipProbInt);
  }

  /// The tip the Prolific log records for this match. Other screens can call
  /// this to show exactly the same tip.
  static ({String tip, int? prob}) tipFor(FixtureModel f) =>
      _selectLeagueAwareTip(f);

  /// A short, factual summary of the data the tip was based on.
  static String _detailOf(FixtureModel f) {
    final parts = <String>[];
    if (f.hasPrediction) {
      parts.add(
        'Chances: ${f.homeTeam} ${f.homeWinProb.round()}%, '
        'draw ${f.drawProb.round()}%, '
        '${f.awayTeam} ${f.awayWinProb.round()}%.',
      );
    }
    if (f.homeForm.isNotEmpty && f.awayForm.isNotEmpty) {
      parts.add(
        'Form (last ${f.homeForm.length}): '
        '${f.homeTeam} ${_formPoints(f.homeForm)} points, '
        '${f.awayTeam} ${_formPoints(f.awayForm)} points.',
      );
    }
    if (f.over25Goals != 'N/A') {
      parts.add(
          'Over 2.5 goals ${f.over25Goals}, both teams to score ${f.btts}.');
    }
    return parts.join(' ');
  }

  static LogEntry _newEntry(
    String key,
    FixtureModel f,
    ({String tip, int? prob}) chosen,
  ) {
    final String effectiveUtc = f.utcDate.trim().isNotEmpty
        ? f.utcDate.trim()
        : (f.kickoff?.toUtc().toIso8601String() ?? '');

    return LogEntry(
      key: key,
      home: f.homeTeam,
      away: f.awayTeam,
      league: f.league,
      tip: chosen.tip,
      tipProb: chosen.prob,
      kickoff: f.timeLabel,
      utcDate: effectiveUtc,
      detail: _detailOf(f),
    );
  }

  static void _settle(LogEntry entry, FixtureModel f) {
    // Shared evaluator first; the model's own evaluator covers markets the
    // shared one can't judge from the score alone.
    final bool? result =
        evaluateTip(entry.tip, entry.home, entry.away, f.actualScore) ??
            f.evaluateMarketOutcome(predictionText: entry.tip);
    entry.settled = true;
    entry.score = f.actualScore;
    entry.isVoid = result == null;
    entry.won = result;
  }

  /// Records new tips (only before kickoff) and settles finished matches.
  static Future<void> update(List<FixtureModel> fixtures) =>
      _queue.run(() => _update(fixtures));

  static Future<void> _update(List<FixtureModel> fixtures) async {
    final entries = await load();
    final byKey = {for (final e in entries) e.key: e};
    final now = DateTime.now().toUtc();
    var changed = false;

    for (final f in fixtures) {
      final k = f.key;
      if (k == null || k.isEmpty) continue;
      final existing = byKey[k];

      if (existing == null) {
        final ko = f.kickoff;
        final bool upcoming = !f.effectiveIsFinished &&
            !f.effectiveIsLive &&
            ko != null &&
            ko.toUtc().isAfter(now);
        if (upcoming) {
          // Judge by the tip that will actually be logged. The league-aware
          // picker can produce a tip even when topTip is empty.
          final chosen = _selectLeagueAwareTip(f);
          if (chosen.tip.trim().isNotEmpty) {
            final entry = _newEntry(k, f, chosen);
            entries.add(entry);
            byKey[k] = entry;
            changed = true;
          }
        }
      } else if (!existing.settled &&
          f.effectiveIsFinished &&
          f.actualScore.trim().isNotEmpty) {
        _settle(existing, f);
        changed = true;
      }
    }

    // Tips whose result never arrived are marked void.
    for (final e in entries) {
      if (e.settled) continue;
      final ko = DateTime.tryParse(e.utcDate);
      if (ko != null && now.difference(ko.toUtc()).inDays > _voidAfterDays) {
        e.settled = true;
        e.isVoid = true;
        changed = true;
      }
    }

    if (entries.length > _maxEntries) {
      entries.removeRange(0, entries.length - _maxEntries);
      changed = true;
    }

    if (changed) await _save(entries);
  }

  // ------------------------------------------------------------------ stats
  static LogStats stats(List<LogEntry> entries) {
    var pending = 0;
    var voided = 0;
    var settled = 0;
    var wins = 0;
    for (final e in entries) {
      if (!e.settled) {
        pending++;
      } else if (e.isVoid) {
        voided++;
      } else {
        settled++;
        if (e.won == true) wins++;
      }
    }
    return LogStats(
      total: entries.length,
      pending: pending,
      voided: voided,
      settled: settled,
      wins: wins,
    );
  }

  /// Hit rate per competition (only competitions with settled tips).
  static List<LeagueStats> byLeague(List<LogEntry> entries) {
    final settledCount = <String, int>{};
    final winCount = <String, int>{};
    for (final e in entries) {
      if (!e.settled || e.isVoid) continue;
      settledCount[e.league] = (settledCount[e.league] ?? 0) + 1;
      if (e.won == true) winCount[e.league] = (winCount[e.league] ?? 0) + 1;
    }
    final out = [
      for (final entry in settledCount.entries)
        LeagueStats(
          league: entry.key,
          settled: entry.value,
          wins: winCount[entry.key] ?? 0,
        ),
    ];
    out.sort((a, b) => b.settled.compareTo(a.settled));
    return out;
  }

  /// Names the market a tip belongs to, for the per-market breakdown.
  static String marketOf(String tip) {
    final t = tip.trim().toLowerCase();
    final compact = t.replaceAll(RegExp(r'\s+'), '');

    if (t.contains('double chance') ||
        t.contains('(1x)') ||
        t.contains('(x2)') ||
        t.contains('(12)') ||
        RegExp(r'^(1x|x2|12)\b').hasMatch(t)) {
      return 'Double Chance';
    }
    final over = RegExp(r'over(\d\.\d)').firstMatch(compact);
    if (over != null) return 'Over ${over.group(1)}';
    final under = RegExp(r'under(\d\.\d)').firstMatch(compact);
    if (under != null) return 'Under ${under.group(1)}';

    if (t == 'ng' ||
        t.contains('btts no') ||
        t.contains('btts: no') ||
        t.contains('both teams to score: no')) {
      return 'NG';
    }
    if (t == 'gg' || t.contains('btts') || t.contains('both teams to score')) {
      return 'GG';
    }
    if (t.contains(' win') ||
        t == '1' ||
        t == '2' ||
        t == 'x' ||
        t == 'draw' ||
        t == 'home' ||
        t == 'away') {
      return '1X2';
    }
    return 'Other';
  }

  /// Hit rate per market (only markets with settled tips).
  static List<MarketStats> byMarket(List<LogEntry> entries) {
    final settledCount = <String, int>{};
    final winCount = <String, int>{};
    for (final e in entries) {
      if (!e.settled || e.isVoid) continue;
      final m = marketOf(e.tip);
      settledCount[m] = (settledCount[m] ?? 0) + 1;
      if (e.won == true) winCount[m] = (winCount[m] ?? 0) + 1;
    }
    final out = [
      for (final entry in settledCount.entries)
        MarketStats(
          market: entry.key,
          settled: entry.value,
          wins: winCount[entry.key] ?? 0,
        ),
    ];
    out.sort((a, b) => b.settled.compareTo(a.settled));
    return out;
  }

  /// Claimed confidence vs actual hit rate for tips whose confidence falls in
  /// [minProb, maxProb]. Null when there are no settled tips in that range.
  /// A big negative gap means the model is overconfident there.
  static CalibrationStats? calibration(
    List<LogEntry> entries, {
    int minProb = 0,
    int maxProb = 100,
  }) {
    var count = 0;
    var wins = 0;
    var sum = 0.0;
    for (final e in entries) {
      final p = e.tipProb;
      if (!e.settled || e.isVoid || p == null) continue;
      if (p < minProb || p > maxProb) continue;
      count++;
      sum += p;
      if (e.won == true) wins++;
    }
    if (count == 0) return null;
    return CalibrationStats(
      count: count,
      avgConfidence: sum / count,
      hitRate: wins / count,
    );
  }

  // ----------------------------------------------------------------- backup
  /// The whole log as JSON text, for adding to Export Backup.
  static Future<String> exportJson() async {
    final entries = await load();
    return jsonEncode(entries.map((e) => e.toJson()).toList());
  }

  /// Merges a backup made by [exportJson] into the current log. New tips are
  /// added, and tips that were still pending here are settled from the backup.
  /// Returns how many tips were added or settled.
  static Future<int> importJson(String raw) =>
      _queue.run(() => _importJson(raw));

  static Future<int> _importJson(String raw) async {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return 0;

      final entries = await load();
      final byKey = {for (final e in entries) e.key: e};
      var touched = 0;

      for (final item in decoded) {
        if (item is! Map) continue;
        final incoming = LogEntry.fromJson(Map<String, dynamic>.from(item));
        if (incoming.key.isEmpty) continue;

        final existing = byKey[incoming.key];
        if (existing == null) {
          entries.add(incoming);
          byKey[incoming.key] = incoming;
          touched++;
        } else if (!existing.settled && incoming.settled) {
          existing.settled = true;
          existing.isVoid = incoming.isVoid;
          existing.won = incoming.won;
          existing.score = incoming.score;
          touched++;
        }
      }

      if (touched > 0) {
        // Keep oldest first so the 500-entry trim drops the oldest tips.
        entries.sort((a, b) => a.utcDate.compareTo(b.utcDate));
        await _save(entries);
      }
      return touched;
    } catch (e) {
      debugPrint('Could not import prediction log: $e');
      return 0;
    }
  }
}

//=========================================================================
// PROLIFIC SCREEN (tab, history page and breakdown card)
// Everything below is the UI; everything above is data and logic.
//=========================================================================

//=========================================================================
// Shared helpers
//=========================================================================
const List<String> _weekdayNames = [
  'MONDAY',
  'TUESDAY',
  'WEDNESDAY',
  'THURSDAY',
  'FRIDAY',
  'SATURDAY',
  'SUNDAY',
];

const List<String> _monthNames = [
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

/// Real kickoff time. LogEntry.kickoff is only a display label, so days must
/// be built from the ISO timestamp in utcDate.
DateTime? _kickoffOf(LogEntry e) => DateTime.tryParse(e.utcDate)?.toLocal();

String _dayKeyOf(LogEntry e) {
  final dt = _kickoffOf(e);
  return dt == null ? 'unknown' : formatLocalDayKey(dt);
}

/// "TODAY", "TOMORROW", "YESTERDAY" or '' for other days.
String _relativePrefix(String dayKey) {
  final dt = DateTime.tryParse(dayKey);
  if (dt == null) return '';
  final now = DateTime.now();
  // UTC midnights so a daylight-saving change can't shift the day count.
  final today = DateTime.utc(now.year, now.month, now.day);
  final target = DateTime.utc(dt.year, dt.month, dt.day);
  final diff = target.difference(today).inDays;
  if (diff == 0) return 'TODAY';
  if (diff == 1) return 'TOMORROW';
  if (diff == -1) return 'YESTERDAY';
  return '';
}

/// e.g. "TODAY \u2022 MONDAY, 30 NOV" or "MONDAY, 23 NOV 2026".
String _dayTitle(String dayKey, {bool withYear = false}) {
  final dt = DateTime.tryParse(dayKey);
  if (dt == null) return 'DATE UNKNOWN';
  final date = '${_weekdayNames[dt.weekday - 1]}, ${dt.day} '
      '${_monthNames[dt.month - 1]}${withYear ? ' ${dt.year}' : ''}';
  final prefix = _relativePrefix(dayKey);
  return prefix.isEmpty ? date : '$prefix \u2022 $date';
}

String _daySummary(List<LogEntry> list) {
  final s = PredictionLog.stats(list);
  if (s.settled == 0) {
    return s.pending > 0 ? '${s.pending} pending' : '${list.length} tips';
  }
  final parts = <String>['${s.wins}W', '${s.settled - s.wins}L'];
  if (s.pending > 0) parts.add('${s.pending} pending');
  return parts.join(' \u2022 ');
}

Map<String, List<LogEntry>> _groupByDay(List<LogEntry> entries) {
  final grouped = <String, List<LogEntry>>{};
  for (final e in entries) {
    grouped.putIfAbsent(_dayKeyOf(e), () => []).add(e);
  }
  // Inside a day: earliest kickoff first.
  for (final list in grouped.values) {
    list.sort((a, b) {
      final ka = _kickoffOf(a);
      final kb = _kickoffOf(b);
      if (ka == null && kb == null) return 0;
      if (ka == null) return 1;
      if (kb == null) return -1;
      return ka.compareTo(kb);
    });
  }
  return grouped;
}

Widget _statItem(String label, String value) {
  return Column(
    children: [
      Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      const SizedBox(height: 4),
      Text(
        value,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    ],
  );
}

Widget _statsCard(BuildContext context, List<LogEntry> entries) {
  final stats = PredictionLog.stats(entries);
  return Card(
    color: cardBg(context),
    child: Padding(
      padding: const EdgeInsets.all(12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statItem('Total', '${stats.total}'),
          _statItem('Settled', '${stats.settled}'),
          _statItem('Wins', '${stats.wins}'),
          _statItem(
            'Hit Rate',
            '${(stats.hitRate * 100).toStringAsFixed(1)}%',
          ),
        ],
      ),
    ),
  );
}

Widget _statusChip(LogEntry entry) {
  if (!entry.settled) {
    return const Chip(
      label: Text(
        'Pending',
        style: TextStyle(
          fontSize: 10,
          color: Colors.black87,
          fontWeight: FontWeight.w600,
        ),
      ),
      backgroundColor: Colors.amberAccent,
    );
  }
  if (entry.isVoid) {
    return const Chip(
      label: Text('Void', style: TextStyle(fontSize: 10)),
      backgroundColor: Colors.grey,
    );
  }
  return Chip(
    label: Text(
      entry.won == true ? 'Won' : 'Lost',
      style: const TextStyle(fontSize: 10, color: Colors.white),
    ),
    backgroundColor: entry.won == true ? _safaricomGreen : Colors.red,
  );
}

class _PredictionEntryCard extends StatelessWidget {
  final LogEntry entry;

  const _PredictionEntryCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Card(
      color: cardBg(context),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: () => showLogEntryInsight(context, entry),
        title: Text('${entry.home} vs ${entry.away}'),
        subtitle: Text(
          '${entry.kickoff.isNotEmpty ? '${entry.kickoff}\n' : ''}'
          'Tip: ${entry.tip} | League: ${entry.league}',
        ),
        trailing: _statusChip(entry),
      ),
    );
  }
}

//=========================================================================
// PROLIFIC tab: today and coming days, grouped per day
//=========================================================================
class PredictionLogTab extends StatefulWidget {
  const PredictionLogTab({super.key});

  @override
  State<PredictionLogTab> createState() => _PredictionLogTabState();
}

class _PredictionLogTabState extends State<PredictionLogTab> {
  late Future<List<LogEntry>> _logFuture;

  @override
  void initState() {
    super.initState();
    _loadLog();
  }

  List<LogEntry>? _cached;
  Future<void>? _syncFuture;

  void _loadLog() {
    setState(() {
      _logFuture = PredictionLog.load();
    });
    _syncInBackground();
  }

  /// Pulls fresh fixtures, records new tips and settles finished ones, so this
  /// tab stays current even if the Fixtures tab was never opened.
  Future<void> _syncInBackground() {
    return _syncFuture ??= _runSync().whenComplete(() => _syncFuture = null);
  }

  Future<void> _runSync() async {
    try {
      final fixtures = await ApiService.fetchFixtures();
      await PredictionLog.update(fixtures);
      if (!mounted) return;
      setState(() {
        _logFuture = PredictionLog.load();
      });
    } catch (e) {
      debugPrint('Prolific background sync failed: $e');
    }
  }

  /// Splits tips into today-and-later vs earlier days (and unknown dates).
  ({List<LogEntry> current, List<LogEntry> past}) _split(List<LogEntry> all) {
    final todayKey = todayDayKey();
    final current = <LogEntry>[];
    final past = <LogEntry>[];
    for (final e in all) {
      final k = _dayKeyOf(e);
      if (k != 'unknown' && k.compareTo(todayKey) >= 0) {
        current.add(e);
      } else {
        past.add(e);
      }
    }
    return (current: current, past: past);
  }

  void _openHistory(List<LogEntry> past) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PredictionHistoryScreen(entries: past),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<LogEntry>>(
      future: _logFuture,
      builder: (context, snapshot) {
        // Keep showing the last tips while a refresh runs (no spinner flash).
        if (snapshot.hasData) _cached = snapshot.data;
        final all = snapshot.data ?? _cached ?? const <LogEntry>[];
        final loading =
            snapshot.connectionState == ConnectionState.waiting &&
                _cached == null;
        final parts = _split(all);

        Widget body;
        if (loading) {
          body = const Center(child: CircularProgressIndicator());
        } else if (all.isEmpty) {
          body =
              const Center(child: Text('No prediction history recorded yet.'));
        } else {
          body = _buildBody(all, parts.current);
        }

        return Column(
          children: [
            _buildHeader(parts.past),
            Expanded(child: body),
          ],
        );
      },
    );
  }

  Widget _buildHeader(List<LogEntry> past) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 4),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'PROLIFIC \u{1F525}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _teal,
                letterSpacing: 1.2,
              ),
            ),
          ),
          // Banner in the top-right corner that opens the previous results.
          Material(
            color: _teal.withOpacity(0.14),
            shape: const StadiumBorder(
              side: BorderSide(color: _teal, width: 1),
            ),
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: () => _openHistory(past),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.history, size: 16, color: _teal),
                    const SizedBox(width: 5),
                    Text(
                      past.isEmpty ? 'History' : 'History (${past.length})',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _teal,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(List<LogEntry> all, List<LogEntry> current) {
    final grouped = _groupByDay(current);
    // Today first, then tomorrow, then later days.
    final days = grouped.keys.toList()..sort();

    final rows = <Object>[];
    for (final d in days) {
      rows.add(d);
      rows.addAll(grouped[d]!);
    }

    return RefreshIndicator(
      onRefresh: () async {
        _loadLog();
        await _syncInBackground();
      },
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
        // +1 for the stats card, +1 for the empty message when needed
        itemCount: rows.length + 1 + (rows.isEmpty ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 4),
              child: _statsCard(context, all),
            );
          }
          if (rows.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No tips for today or the coming days yet.\n'
                'Tap History to see your previous results.',
                textAlign: TextAlign.center,
                style: TextStyle(color: mutedText(context)),
              ),
            );
          }

          final row = rows[index - 1];
          if (row is String) {
            return _dayHeader(row, grouped[row]!);
          }
          return _PredictionEntryCard(entry: row as LogEntry);
        },
      ),
    );
  }

  Widget _dayHeader(String dayKey, List<LogEntry> list) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _dayTitle(dayKey),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
                color: Colors.amber,
              ),
            ),
          ),
          Text(
            _daySummary(list),
            style: TextStyle(fontSize: 11, color: mutedText(context)),
          ),
        ],
      ),
    );
  }
}

//=========================================================================
// History screen: every earlier day, newest first, plus a performance
// breakdown
//=========================================================================
class PredictionHistoryScreen extends StatelessWidget {
  final List<LogEntry> entries; // earlier days only

  const PredictionHistoryScreen({super.key, required this.entries});

  @override
  Widget build(BuildContext context) {
    final grouped = _groupByDay(entries);
    // Newest day first; unknown dates last.
    final days = grouped.keys.toList()
      ..sort((a, b) {
        if (a == 'unknown') return 1;
        if (b == 'unknown') return -1;
        return b.compareTo(a);
      });

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Previous results',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
      ),
      body: entries.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No previous results yet.\n'
                  'Tips move here automatically once their day has passed.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: mutedText(context)),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                _statsCard(context, entries),
                const SizedBox(height: 4),
                _BreakdownCard(entries: entries),
                const SizedBox(height: 8),
                for (int i = 0; i < days.length; i++)
                  _buildDayTile(context, days[i], grouped[days[i]]!, i == 0),
              ],
            ),
    );
  }

  Widget _buildDayTile(
    BuildContext context,
    String dayKey,
    List<LogEntry> list,
    bool expanded,
  ) {
    return Card(
      color: cardBg(context),
      margin: const EdgeInsets.only(bottom: 10),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey('history_$dayKey'),
          initiallyExpanded: expanded,
          iconColor: _teal,
          collapsedIconColor: _teal,
          title: Text(
            _dayTitle(dayKey, withYear: true),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: _teal,
              letterSpacing: 0.6,
            ),
          ),
          subtitle: Text(_daySummary(list)),
          childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          children: [
            for (final e in list) _PredictionEntryCard(entry: e),
          ],
        ),
      ),
    );
  }
}

//=========================================================================
// Performance breakdown: by market, by league, and a confidence check
//=========================================================================
class _BreakdownCard extends StatelessWidget {
  final List<LogEntry> entries;

  const _BreakdownCard({required this.entries});

  Color _pctColor(double pct) {
    if (pct >= 60) return _safaricomGreen;
    if (pct < 50) return Colors.red;
    return Colors.orange;
  }

  Widget _row(String label, int settled, int wins) {
    final pct = settled == 0 ? 0.0 : wins / settled * 100;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          Text('$wins/$settled', style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 12),
          SizedBox(
            width: 44,
            child: Text(
              '${pct.toStringAsFixed(0)}%',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: _pctColor(pct),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _title(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: _teal,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _confidenceRow(BuildContext context, String label, CalibrationStats? c) {
    if (c == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Text(
        '$label: claimed ${c.avgConfidence.toStringAsFixed(0)}%, '
        'won ${(c.hitRate * 100).toStringAsFixed(0)}% (${c.count} tips)',
        style: TextStyle(fontSize: 12, color: mutedText(context)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final markets = PredictionLog.byMarket(entries);
    final leagues = PredictionLog.byLeague(entries).take(8).toList();
    final overall = PredictionLog.calibration(entries);

    if (markets.isEmpty && leagues.isEmpty) {
      return const SizedBox.shrink();
    }

    String verdict = '';
    if (overall != null) {
      if (overall.count < 10) {
        verdict = 'Too few settled tips yet for a reliable reading.';
      } else if (overall.gap < -10) {
        verdict = 'The model claims more than it delivers. '
            'Treat its tips with extra caution.';
      } else if (overall.gap > 10) {
        verdict = 'The model is doing better than it claims.';
      } else {
        verdict = 'Claimed confidence and real results are close.';
      }
    }

    return Card(
      color: cardBg(context),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          iconColor: _teal,
          collapsedIconColor: _teal,
          title: const Text(
            'PERFORMANCE BREAKDOWN',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: _teal,
              letterSpacing: 0.8,
            ),
          ),
          subtitle: const Text('By market, league and confidence'),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (markets.isNotEmpty) ...[
              _title('BY MARKET'),
              for (final m in markets) _row(m.market, m.settled, m.wins),
            ],
            if (leagues.isNotEmpty) ...[
              _title('BY LEAGUE'),
              for (final l in leagues) _row(l.league, l.settled, l.wins),
            ],
            if (overall != null) ...[
              _title('CONFIDENCE CHECK'),
              _confidenceRow(context, 'All tips', overall),
              _confidenceRow(context, 'Below 65%',
                  PredictionLog.calibration(entries, maxProb: 64)),
              _confidenceRow(context, '65% to 74%',
                  PredictionLog.calibration(entries, minProb: 65, maxProb: 74)),
              _confidenceRow(context, '75% and above',
                  PredictionLog.calibration(entries, minProb: 75)),
              const SizedBox(height: 6),
              Text(
                verdict,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
