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

class FixtureModel {
  final String? key;
  final String utcDate; // ISO time of kickoff (UTC)
  final String competitionCode;
  final String dateLabel; // e.g. "Thu 19 Nov"
  final String kickoffTime; // e.g. "01:30 EAT"
  final String league;
  final String time;
  final String homeTeam;
  final String awayTeam;
  final List<String> homeForm;
  final List<String> awayForm;
  final List<H2HEntry> h2h;
  final int homeWinProb;
  final int drawProb;
  final int awayWinProb;
  final String over25Goals;
  final String btts;
  final String cardRisk;
  final String topTip;
  final int? tipProb;
  final double odds;
  final bool isLive;
  final bool isFinished;
  final String actualScore;
  final bool? predictionCorrect;
  final bool isProlific;
  final bool isSample;
  final bool isEstimate;
  bool isSaved;

  FixtureModel({
    this.key,
    this.utcDate = '',
    this.competitionCode = '',
    this.dateLabel = '',
    this.kickoffTime = '',
    required this.league,
    required this.time,
    required this.homeTeam,
    required this.awayTeam,
    required this.homeForm,
    required this.awayForm,
    this.h2h = const [],
    required this.homeWinProb,
    required this.drawProb,
    required this.awayWinProb,
    required this.over25Goals,
    required this.btts,
    required this.cardRisk,
    required this.topTip,
    this.tipProb,
    required this.odds,
    required this.isLive,
    required this.isFinished,
    required this.actualScore,
    required this.predictionCorrect,
    required this.isProlific,
    this.isSample = false,
    this.isEstimate = false,
    this.isSaved = false,
  });

  /// Kickoff as a DateTime (UTC), or null if the server did not send it.
  DateTime? get kickoff => DateTime.tryParse(utcDate);

  /// True when the server produced a real prediction for this match.
  bool get hasPrediction => (homeWinProb + drawProb + awayWinProb) > 0;

  /// Reads a JSON number (int or double) safely as an int.
  static int _toInt(dynamic value, int fallback) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  /// Reads a JSON number (int or double) safely as a double.
  static double _toDouble(dynamic value, double fallback) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? fallback;
    return fallback;
  }

  /// Reads a JSON list of strings, falling back if missing or wrong type.
  static List<String> _toStringList(dynamic value, List<String> fallback) {
    if (value is List) return value.map((e) => e.toString()).toList();
    return fallback;
  }

  static List<H2HEntry> _toH2H(dynamic value) {
    if (value is! List) return const [];
    final out = <H2HEntry>[];
    for (final e in value) {
      if (e is Map) {
        out.add(H2HEntry.fromJson(Map<String, dynamic>.from(e)));
      }
    }
    return out;
  }

  factory FixtureModel.fromJson(Map<String, dynamic> json) {
    return FixtureModel(
      key: json['key']?.toString() ?? '${json['homeTeam']}_${json['awayTeam']}',
      utcDate: json['utcDate']?.toString() ?? '',
      competitionCode: json['competitionCode']?.toString() ?? '',
      dateLabel: json['dateLabel']?.toString() ?? '',
      kickoffTime: json['kickoffTime']?.toString() ?? '',
      league: json['league']?.toString() ?? '',
      time: json['time']?.toString() ?? '',
      homeTeam: json['homeTeam']?.toString() ?? '',
      awayTeam: json['awayTeam']?.toString() ?? '',
      homeForm: _toStringList(json['homeForm'], []),
      awayForm: _toStringList(json['awayForm'], []),
      h2h: _toH2H(json['h2h']),
      homeWinProb: _toInt(json['homeWinProb'], 0),
      drawProb: _toInt(json['drawProb'], 0),
      awayWinProb: _toInt(json['awayWinProb'], 0),
      over25Goals: json['over25Goals']?.toString() ?? 'N/A',
      btts: json['btts']?.toString() ?? 'N/A',
      cardRisk: json['cardRisk']?.toString() ?? 'N/A',
      topTip: json['topTip']?.toString() ?? '',
      tipProb: json['tipProb'] is num ? (json['tipProb'] as num).toInt() : null,
      odds: _toDouble(json['odds'], 0),
      isLive: json['isLive'] == true,
      isFinished: json['isFinished'] == true,
      actualScore: json['actualScore']?.toString() ?? 'Pending',
      predictionCorrect: json['predictionCorrect'] is bool
          ? json['predictionCorrect'] as bool
          : null,
      isProlific: json['isProlific'] == true,
      isSample: json['isSample'] == true,
      isEstimate: json['isEstimate'] == true,
      isSaved: json['isSaved'] == true,
    );
  }
}
