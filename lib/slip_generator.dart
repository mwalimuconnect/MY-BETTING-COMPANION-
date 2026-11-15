import 'fixture_model.dart';

class GeneratedSlip {
  final String title;
  final double totalOdds;
  final List> selections;
  final double stake;
  final double potentialPayout;

  /// Reminder that these are not bookmaker odds.
  final String note;

  GeneratedSlip({
    required this.title,
    required this.totalOdds,
    required this.selections,
    this.stake = 200.0,
    double? potentialPayout,
    this.note =
        'Odds are model-implied (100 divided by win probability), not bookmaker odds.',
  }) : potentialPayout = potentialPayout ?? double.parse((totalOdds * 200.0).toStringAsFixed(2));
}

class _Candidate {
  final String match;
  final String prediction;
  final double odds; // model-implied "fair" odds
  final num prob;

  _Candidate(this.match, this.prediction, this.odds, this.prob);
}

class SlipGenerator {
  /// Builds an accumulator from upcoming matches that have a model tip,
  /// most confident first, aiming for combined odds between 5.00 and 10.00.
  static GeneratedSlip? generateTargetSlip(List<dynamic> availableFixtures) {
    final List<_Candidate> candidates = [];

    for (final fixture in availableFixtures) {
      if (fixture is! FixtureModel) continue;
      if (fixture.isFinished || fixture.isLive) continue;

      final num? prob = fixture.tipProb;
      if (fixture.topTip.isEmpty || prob == null || prob <= 0) continue;

      final double odds = 100 / prob.toDouble();
      candidates.add(_Candidate(
        '${fixture.homeTeam} vs ${fixture.awayTeam}',
        fixture.topTip,
        odds,
        prob,
      ));
    }

    // Most confident tips first.
    candidates.sort((a, b) => b.prob.compareTo(a.prob));

    final List> selectedBets = [];
    double cumulativeOdds = 1.0;

    for (final c in candidates) {
      if (cumulativeOdds * c.odds > 12.0) continue;

      selectedBets.add({
        'match': c.match,
        'prediction': c.prediction,
        'odds': double.parse(c.odds.toStringAsFixed(2)),
      });
      cumulativeOdds *= c.odds;

      if (cumulativeOdds >= 5.00 && cumulativeOdds <= 10.00) {
        return GeneratedSlip(
          title: '🔥 Prolific Value Accumulator',
          totalOdds: double.parse(cumulativeOdds.toStringAsFixed(2)),
          selections: selectedBets,
        );
      }
    }

    if (selectedBets.isNotEmpty && cumulativeOdds >= 3.0) {
      return GeneratedSlip(
        title: '⚡ Custom Combo Slip',
        totalOdds: double.parse(cumulativeOdds.toStringAsFixed(2)),
        selections: selectedBets,
      );
    }

    return null;
  }
}
