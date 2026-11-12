class FixtureModel {
  final String? key;
  final String league;
  final String time;
  final String homeTeam;
  final String awayTeam;
  final List<String> homeForm;
  final List<String> awayForm;
  final int homeWinProb;
  final int drawProb;
  final int awayWinProb;
  final String over25Goals;
  final String btts;
  final String cardRisk;
  final String topTip;
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
    required this.league,
    required this.time,
    required this.homeTeam,
    required this.awayTeam,
    required this.homeForm,
    required this.awayForm,
    required this.homeWinProb,
    required this.drawProb,
    required this.awayWinProb,
    required this.over25Goals,
    required this.btts,
    required this.cardRisk,
    required this.topTip,
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

  factory FixtureModel.fromJson(Map<String, dynamic> json) {
    return FixtureModel(
      key: json['key']?.toString() ?? '${json['homeTeam']}_${json['awayTeam']}',
      league: json['league']?.toString() ?? '',
      time: json['time']?.toString() ?? '',
      homeTeam: json['homeTeam']?.toString() ?? '',
      awayTeam: json['awayTeam']?.toString() ?? '',
      homeForm: _toStringList(json['homeForm'], ['W', 'D', 'W']),
      awayForm: _toStringList(json['awayForm'], ['L', 'D', 'W']),
      homeWinProb: _toInt(json['homeWinProb'], 50),
      drawProb: _toInt(json['drawProb'], 25),
      awayWinProb: _toInt(json['awayWinProb'], 25),
      over25Goals: json['over25Goals']?.toString() ?? '50%',
      btts: json['btts']?.toString() ?? '50%',
      cardRisk: json['cardRisk']?.toString() ?? 'Low',
      topTip: json['topTip']?.toString() ?? '',
      odds: _toDouble(json['odds'], 1.5),
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
