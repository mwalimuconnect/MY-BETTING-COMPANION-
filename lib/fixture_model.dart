class FixtureModel {
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
  bool isSaved;

  FixtureModel({
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
    this.isSaved = false,
  });

  factory FixtureModel.fromJson(Map<String, dynamic> json) {
    return FixtureModel(
      league: json['league'] ?? 'Premier League',
      time: json['time'] ?? '21:00 EAT',
      homeTeam: json['home_team'] ?? 'Home Team',
      awayTeam: json['away_team'] ?? 'Away Team',
      homeForm: List<String>.from(json['home_form'] ?? ['W', 'W', 'D', 'W', 'L']),
      awayForm: List<String>.from(json['away_form'] ?? ['W', 'L', 'D', 'W', 'W']),
      homeWinProb: json['home_win_prob'] ?? 54,
      drawProb: json['draw_prob'] ?? 26,
      awayWinProb: json['away_win_prob'] ?? 20,
      over25Goals: json['over_25_goals'] ?? '72%',
      btts: json['btts'] ?? '68%',
      cardRisk: json['card_risk'] ?? 'Medium',
      topTip: json['top_tip'] ?? 'Over 2.5 Goals & BTTS - Yes',
      odds: (json['odds'] ?? 2.15).toDouble(),
    );
  }
}
