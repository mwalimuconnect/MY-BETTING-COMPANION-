import 'fixture_model.dart';
import 'package:flutter/material.dart';

class GeneratedSlip {
  final String title;
  final double totalOdds;
  final List> selections;
  final double stake;
  final double potentialPayout;
  final Color payoutColor;

  /// Reminder about odds source.
  final String note;

  GeneratedSlip({
    required this.title,
    required this.totalOdds,
    required this.selections,
    this.stake = 200.0,
    double? potentialPayout,
    this.payoutColor = const Color(0xFF008080), // Teal Green
    this.note =
        'Includes available bookmaker odds where live, otherwise model-implied.',
  }) : potentialPayout =
            potentialPayout ?? double.parse((totalOdds * stake).toStringAsFixed(2));
}

class _Candidate {
  final String match;
  final String prediction;
  final double odds; 
  final num prob;

  const _Candidate(this.match, this.prediction, this.odds, this.prob);
}

class SlipGenerator {
  /// Reads a percentage such as "62%" and returns 62.0 (or null if unknown).
  static double? _percent(String text) {
    final cleaned = text.replaceAll('%', '').trim();
    final value = double.tryParse(cleaned);
    if (value == null || value <= 0 || value >= 100) return null;
    return value;
  }

  /// Builds an accumulator strictly from TODAY'S matches, aiming for combined odds between 5.00 and 10.00.
  static GeneratedSlip? generateTargetSlip(List<dynamic> availableFixtures) {
    final now = DateTime.now();
    final List<_Candidate> candidates = [];

    for (final fixture in availableFixtures) {
      if (fixture is! FixtureModel) continue;
      if (fixture.isFinished || fixture.isLive) continue;

      // Ensure the match kickoff is strictly TODAY
      if (fixture.kickoff == null) continue;
      final localKickoff = fixture.kickoff!.toLocal();
      if (localKickoff.year != now.year ||
          localKickoff.month != now.month ||
          localKickoff.day != now.day) {
        continue;
      }

      final double homeProb = fixture.homeWinProb.toDouble();
      final double drawProb = fixture.drawProb.toDouble();
      final double awayProb = fixture.awayWinProb.toDouble();

      if (homeProb <= 0 && awayProb <= 0) continue;

      final String matchName = '${fixture.homeTeam} vs ${fixture.awayTeam}';

      // 1. Standard 1X2 / winner tip (uses real bookmaker odds if available and > 0, else model odds)
      final num? tipProb = fixture.tipProb;
      if (fixture.topTip.isNotEmpty && tipProb != null && tipProb > 0) {
        final double odds = (fixture.odds > 0 && fixture.topTip.toLowerCase().contains('win'))
            ? fixture.odds
            : 100 / tipProb.toDouble();
        candidates.add(_Candidate(matchName, fixture.topTip, odds, tipProb));
      }

      // 2. Double Chance (1X or X2) for clear favourites
      if (homeProb >= 55.0) {
        final double dcProb = homeProb + drawProb;
        if (dcProb < 95.0) {
          candidates.add(_Candidate(
            matchName,
            'Double Chance: ${fixture.homeTeam} or Draw (1X)',
            100 / dcProb,
            dcProb,
          ));
        }
      } else if (awayProb >= 55.0) {
        final double dcProb = awayProb + drawProb;
        if (dcProb < 95.0) {
          candidates.add(_Candidate(
            matchName,
            'Double Chance: Draw or ${fixture.awayTeam} (X2)',
            100 / dcProb,
            dcProb,
          ));
        }
      }

      // 3. Over 2.5 goals
      final double? over25 = _percent(fixture.over25Goals);
      if (over25 != null && over25 >= 55.0) {
        candidates.add(_Candidate(matchName, 'Over 2.5 Goals', 100 / over25, over25));
      }

      // 4. Both teams to score
      final double? btts = _percent(fixture.btts);
      if (btts != null && btts >= 55.0) {
        candidates.add(_Candidate(
            matchName, 'Both Teams To Score: Yes', 100 / btts, btts));
      }
    }

    // Most confident first
    candidates.sort((a, b) => b.prob.compareTo(a.prob));

    final List> selectedBets = [];
    final Set<String> usedMatches = {};
    double cumulativeOdds = 1.0;

    // First pass: one pick per match
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
          title: '\u{1F525} Prolific Value Accumulator',
          totalOdds: double.parse(cumulativeOdds.toStringAsFixed(2)),
          selections: selectedBets,
        );
      }
    }

    // Second pass if target not reached yet
    for (final c in candidates) {
      if (selectedBets.any((s) => s['match'] == c.match && s['prediction'] == c.prediction)) {
        continue;
      }
      if (cumulativeOdds * c.odds > 14.0) continue;

      selectedBets.add({
        'match': c.match,
        'prediction': c.prediction,
        'odds': double.parse(c.odds.toStringAsFixed(2)),
      });
      cumulativeOdds *= c.odds;

      if (cumulativeOdds >= 5.00 && cumulativeOdds <= 10.00) {
        return GeneratedSlip(
          title: '\u{1F525} Prolific Value Accumulator',
          totalOdds: double.parse(cumulativeOdds.toStringAsFixed(2)),
          selections: selectedBets,
        );
      }
    }

    if (selectedBets.isNotEmpty && cumulativeOdds >= 3.0) {
      return GeneratedSlip(
        title: '\u26A1 Custom Combo Slip',
        totalOdds: double.parse(cumulativeOdds.toStringAsFixed(2)),
        selections: selectedBets,
      );
    }

    return null;
  }
}
