import 'package:flutter/material.dart';

class GeneratedSlip {
  final String title;
  final double totalOdds;
  final List> selections;

  GeneratedSlip({
    required this.title,
    required this.totalOdds,
    required this.selections,
  });
}

class SlipGenerator {
  static GeneratedSlip? generateTargetSlip(List<dynamic> availableFixtures) {
    List> selectedBets = [];
    double cumulativeOdds = 1.0;

    for (var fixture in availableFixtures) {
      double odds = 1.5;
      try {
        if (fixture is Map && fixture['odds'] != null) {
          odds = double.tryParse(fixture['odds'].toString()) ?? 1.5;
        }
      } catch (_) {}

      if (cumulativeOdds * odds <= 12.0) {
        selectedBets.add({
          'match': fixture is Map ? '${fixture['homeTeam']} vs ${fixture['awayTeam']}' : 'Match Selection',
          'prediction': fixture is Map ? (fixture['prediction'] ?? 'Win') : 'Win',
          'odds': odds,
        });
        cumulativeOdds *= odds;
      }

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
