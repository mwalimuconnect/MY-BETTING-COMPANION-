import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixture_model.dart';
import 'pick_evaluator.dart';

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

//=========================
// UI helpers
//=========================

/// Bold teal "PROLIFIC 🔥" section header.
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

  static int? _parsePercent(String raw) {
    final cleaned = raw.replaceAll('%', '').trim();
    return double.tryParse(cleaned)?.round();
  }

  /// Selects a market using league-specific tendencies:
  /// - Bundesliga & Eredivisie: prioritize Over 2.5 and GG (BTTS).
  /// - Premier League (EPL): avoid straight 1X2 unless overwhelming; favor
  ///   Double Chance (1X/X2), GG, or Over 2.5.
  /// - Other leagues: use straight 1X2 only on clear edges (>= 56%),
  ///   otherwise pivot to Double Chance, Over 2.5, or GG.
    static int? _extractOver15Prob(FixtureModel f, int? ov25Prob) {
    try {
      final dynamic dyn = f;
      final raw = dyn.over15Goals;
      if (raw != null) {
        final parsed = _parsePercent(raw.toString());
        if (parsed != null) return parsed;
      }
    } catch (_) {}

    // Fallback estimate from Over 2.5 probability if FixtureModel lacks over15Goals
    if (ov25Prob != null) {
      return (ov25Prob + 24).clamp(50, 92);
    }
    return null;
  }

  /// Selects a market using league-specific tendencies:
  /// - Bundesliga & Eredivisie: prioritize Over 2.5, GG (BTTS), and Over 1.5.
  /// - Premier League (EPL): avoid straight 1X2 unless overwhelming; favor
  ///   Double Chance (1X, X2, 12), Over 1.5, GG, or Over 2.5.
  /// - Other leagues: use straight 1X2 only on clear edges (>= 56%),
  ///   otherwise pivot to Double Chance (1X, X2, 12), Over 1.5, Over 2.5, or GG.
  static ({String tip, int? prob}) _selectLeagueAwareTip(FixtureModel f) {
    final leagueLower = f.league.toLowerCase();
    final isGoalHeavyLeague = leagueLower.contains('bundesliga') ||
        leagueLower.contains('eredivisie');
    final isEpl = leagueLower.contains('premier league') ||
        leagueLower == 'epl' ||
        leagueLower.contains('england - premier');

    final int homeProb = f.homeWinProb.round();
    final int drawProb = f.drawProb.round();
    final int awayProb = f.awayWinProb.round();
    final int? ov25Prob = _parsePercent(f.over25Goals);
    final int? ov15Prob = _extractOver15Prob(f, ov25Prob);
    final int? ggProb = _parsePercent(f.btts);

    final bool homeFav = homeProb >= awayProb;
    final int favWinProb = homeFav ? homeProb : awayProb;
    final String favWinTip = homeFav ? '${f.homeTeam} Win' : '${f.awayTeam} Win';

    // Best Double Chance option across 1X, X2, and 12 (Home or Away)
    final int dc1XProb = (homeProb + drawProb).clamp(0, 95);
    final int dcX2Prob = (awayProb + drawProb).clamp(0, 95);
    final int dc12Prob = (homeProb + awayProb).clamp(0, 95);

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
          (tip: 'GG (Both Teams to Score)', prob: ggProb),
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

  static LogEntry _newEntry(String key, FixtureModel f) {
    final chosen = _selectLeagueAwareTip(f);
    return LogEntry(
      key: key,
      home: f.homeTeam,
      away: f.awayTeam,
      league: f.league,
      tip: chosen.tip,
      tipProb: chosen.prob,
      kickoff: f.timeLabel,
      utcDate: f.utcDate,
      detail: _detailOf(f),
    );
  }

  static void _settle(LogEntry entry, FixtureModel f) {
    final result =
        evaluateTip(entry.tip, entry.home, entry.away, f.actualScore);
    entry.settled = true;
    entry.score = f.actualScore;
    entry.isVoid = result == null;
    entry.won = result;
  }

  /// Records new tips (only before kickoff) and settles finished matches.
  static Future<void> update(List<FixtureModel> fixtures) async {
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
        final bool canRecord = !f.effectiveIsFinished &&
            !f.effectiveIsLive &&
            f.topTip.isNotEmpty &&
            ko != null &&
            ko.toUtc().isAfter(now);
        if (canRecord) {
          final entry = _newEntry(k, f);
          entries.add(entry);
          byKey[k] = entry;
          changed = true;
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
}
