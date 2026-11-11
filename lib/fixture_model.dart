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

  factory FixtureModel.fromJson(Map<String, dynamic> json) {
    return FixtureModel(
      key: json['key'] ?? '${json['homeTeam']}_${json['awayTeam']}',
      league: json['league'] ?? '',
      time: json['time'] ?? '',
      homeTeam: json['homeTeam'] ?? '',
      awayTeam: json['awayTeam'] ?? '',
      homeForm: List<String>.from(json['homeForm'] ?? ['W', 'D', 'W']),
      awayForm: List<String>.from(json['awayForm'] ?? ['L', 'D', 'W']),
      homeWinProb: json['homeWinProb'] ?? 50,
      drawProb: json['drawProb'] ?? 25,
      awayWinProb: json['awayWinProb'] ?? 25,
      over25Goals: json['over25Goals'] ?? '50%',
      btts: json['btts'] ?? '50%',
      cardRisk: json['cardRisk'] ?? 'Low',
      topTip: json['topTip'] ?? '',
      odds: (json['odds'] ?? 1.5).toDouble(),
      isLive: json['isLive'] ?? false,
      isFinished: json['isFinished'] ?? false,
      actualScore: json['actualScore'] ?? 'Pending',
      predictionCorrect: json['predictionCorrect'],
      isProlific: json['isProlific'] ?? false,
      isSample: json['isSample'] ?? false,
      isEstimate: json['isEstimate'] ?? false,
      isSaved: json['isSaved'] ?? false,
    );
  }
}
