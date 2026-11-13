import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'fixture_model.dart';

class LogEntry {
  final String id, league, home, away, kickoff, tip, loggedAt;
  final double odds;
  String? score; // final score once settled
  bool? won; // null while pending or void
  bool isVoid; // tip type not recognised, excluded from stats

  LogEntry({
    required this.id,
    required this.league,
    required this.home,
    required this.away,
    required this.kickoff,
    required this.tip,
    required this.odds,
    required this.loggedAt,
    this.score,
    this.won,
    this.isVoid = false,
  });

  bool get settled => score != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'league': league,
        'home': home,
        'away': away,
        'kickoff': kickoff,
        'tip': tip,
        'odds': odds,
        'loggedAt': loggedAt,
        'score': score,
        'won': won,
        'isVoid': isVoid,
      };

  factory LogEntry.fromJson(Map<String, dynamic> j) => LogEntry(
        id: j['id'] as String,
        league: j['league'] as String,
        home: j['home'] as String,
        away: j['away'] as String,
        kickoff: j['kickoff'] as String,
        tip: j['tip'] as String,
        odds: (j['odds'] as num).toDouble(),
        loggedAt: j['loggedAt'] as String,
        score: j['score'] as String?,
        won: j['won'] as bool?,
        isVoid: j['isVoid'] == true,
      );
}

class LogStats {
  final int total, pending, voided, settled, wins;
  final double hitRate, breakEven, profit;
  const LogStats(this.total, this.pending, this.voided, this.settled, this.wins,
      this.hitRate, this.breakEven, this.profit);
}

class PredictionLog {
  static const _prefsKey = 'prediction_log_v1';

  static Future<List<LogEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((e) => LogEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _save(List<LogEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _prefsKey, jsonEncode(entries.map((e) => e.toJson()).toList()));
  }

  static final RegExp _scoreRe = RegExp(r'^\s*(\d+)\s*-\s*(\d+)\s*$');

  /// true = tip won, false = lost, null = tip type not recognised.
  static bool? _evaluate(String tip, String home, String away, int h, int a) {
    final t = tip.toLowerCase().trim();
    final hn = home.toLowerCase();
    final an = away.toLowerCase();
    if (t.contains('both teams to score')) return h > 0 && a > 0;
    if (t.endsWith('win or draw')) {
      if (t.startsWith(hn)) return h >= a;
      if (t.startsWith(an)) return a >= h;
    } else if (t.endsWith(' win')) {
      if (t.startsWith(hn)) return h > a;
      if (t.startsWith(an)) return a > h;
    }
    return null;
  }

  /// Call after every successful fetch.
  /// Upcoming matches get logged once; finished matches settle their entry.
  static Future<void> update(List<FixtureModel> fixtures) async {
    final entries = await load();
    final pending = <String, LogEntry>{
      for (final e in entries)
        if (!e.settled) e.id: e,
    };
    var changed = false;

    for (final f in fixtures) {
      final id = '${f.homeTeam}|${f.awayTeam}';
      final isUpcoming = !f.isLive && !f.isFinished;

      if (isUpcoming && !pending.containsKey(id) && f.topTip.isNotEmpty) {
        final e = LogEntry(
          id: id,
          league: f.league,
          home: f.homeTeam,
          away: f.awayTeam,
          kickoff: f.time,
          tip: f.topTip,
          odds: f.odds,
          loggedAt: DateTime.now().toIso8601String(),
        );
        entries.add(e);
        pending[id] = e;
        changed = true;
      } else if (f.isFinished && pending.containsKey(id)) {
        final m = _scoreRe.firstMatch(f.actualScore);
        if (m == null) continue; // score not available yet, stay pending
        final e = pending.remove(id)!;
        final h = int.parse(m.group(1)!);
        final a = int.parse(m.group(2)!);
        e.score = '$h-$a';
        final result = _evaluate(e.tip, e.home, e.away, h, a);
        if (result == null) {
          e.isVoid = true;
        } else {
          e.won = result;
        }
        changed = true;
      }
    }

    if (changed) await _save(entries);
  }

  static LogStats stats(List<LogEntry> entries) {
    final pending = entries.where((e) => !e.settled).length;
    final voided = entries.where((e) => e.settled && e.isVoid).length;
    final done = entries.where((e) => e.settled && !e.isVoid && e.won != null).toList();
    final wins = done.where((e) => e.won == true).length;
    final n = done.length;
    final hit = n == 0 ? 0.0 : wins / n;
    final breakEven =
        n == 0 ? 0.0 : done.map((e) => 1 / e.odds).reduce((a, b) => a + b) / n;
    final profit = done.fold<double>(
        0, (sum, e) => sum + (e.won == true ? e.odds - 1 : -1));
    return LogStats(entries.length, pending, voided, n, wins, hit, breakEven, profit);
  }
}
