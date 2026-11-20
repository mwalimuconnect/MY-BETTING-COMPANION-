import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'fixture_model.dart';

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
              color: Color(0xFF008080),
              letterSpacing: 0.5,
            ),
          ),
        );

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.insights, color: Color(0xFF008080)),
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
                    fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF008080)),
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
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
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
                    'Model odds: ${fairOdds.toStringAsFixed(2)} (100 divided by the confidence). These are not bookmaker odds.',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),

              if (detail.isNotEmpty) ...[
                heading('DATA BEHIND IT (SAVED WHEN THE TIP WAS MADE)'),
                Text(detail, style: const TextStyle(fontSize: 13, height: 1.35)),
              ],

              if (status.isNotEmpty) ...[
                heading('RESULT'),
                Text(
                  score.isNotEmpty ? '$status (final score $score)' : status,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],

              heading('HOW IT IS CALCULATED'),
              const Text(
                'The model counts the goals each team has scored and conceded in this season\'s '
                'finished matches in the same competition, adjusts for home advantage, and '
                'pulls small samples toward the league average. It then simulates the possible '
                'scorelines to get win, draw and goals chances. It does not know about injuries, '
                'suspensions, lineups or bookmaker odds, and no tip is guaranteed.',
                style: TextStyle(fontSize: 12, height: 1.4, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF008080),
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

/// Returns true if the tip won, false if it lost, or null if it cannot be
/// judged from final score alone (treated as void).
bool? evaluateTip(String tip, String home, String away, String score) {
  final parts = score.split('-');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0].trim());
  final a = int.tryParse(parts[1].trim());
  if (h == null || a == null) return null;
  final normalizedTip = tip.trim();
  final lowerTip = normalizedTip.toLowerCase();
  final compactTip = lowerTip.replaceAll(RegExp(r'\s+'), '');
  final totalGoals = h + a;

  if (lowerTip.contains('most goals') ||
      lowerTip.contains('card') ||
      lowerTip.contains('scorer')) {
    return null;
  }

  if (normalizedTip == '$home Win') return h > a;
  if (normalizedTip == '$away Win') return a > h;
  if (normalizedTip == 'Draw') return h == a;

  if (normalizedTip == 'Double Chance: $home or Draw (1X)' ||
      normalizedTip.endsWith('(1X)')) {
    return h >= a;
  }
  if (normalizedTip == 'Double Chance: Draw or $away (X2)' ||
      normalizedTip.endsWith('(X2)')) {
    return a >= h;
  }

  if (normalizedTip == 'Over 1.5 Goals') return totalGoals >= 2;
  if (normalizedTip == 'Over 2.5 Goals') return totalGoals >= 3;
  if (normalizedTip == 'Under 3.5 Goals') return totalGoals <= 3;

  if (normalizedTip == 'Both Teams To Score: Yes') return h > 0 && a > 0;
  if (normalizedTip == 'Both Teams To Score: No') return h == 0 || a == 0;

  if (lowerTip == '1' || lowerTip == 'home') return h > a;
  if (lowerTip == '2' || lowerTip == 'away') return a > h;
  if (lowerTip == 'x') return h == a;
  if (lowerTip == '12' || lowerTip == 'home or away') return h != a;

  if (lowerTip == 'gg' || lowerTip == 'btts' || lowerTip == 'btts yes') {
    return h > 0 && a > 0;
  }
  if (lowerTip == 'ng' || lowerTip == 'btts no' || lowerTip == 'no gg') {
    return h == 0 || a == 0;
  }

  if (compactTip.contains('un1.5') || compactTip.contains('under1.5')) {
    return totalGoals < 2;
  }
  if (lowerTip.contains('over 1.5') || compactTip.contains('ov1.5')) {
    return totalGoals >= 2;
  }
  if (compactTip.contains('un2.5') || compactTip.contains('under2.5')) {
    return totalGoals < 3;
  }
  if (lowerTip.contains('over 2.5') || compactTip.contains('ov2.5')) {
    return totalGoals >= 3;
  }
  if (compactTip.contains('un3.5') || compactTip.contains('under3.5')) {
    return totalGoals <= 3;
  }

  final RegExpMatch? scoreTipMatch =
      RegExp(r'\b(\d+)\s*-\s*(\d+)\b').firstMatch(lowerTip);
  if (scoreTipMatch != null) {
    final int? tipH = int.tryParse(scoreTipMatch.group(1)!);
    final int? tipA = int.tryParse(scoreTipMatch.group(2)!);
    if (tipH != null && tipA != null) {
      return h == tipH && a == tipA;
    }
  }
  
  return null;
}
  /// Helper widget to render the PROLIFIC \u{1F525} header in bold Teal Green capital letters
  Widget buildProlificHeader() {
  return const Padding(
    padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Text(
      'PROLIFIC \u{1F525}',
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Color(0xFF008080), // Teal Green
        letterSpacing: 1.2,
      ),
    ),
  );
}

String _statusTextOf(LogEntry entry) {
  if (!entry.settled) return 'Pending';
  if (entry.isVoid) return 'Void';
  return entry.won == true ? 'Won' : 'Lost';
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
    status: _statusTextOf(entry),
    score: entry.score,
    detail: entry.detail,
  );
}

/// Helper builder to render your logged prediction items cleanly with tap-to-inspect insights
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

  return ListView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    itemCount: entries.length,
    itemBuilder: (context, index) {
      final entry = entries[index];

      Color statusColor = Colors.orange;
      String statusText = 'Pending';
      if (entry.settled) {
        if (entry.isVoid) {
          statusColor = Colors.grey;
          statusText = 'Void';
        } else if (entry.won == true) {
          statusColor = Colors.green;
          statusText = 'Won';
        } else {
          statusColor = Colors.red;
          statusText = 'Lost';
        }
      }

      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          // Tapping any logged prediction opens its insight breakdown dialog
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
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'Tip: ${entry.tip}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF008080),
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.info_outline, size: 12, color: Colors.grey),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'League: ${entry.league}',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                Chip(
                  label: Text(
                    statusText,
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                  backgroundColor: statusColor,
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

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

class PredictionLog {
  static const String _prefsKey = 'prediction_log_v2';
  static const int _maxEntries = 500;

  static Future<List<LogEntry>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final out = <LogEntry>[];
      for (final e in decoded) {
        if (e is Map) out.add(LogEntry.fromJson(Map<String, dynamic>.from(e)));
      }
      return out;
    } catch (e) {
      debugPrint('Could not load prediction log: $e');
      return [];
    }
  }

  static Future<void> _save(List<LogEntry> entries) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _prefsKey, jsonEncode(entries.map((e) => e.toJson()).toList()));
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

  /// A short, factual summary of the data the tip was based on.
  static String _detailOf(FixtureModel f) {
    final parts = <String>[];
    if (f.hasPrediction) {
      parts.add(
          'Chances: ${f.homeTeam} ${f.homeWinProb.round()}%, draw ${f.drawProb.round()}%, ${f.awayTeam} ${f.awayWinProb.round()}%.');
    }
    if (f.homeForm.isNotEmpty && f.awayForm.isNotEmpty) {
      parts.add(
          'Form (last ${f.homeForm.length}): ${f.homeTeam} ${_formPoints(f.homeForm)} points, '
          '${f.awayTeam} ${_formPoints(f.awayForm)} points.');
    }
    if (f.over25Goals != 'N/A') {
      parts.add('Over 2.5 goals ${f.over25Goals}, both teams to score ${f.btts}.');
    }
    return parts.join(' ');
  }

  /// Records new tips (only before kickoff) and settles finished matches.
  static Future<void> update(List<FixtureModel> fixtures) async {
    final entries = await load();
    final byKey = <String, LogEntry>{};
    for (final e in entries) {
      byKey[e.key] = e;
    }
    final now = DateTime.now().toUtc();
    var changed = false;

    for (final f in fixtures) {
      final k = f.key;
      if (k == null || k.isEmpty) continue;
      final existing = byKey[k];

      if (existing == null) {
        final ko = f.kickoff;
        if (!f.isFinished &&
            !f.isLive &&
            f.topTip.isNotEmpty &&
            ko != null &&
            ko.isAfter(now)) {
          final entry = LogEntry(
            key: k,
            home: f.homeTeam,
            away: f.awayTeam,
            league: f.league,
            tip: f.topTip,
            tipProb: f.tipProbInt,
            kickoff: f.timeLabel,
            utcDate: f.utcDate,
            detail: _detailOf(f),
          );
          entries.add(entry);
          byKey[k] = entry;
          changed = true;
        }
      } else if (!existing.settled && f.isFinished) {
        final result =
            evaluateTip(existing.tip, existing.home, existing.away, f.actualScore);
        existing.settled = true;
        existing.score = f.actualScore;
        if (result == null) {
          existing.isVoid = true;
          existing.won = null;
        } else {
          existing.won = result;
        }
        changed = true;
      }
    }

    // Tips whose result never arrived (older than 14 days) are marked void.
    for (final e in entries) {
      if (!e.settled) {
        final ko = DateTime.tryParse(e.utcDate);
        if (ko != null && now.difference(ko).inDays > 14) {
          e.settled = true;
          e.isVoid = true;
          changed = true;
        }
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
    final out = <LeagueStats>[];
    settledCount.forEach((league, n) {
      out.add(LeagueStats(league: league, settled: n, wins: winCount[league] ?? 0));
    });
    out.sort((a, b) => b.settled.compareTo(a.settled));
    return out;
  }
}
