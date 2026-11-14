import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'api_service.dart';

int _i(dynamic v) => v is num ? v.toInt() : 0;

class StandingRow {
  final int position;
  final String team;
  final int played;
  final int won;
  final int draw;
  final int lost;
  final int goalsFor;
  final int goalsAgainst;
  final int goalDifference;
  final int yellowCards;
  final int redCards;
  final int points;
  final String form;

  const StandingRow({
    required this.position,
    required this.team,
    required this.played,
    required this.won,
    required this.draw,
    required this.lost,
    required this.goalsFor,
    required this.goalsAgainst,
    required this.goalDifference,
    required this.yellowCards,
    required this.redCards,
    required this.points,
    required this.form,
  });

  factory StandingRow.fromJson(Map<String, dynamic> j) {
    return StandingRow(
      position: _i(j['position']),
      team: j['team']?.toString() ?? '',
      played: _i(j['played']),
      won: _i(j['won']),
      draw: _i(j['draw']),
      lost: _i(j['lost']),
      goalsFor: _i(j['goalsFor']),
      goalsAgainst: _i(j['goalsAgainst']),
      goalDifference: _i(j['goalDifference']),
      yellowCards: _i(j['yellowCards']),
      redCards: _i(j['redCards']),
      points: _i(j['points']),
      form: j['form']?.toString() ?? '',
    );
  }
}

class StandingGroup {
  final String name; // empty for normal leagues, "GROUP A" etc. for tournaments
  final List<StandingRow> rows;

  const StandingGroup({required this.name, required this.rows});
}

class ScorerRow {
  final String name;
  final String team;
  final int goals;
  final int assists;
  final int penalties;
  final int played;

  const ScorerRow({
    required this.name,
    required this.team,
    required this.goals,
    required this.assists,
    required this.penalties,
    required this.played,
  });

  factory ScorerRow.fromJson(Map<String, dynamic> j) {
    return ScorerRow(
      name: j['name']?.toString() ?? '',
      team: j['team']?.toString() ?? '',
      goals: _i(j['goals']),
      assists: _i(j['assists']),
      penalties: _i(j['penalties']),
      played: _i(j['played']),
    );
  }
}

class _Cached {
  final Map<String, dynamic> data;
  final DateTime at;
  _Cached(this.data, this.at);
}

class LeagueApi {
  static final Map<String, _Cached> _cache = {};
  static const Duration _ttl = Duration(minutes: 10);

  static Future<List<StandingGroup>> standings(String code) async {
    final data = await _get('standings', code);
    final groups = data['groups'];
    if (groups is! List) return [];
    final out = <StandingGroup>[];
    for (final g in groups) {
      if (g is! Map) continue;
      final table = g['table'];
      final rows = <StandingRow>[];
      if (table is List) {
        for (final r in table) {
          if (r is Map) rows.add(StandingRow.fromJson(Map<String, dynamic>.from(r)));
        }
      }
      out.add(StandingGroup(name: g['name']?.toString() ?? '', rows: rows));
    }
    return out;
  }

  static Future<List<ScorerRow>> scorers(String code) async {
    final data = await _get('scorers', code);
    final list = data['scorers'];
    if (list is! List) return [];
    final out = <ScorerRow>[];
    for (final s in list) {
      if (s is Map) out.add(ScorerRow.fromJson(Map<String, dynamic>.from(s)));
    }
    return out;
  }

  static Future> _get(String kind, String code) async {
    final cacheKey = '$kind:$code';
    final cached = _cache[cacheKey];
    if (cached != null && DateTime.now().difference(cached.at) < _ttl) {
      return cached.data;
    }

    try {
      final res = await http
          .get(Uri.parse('$kApiBase/api/$kind/$code'))
          .timeout(const Duration(seconds: 60));

      if (res.statusCode == 429 || res.statusCode == 503) {
        throw Exception('Server is busy (rate limit). Try again in a minute.');
      }
      if (res.statusCode == 403) {
        throw Exception('This competition is not available on the free plan.');
      }
      if (res.statusCode != 200) {
        throw Exception('Server returned ${res.statusCode}');
      }

      final decoded = jsonDecode(res.body);
      if (decoded is! Map) throw Exception('Unexpected data from server');
      final data = Map<String, dynamic>.from(decoded);
      _cache[cacheKey] = _Cached(data, DateTime.now());
      return data;
    } on SocketException {
      throw Exception('Cannot reach server. Check internet, VPN or private DNS.');
    } on TimeoutException {
      throw Exception('Server took too long to respond. Try again.');
    } on FormatException {
      throw Exception('Server sent invalid data.');
    }
  }
}
