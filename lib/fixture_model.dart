import 'package:flutter/material.dart';

class H2HEntry {
  final String date;
  final String home;
  final String away;
  final String score;

  const H2HEntry({
    required this.date,
    required this.home,
    required this.away,
    required this.score,
  });

  factory H2HEntry.fromJson(Map<String, dynamic> json) {
    return H2HEntry(
      date: json['date']?.toString() ?? '',
      home: json['home']?.toString() ?? '',
      away: json['away']?.toString() ?? '',
      score: json['score']?.toString() ?? '',
    );
  }
}

class PlayerScorerTip {
  final String name;
  final String team;
  final double goalProb;
  final double odds;

  const PlayerScorerTip({
    required this.name,
    required this.team,
    required this.goalProb,
    this.odds = 0.0,
  });

  factory PlayerScorerTip.fromJson(Map<String, dynamic> json) {
    final double prob = FixtureModel._d(
      json['goalProb'] ?? json['prob'] ?? json['probability'],
      0.0,
    );
    final double rawOdds = FixtureModel._d(json['odds'], 0.0);
    return PlayerScorerTip(
      name: json['name']?.toString() ?? json['player']?.toString() ?? '',
      team: json['team']?.toString() ?? '',
      goalProb: prob,
      odds: rawOdds > 0 ? rawOdds : (prob > 0 ? (100 / prob) : 0.0),
    );
  }
}

class FixtureModel {
  final String? key;
  final String homeTeam;
  final String awayTeam;
  final DateTime? kickoff;
  final DateTime? time; // Alias for kickoff required by UI
  final bool isLive;
  final bool isFinished;
  double odds; // 0 = no real bookmaker odds available (mutable so live odds can be mapped)
  final String prediction; // same as topTip
  final String league;

  // UI properties
  final bool hasPrediction;
  final String topTip; // empty when the model has no clear tip
  final double tipProb; // 0 when there is no tip
  final double homeWinProb;
  final double drawProb;
  final double awayWinProb;

  // Extra data from the server (all optional)
  final String utcDate; // ISO kickoff time (UTC)
  final String competitionCode;
  final String dateLabel; // e.g. "Thu 19 Nov"
  final String kickoffTime; // e.g. "01:30 EAT"
  final String actualScore; // e.g. "2-1", or "Pending"
  final List<String> homeForm;
  final List<String> awayForm;
  final List<H2HEntry> h2h;
  final String over25Goals;
  final String btts;
  final String cardRisk;
  final bool isProlific;
  final bool isSample;
  final bool isEstimate;
  final bool? predictionCorrect;
  bool isSaved;

  // Extended market fields (parsed if sent by backend, otherwise null/empty)
  final String over15Goals;
  final String under35Goals;
  final double? firstHalfGoalsProb;
  final double? secondHalfGoalsProb;
  final double? homeCardsProb;
  final double? drawCardsProb;
  final double? awayCardsProb;
  final double? firstHalfCardsProb;
  final double? secondHalfCardsProb;
  final List<PlayerScorerTip> anytimeScorers;

  FixtureModel({
    required this.key,
    required this.homeTeam,
    required this.awayTeam,
    required this.kickoff,
    required this.time,
    required this.isLive,
    required this.isFinished,
    required this.odds,
    required this.prediction,
    required this.league,
    required this.hasPrediction,
    required this.topTip,
    required this.tipProb,
    required this.homeWinProb,
    required this.drawProb,
    required this.awayWinProb,
    this.utcDate = '',
    this.competitionCode = '',
    this.dateLabel = '',
    this.kickoffTime = '',
    this.actualScore = 'Pending',
    this.homeForm = const [],
    this.awayForm = const [],
    this.h2h = const [],
    this.over25Goals = 'N/A',
    this.btts = 'N/A',
    this.cardRisk = 'N/A',
    this.isProlific = false,
    this.isSample = false,
    this.isEstimate = false,
    this.predictionCorrect,
    this.isSaved = false,
    this.over15Goals = 'N/A',
    this.under35Goals = 'N/A',
    this.firstHalfGoalsProb,
    this.secondHalfGoalsProb,
    this.homeCardsProb,
    this.drawCardsProb,
    this.awayCardsProb,
    this.firstHalfCardsProb,
    this.secondHalfCardsProb,
    this.anytimeScorers = const [],
  });

  /// Text such as "Thu 19 Nov, 01:30 EAT" (empty if the server sent no date).
  String get timeLabel {
    if (dateLabel.isEmpty) return kickoffTime;
    if (kickoffTime.isEmpty) return dateLabel;
    return '$dateLabel, $kickoffTime';
  }

  /// Tip confidence as a whole number, or null when there is no tip.
  int? get tipProbInt => tipProb > 0 ? tipProb.round() : null;

  // Convenience filters for UI
  bool get isUpcoming => !isLive && !isFinished;
  bool get isLiveMatch => isLive;
  bool get isFinishedMatch => isFinished;

  static double _d(dynamic v, double fallback) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.replaceAll('%', '').trim()) ?? fallback;
    return fallback;
  }

  static double? _dOpt(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.replaceAll('%', '').trim());
    return null;
  }

  static List<String> _list(dynamic v) {
    if (v is List) return v.map((e) => e.toString()).toList();
    return <String>[];
  }

  static List<H2HEntry> _h2h(dynamic v) {
    if (v is! List) return const [];
    final out = <H2HEntry>[];
    for (final e in v) {
      if (e is Map) out.add(H2HEntry.fromJson(Map<String, dynamic>.from(e)));
    }
    return out;
  }

  static List<PlayerScorerTip> _scorers(dynamic v) {
    if (v is! List) return const [];
    final out = <PlayerScorerTip>[];
    for (final e in v) {
      if (e is Map) {
        final tip = PlayerScorerTip.fromJson(Map<String, dynamic>.from(e));
        if (tip.name.isNotEmpty) out.add(tip);
      }
    }
    return out;
  }

  factory FixtureModel.fromJson(Map<String, dynamic> j) {
    final String utc = j['utcDate']?.toString() ?? '';

    DateTime? parsedTime = DateTime.tryParse(utc);
    parsedTime ??= j['kickoff'] != null ? DateTime.tryParse(j['kickoff'].toString()) : null;

    final String tip = j['topTip']?.toString() ?? j['prediction']?.toString() ?? '';
    final double home = _d(j['homeWinProb'], 0);
    final double draw = _d(j['drawProb'], 0);
    final double away = _d(j['awayWinProb'], 0);

    return FixtureModel(
      key: j['key']?.toString() ?? j['id']?.toString(),
      homeTeam: j['homeTeam']?.toString() ?? 'Home',
      awayTeam: j['awayTeam']?.toString() ?? 'Away',
      kickoff: parsedTime,
      time: parsedTime,
      isLive: j['isLive'] == true,
      isFinished: j['isFinished'] == true,
      odds: _d(j['odds'], 0),
      prediction: tip,
      league: j['league']?.toString() ?? 'General League',
      hasPrediction: (home + draw + away) > 0,
      topTip: tip,
      tipProb: _d(j['tipProb'], 0),
      homeWinProb: home,
      drawProb: draw,
      awayWinProb: away,
      utcDate: utc,
      competitionCode: j['competitionCode']?.toString() ?? '',
      dateLabel: j['dateLabel']?.toString() ?? '',
      kickoffTime: j['kickoffTime']?.toString() ?? '',
      actualScore: j['actualScore']?.toString() ?? 'Pending',
      homeForm: _list(j['homeForm']),
      awayForm: _list(j['awayForm']),
      h2h: _h2h(j['h2h']),
      over25Goals: j['over25Goals']?.toString() ?? 'N/A',
      btts: j['btts']?.toString() ?? 'N/A',
      cardRisk: j['cardRisk']?.toString() ?? 'N/A',
      isProlific: j['isProlific'] == true,
      isSample: j['isSample'] == true,
      isEstimate: j['isEstimate'] == true,
      predictionCorrect:
          j['predictionCorrect'] is bool ? j['predictionCorrect'] as bool : null,
      over15Goals: j['over15Goals']?.toString() ?? 'N/A',
      under35Goals: j['under35Goals']?.toString() ?? 'N/A',
      firstHalfGoalsProb: _dOpt(j['firstHalfGoalsProb']),
      secondHalfGoalsProb: _dOpt(j['secondHalfGoalsProb']),
      homeCardsProb: _dOpt(j['homeCardsProb']),
      drawCardsProb: _dOpt(j['drawCardsProb']),
      awayCardsProb: _dOpt(j['awayCardsProb']),
      firstHalfCardsProb: _dOpt(j['firstHalfCardsProb']),
      secondHalfCardsProb: _dOpt(j['secondHalfCardsProb']),
      anytimeScorers: _scorers(j['anytimeScorers']),
    );
  }

  /// Global filter helper method supporting status tabs and text search (teams & competitions)
  static List<FixtureModel> filterFixtures(List<FixtureModel> fixtures, String filter, {String searchQuery = ''}) {
    final statusQuery = filter.toLowerCase();
    var filtered = fixtures.where((f) {
      if (statusQuery == 'upcoming') return f.isUpcoming;
      if (statusQuery == 'live') return f.isLiveMatch;
      if (statusQuery == 'finished') return f.isFinishedMatch;
      return true;
    }).toList();

    final textQuery = searchQuery.toLowerCase().trim();
    if (textQuery.isNotEmpty) {
      filtered = filtered.where((f) {
        return f.homeTeam.toLowerCase().contains(textQuery) ||
            f.awayTeam.toLowerCase().contains(textQuery) ||
            f.league.toLowerCase().contains(textQuery) ||
            f.competitionCode.toLowerCase().contains(textQuery);
      }).toList();
    }

    return filtered;
  }
}
