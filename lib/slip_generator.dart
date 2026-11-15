import 'fixture_model.dart';
import 'package:flutter/material.dart';

class GeneratedSlip {
  final String title;
  final double totalOdds;
  final List> selections;
  final double stake;
  final double potentialPayout;
  final Color payoutColor;

  /// Reminder that these are not bookmaker odds.
  final String note;

  GeneratedSlip({
    required this.title,
    required this.totalOdds,
    required this.selections,
    this.stake = 200.0,
    double? potentialPayout,
    this.payoutColor = const Color(0xFF008080), // Teal Green
    this.note =
        'Odds are model-implied (100 divided by win probability), not bookmaker odds.',
  }) : potentialPayout =
            potentialPayout ?? double.parse((totalOdds * 200.0).toStringAsFixed(2));
}

class _Candidate {
  final String match;
  final String prediction;
  final double odds; // model-implied "fair" odds
  final num prob;

  const _Candidate(this.match, this.prediction, this.odds, this.prob);
}

class SlipGenerator {
  /// Builds an accumulator from upcoming matches, varying the prediction markets
  /// across 1X2, Double Chance, Over/Under Goals, and Handicaps,
  /// aiming for combined odds between 5.00 and 10.00.
  static GeneratedSlip? generateTargetSlip(List<dynamic> availableFixtures) {
    final List<_Candidate> candidates = [];

    for (final fixture in availableFixtures) {
      if (fixture is! FixtureModel) continue;
      if (fixture.isFinished || fixture.isLive) continue;

      final double homeProb = fixture.homeWinProb.toDouble();
      final double drawProb = fixture.drawProb.toDouble();
      final double awayProb = fixture.awayWinProb.toDouble();
      
      if (homeProb <= 0 && awayProb <= 0) continue;

      final matchName = '${fixture.homeTeam} vs ${fixture.awayTeam}';

      // 1. Standard 1X2 / Winner tip
      if (fixture.topTip.isNotEmpty && fixture.tipProb != null && fixture.tipProb! > 0) {
        final double odds = 100 / fixture.tipProb!.toDouble();
        candidates.add(_Candidate(matchName, fixture.topTip, odds, fixture.tipProb!));
      }

      // 2. Double Chance Market (1X or X2)
      if (homeProb >= 55.0) {
        final double dcProb = homeProb + drawProb;
        if (dcProb < 95.0) {
          final double dcOdds = 100 / dcProb;
          candidates.add(_Candidate(matchName, 'Double Chance: ${fixture.homeTeam} or Draw (1X)', dcOdds, dcProb));
        }
      } else if (awayProb >= 55.0) {
        final double dcProb = awayProb + drawProb;
        if (dcProb < 95.0) {
          final double dcOdds = 100 / dcProb;
          candidates.add(_Candidate(matchName, 'Double Chance: Draw or ${fixture.awayTeam} (X2)', dcOdds, dcProb));
        }
      }

      // 3. Over / Under Goals Markets based on probabilities
      if (homeProb > 65.0 || awayProb > 65.0) {
        const double over25Prob = 72.0;
        final double over25Odds = 100 / over25Prob;
        candidates.add(_Candidate(matchName, 'Over 2.5 Goals', over25Odds, over25Prob));
      } else {
        const double over15Prob = 82.0;
        final double over15Odds = 100 / over15Prob;
        candidates.add(_Candidate(matchName, 'Over 1.5 Goals', over15Odds, over15Prob));
      }

      // 4. Handicap Markets for strong favorites
      if (homeProb >= 70.0) {
        const double hcProb = 48.0;
        final double hcOdds = 100 / hcProb;
        candidates.add(_Candidate(matchName, 'Handicap: ${fixture.homeTeam} (-1.5)', hcOdds, hcProb));
      } else if (awayProb >= 70.0) {
        const double hcProb = 48.0;
        final double hcOdds = 100 / hcProb;
        candidates.add(_Candidate(matchName, 'Handicap: ${fixture.awayTeam} (-1.5)', hcOdds, hcProb));
      }
    }

    // Sort candidates by confidence / probability descending
    candidates.sort((a, b) => b.prob.compareTo(a.prob));

    final List> selectedBets = [];
    final Set<String> usedMatches = {};
    double cumulativeOdds = 1.0;

    // First pass: try to pick unique markets across different matches
    for (final c in candidates) {
      if (usedMatches.contains(c.match)) continue;
      if (cumulativeOdds * c.odds > 14.0) continue;

      selectedBets.add({
        'match': c.match,
        'prediction': c.prediction,
        'odds': double.parse(c.odds.toStringAsFixed(2)),
      });
      usedMatches.add(c.match);
      cumulativeOdds *= c.odds;

      if (cumulativeOdds >= 5.00 && cumulativeOdds <= 10.00) {
        return GeneratedSlip(
          title: '🔥 Prolific Value Accumulator',
          totalOdds: double.parse(cumulativeOdds.toStringAsFixed(2)),
          selections: selectedBets,
        );
      }
    }

    // Second pass if target odds not reached yet
    for (final c in candidates) {
      if (selectedBets.any((s) => s['match'] == c.match && s['prediction'] == c.prediction)) continue;
      if (cumulativeOdds * c.odds > 14.0) continue;

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
