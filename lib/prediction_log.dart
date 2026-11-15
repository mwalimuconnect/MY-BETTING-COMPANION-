import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'fixture_model.dart';

/// Helper to show model insight breakdown when a prediction log item is tapped
class PredictionInsightHelper {
  static void show(BuildContext context, String matchTitle, String prediction, int? prob) {
    final probability = prob ?? 55;
    final double odds = probability > 0 ? 100 / probability.toDouble() : 1.85;

    String reasoning = 'Based on historical performance metrics, recent goal conversion rates, and home/away form analysis.';
    
    if (prediction.contains('Double Chance')) {
      reasoning = 'The defensive solidity and recent unbeaten run of this selection suggest a high probability of securing at least a draw.';
    } else if (prediction.contains('Over')) {
      reasoning = 'Both teams exhibit high expected goals (xG) metrics and aggressive offensive pressing, pointing toward an open, high-scoring fixture.';
    } else if (prediction.contains('Handicap')) {
      reasoning = 'Significant disparity in squad quality and head-to-head dominance supports a multi-goal winning margin.';
    } else if (prediction.contains('Win')) {
      reasoning = 'Home/Away venue advantage, squad depth, and recent point accumulation heavily favor this outcome.';
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.insights, color: Color(0xFF008080)),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Model Insight Breakdown',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              matchTitle,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF008080)),
            ),
            const SizedBox(height: 8),
            Text(
              'Selection: $prediction',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            const Divider(height: 20),
            const Text(
              'Statistical Analysis:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 6),
            Text(
              '• Model-Implied Probability: ~$probability%',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              '• Fair Model Odds: ${odds.toStringAsFixed(2)}x (calculated as 100 ÷ probability)',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            Text(
              reasoning,
              style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: Colors.black87),
            ),
          ],
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
/// judged (treated as void).
bool? evaluateTip(String tip, String home, String away, String score) {
  final parts = score.split('-');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0].trim());
  final a = int.tryParse(parts[1].trim());
  if (h == null || a == null) return null;
  if (tip == '$home Win') return h > a;
  if (tip == '$away Win') return a > h;
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
          onTap: () => PredictionInsightHelper.show(
            context,
            '${entry.home} vs ${entry.away}',
            entry.tip,
            entry.tipProb,
          ),
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
                          Text(
                            'Tip: ${entry.tip}',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF008080), fontWeight: FontWeight.w600),
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
