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
  /// Scans available fixtures/predictions and builds an accumulator slip
  /// targeting cumulative odds between 5.00 and 10.00
  static GeneratedSlip? generateTargetSlip(List<dynamic> availableFixtures) {
    final List> selectedBets = [];
    double cumulativeOdds = 1.0;

    for (var fixture in availableFixtures) {
      double odds = 1.5;
      try {
        if (fixture is Map && fixture['odds'] != null) {
          odds = double.tryParse(fixture['odds'].toString()) ?? 1.5;
        } else {
          odds = (fixture as dynamic).odds ?? 1.5;
        }
      } catch (_) {}

      if (cumulativeOdds * odds <= 12.0) {
        String home = 'Home';
        String away = 'Away';
        String pred = 'Win';

        if (fixture is Map) {
          home = fixture['homeTeam']?.toString() ?? 'Home';
          away = fixture['awayTeam']?.toString() ?? 'Away';
          pred = fixture['prediction']?.toString() ?? 'Win';
        } else {
          try {
            home = (fixture as dynamic).homeTeam ?? 'Home';
            away = (fixture as dynamic).awayTeam ?? 'Away';
            pred = (fixture as dynamic).prediction ?? 'Win';
          } catch (_) {}
        }

        selectedBets.add({
          'match': '$home vs $away',
          'prediction': pred,
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
