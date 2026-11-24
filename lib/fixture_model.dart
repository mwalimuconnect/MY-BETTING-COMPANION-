import 'package:flutter/material.dart';

const Color _kSafaricomGreen = Color(0xFF3AA335);

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

    /// True when the fixture has server prediction or extended market data.
  bool get hasAnalysis {
    if (hasPrediction || topTip.trim().isNotEmpty || tipProb > 0) {
      return true;
    }
    if (over15Goals.toUpperCase() != 'N/A' && over15Goals.trim().isNotEmpty) {
      return true;
    }
    if (over25Goals.toUpperCase() != 'N/A' && over25Goals.trim().isNotEmpty) {
      return true;
    }
    if (under35Goals.toUpperCase() != 'N/A' && under35Goals.trim().isNotEmpty) {
      return true;
    }
    if (btts.toUpperCase() != 'N/A' && btts.trim().isNotEmpty) {
      return true;
    }
    if (cardRisk.toUpperCase() != 'N/A' && cardRisk.trim().isNotEmpty) {
      return true;
    }
    if (firstHalfGoalsProb != null ||
        secondHalfGoalsProb != null ||
        homeCardsProb != null ||
        drawCardsProb != null ||
        awayCardsProb != null ||
        firstHalfCardsProb != null ||
        secondHalfCardsProb != null) {
      return true;
    }
    if (anytimeScorers.isNotEmpty || h2h.isNotEmpty) {
      return true;
    }
    return false;
  }

  /// Text such as "Thu 19 Nov, 01:30 EAT" (empty if the server sent no date).
  String get timeLabel {
    if (dateLabel.isEmpty) return kickoffTime;
    if (kickoffTime.isEmpty) return dateLabel;
    return '$dateLabel, $kickoffTime';
  }

  /// True when actualScore contains a scoreline like "2-1" or starts with "FT".
  bool get hasFinalScore {
    final String clean = actualScore.trim().toLowerCase();
    if (clean.isEmpty ||
        clean == 'pending' ||
        clean == 'ns' ||
        clean == 'tbd') {
      return false;
    }
    return clean.contains('-') || clean.startsWith('ft');
  }

  bool get effectiveIsFinished => isFinished || hasFinalScore;
  bool get effectiveIsLive => isLive && !effectiveIsFinished;
  bool get effectiveIsUpcoming => !effectiveIsLive && !effectiveIsFinished;

  /// Parses (homeGoals, awayGoals) from actualScore, or null if unavailable.
  (int homeGoals, int awayGoals)? get parsedGoals {
    final String scorePart = actualScore
        .replaceAll(RegExp(r'^ft\s*', caseSensitive: false), '')
        .trim();
    final List<String> parts = scorePart.split(RegExp(r'\s*-\s*'));
    if (parts.length != 2) return null;

    final int? homeGoals = int.tryParse(parts[0].trim());
    final int? awayGoals = int.tryParse(parts[1].trim());
    if (homeGoals == null || awayGoals == null) return null;
    return (homeGoals, awayGoals);
  }

  /// Formats kickoff in device local time (EAT), falling back to timeLabel.
  String get formattedLocalTime {
    final DateTime? dt = kickoff;
    if (dt == null) return timeLabel;

    final DateTime local = dt.toLocal();
    const List<String> weekdays = [
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ];
    const List<String> months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    final String dayName = weekdays[local.weekday - 1];
    final String monthName = months[local.month - 1];
    final String dayNum = local.day.toString().padLeft(2, '0');
    final String hour = local.hour.toString().padLeft(2, '0');
    final String minute = local.minute.toString().padLeft(2, '0');

    return '$dayName $dayNum $monthName, $hour:$minute EAT';
  }

  /// Evaluates any market + prediction string against this finished fixture.
  /// Returns true if won, false if lost, or null if undetermined/not finished.
  bool? evaluateMarketOutcome({
    String market = '',
    required String predictionText,
  }) {
    if (!effectiveIsFinished) return null;

    final goals = parsedGoals;
    if (goals == null) return null;

    final int homeGoals = goals.$1;
    final int awayGoals = goals.$2;
    final int totalGoals = homeGoals + awayGoals;

    final String normMarket = market.trim().toLowerCase();
    final String tip = predictionText.trim().toLowerCase();
    if (tip.isEmpty && normMarket.isEmpty) return null;

    final String homeName = homeTeam.trim().toLowerCase();
    final String awayName = awayTeam.trim().toLowerCase();

    bool matchesTeam(String fullName) {
      if (fullName.isEmpty) return false;
      if (tip == fullName ||
          tip == '$fullName win' ||
          tip.startsWith('$fullName ') ||
          tip.contains(fullName)) {
        return true;
      }
      final List<String> tokens = fullName
          .split(RegExp(r'\s+'))
          .where(
            (t) =>
                t.length >= 4 &&
                !{'fc', 'sc', 'cf', 'cd', 'ca', 'cr', 'afc', 'united', 'city'}
                    .contains(t),
          )
          .toList();
      return tokens.any(
        (token) => RegExp('\\b${RegExp.escape(token)}\\b').hasMatch(tip),
      );
    }

    // Goal markets
    if (normMarket == 'over 1.5' ||
        normMarket == 'ov1.5' ||
        tip.contains('over 1.5') ||
        tip == 'ov 1.5') {
      return totalGoals > 1;
    }
    if (normMarket == 'ov2.5' ||
        normMarket == 'over 2.5' ||
        tip.contains('over 2.5') ||
        tip == 'ov 2.5') {
      return totalGoals > 2;
    }
    if (normMarket == 'under 2.5' ||
        normMarket == 'un2.5' ||
        tip.contains('under 2.5') ||
        tip == 'un 2.5') {
      return totalGoals < 3;
    }
    if (normMarket == 'under 3.5' ||
        normMarket == 'un3.5' ||
        tip.contains('under 3.5') ||
        tip == 'un 3.5') {
      return totalGoals < 4;
    }
    if (normMarket == 'gg' ||
        normMarket == 'btts' ||
        tip == 'gg' ||
        tip == 'btts' ||
        tip == 'btts yes' ||
        tip.contains('btts yes') ||
        tip.contains('both teams to score: yes')) {
      return homeGoals > 0 && awayGoals > 0;
    }
    if (normMarket == 'ng' ||
        tip == 'ng' ||
        tip == 'btts no' ||
        tip.contains('btts no') ||
        tip.contains('both teams to score: no')) {
      return homeGoals == 0 || awayGoals == 0;
    }

    // Double Chance
    if (normMarket == 'double chance' ||
        normMarket == 'dc' ||
        tip.contains('double chance') ||
        tip == '1x' ||
        tip == 'x2' ||
        tip == '12' ||
        tip == 'home or draw' ||
        tip == 'away or draw' ||
        tip == 'home or away') {
      if (tip == '1x' ||
          tip == 'home or draw' ||
          tip.contains('(1x)') ||
          (matchesTeam(homeName) && tip.contains('or draw'))) {
        return homeGoals >= awayGoals;
      }
      if (tip == 'x2' ||
          tip == 'away or draw' ||
          tip.contains('(x2)') ||
          (matchesTeam(awayName) && tip.contains('draw or'))) {
        return awayGoals >= homeGoals;
      }
      if (tip == '12' || tip == 'home or away' || tip.contains('(12)')) {
        return homeGoals != awayGoals;
      }
    }

    // 1X2 / Match Winner
    if (tip == '1' ||
        tip == 'home' ||
        tip == 'home win' ||
        matchesTeam(homeName)) {
      return homeGoals > awayGoals;
    }
    if (tip == '2' ||
        tip == 'away' ||
        tip == 'away win' ||
        matchesTeam(awayName)) {
      return awayGoals > homeGoals;
    }
    if (tip == 'x' || tip == 'draw') {
      return homeGoals == awayGoals;
    }

    return null;
  }

  /// Returns true if topTip prediction won, false if lost, or null if undetermined.
  bool? get isPredictionWon {
    if (!effectiveIsFinished) return null;
    if (predictionCorrect != null) return predictionCorrect;
    if (topTip.trim().isEmpty) return null;

    return evaluateMarketOutcome(predictionText: topTip);
  }

  /// Tip confidence as a whole number, or null when there is no tip.
  int? get tipProbInt => tipProb > 0 ? tipProb.round() : null;

  // Convenience filters for UI
  bool get isUpcoming => effectiveIsUpcoming;
  bool get isLiveMatch => effectiveIsLive;
  bool get isFinishedMatch => effectiveIsFinished;

  static double _d(dynamic v, double fallback) {
    if (v is num) return v.toDouble();
    if (v is String) {
      return double.tryParse(v.replaceAll('%', '').trim()) ?? fallback;
    }
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
    final List<H2HEntry> out = [];
    for (final e in v) {
      if (e is Map) out.add(H2HEntry.fromJson(Map<String, dynamic>.from(e)));
    }
    return out;
  }

  static List<PlayerScorerTip> _scorers(dynamic v) {
    if (v is! List) return const [];
    final List<PlayerScorerTip> out = [];
    for (final e in v) {
      if (e is Map) {
        final PlayerScorerTip tip =
            PlayerScorerTip.fromJson(Map<String, dynamic>.from(e));
        if (tip.name.isNotEmpty) out.add(tip);
      }
    }
    return out;
  }
  static DateTime? _parseTimestamp(String raw) {
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final bool hasZone = trimmed.endsWith('Z') ||
        trimmed.endsWith('z') ||
        RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(trimmed);
    final String normalized = hasZone ? trimmed : '${trimmed}Z';
    return DateTime.tryParse(normalized) ?? DateTime.tryParse(trimmed);
  }

  factory FixtureModel.fromJson(Map<String, dynamic> j) {
    final String utc = j['utcDate']?.toString() ?? '';

    DateTime? parsedTime = _parseTimestamp(utc);
    parsedTime ??=
        j['kickoff'] != null ? _parseTimestamp(j['kickoff'].toString()) : null;

    final String tip =
        j['topTip']?.toString() ?? j['prediction']?.toString() ?? '';
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
  static List<FixtureModel> filterFixtures(
    List<FixtureModel> fixtures,
    String filter, {
    String searchQuery = '',
  }) {
    final String statusQuery = filter.toLowerCase();
    var filtered = fixtures.where((f) {
      if (statusQuery == 'upcoming') return f.effectiveIsUpcoming;
      if (statusQuery == 'live') return f.effectiveIsLive;
      if (statusQuery == 'finished') return f.effectiveIsFinished;
      return true;
    }).toList();

    final String textQuery = searchQuery.toLowerCase().trim();
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

class PredictionOutcomeBadge extends StatelessWidget {
  final bool? won;

  const PredictionOutcomeBadge({super.key, required this.won});

  @override
  Widget build(BuildContext context) {
    if (won == null) return const SizedBox.shrink();

    final bool isWon = won!;
    final Color color = isWon ? _kSafaricomGreen : Colors.red.shade700;
    final Color bgColor =
        isWon ? _kSafaricomGreen.withOpacity(0.12) : Colors.red.shade50;
    final Color borderColor =
        isWon ? _kSafaricomGreen.withOpacity(0.45) : Colors.red.shade300;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        isWon ? 'WON' : 'LOST',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
