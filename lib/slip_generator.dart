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
  /// Scans available fixtures/predictions and builds a accumulator slip
  /// targeting cumulative odds between 5.00 and 10.00
  static GeneratedSlip? generateTargetSlip(List<dynamic> availableFixtures) {
    List> selectedBets = [];
    double cumulativeOdds = 1.0;

    for (var fixture in availableFixtures) {
      // Example model prediction extraction
      double odds = fixture['odds'] ?? 1.5; 
      
      // Stop adding if adding another selection pushes us way past 10.00
      if (cumulativeOdds * odds <= 12.0) {
        selectedBets.add({
          'match': '${fixture['homeTeam']} vs ${fixture['awayTeam']}',
          'prediction': fixture['prediction'] ?? 'Home Win',
          'odds': odds,
        });
        cumulativeOdds *= odds;
      }

      // Check if we hit our target window [5.00 - 10.00]
      if (cumulativeOdds >= 5.00 && cumulativeOdds <= 10.00) {
        return GeneratedSlip(
          title: '🔥 Prolific Value Accumulator',
          totalOdds: double.parse(cumulativeOdds.toStringAsFixed(2)),
          selections: selectedBets,
        );
      }
    }

    // If we gathered selections but didn't hit the exact 5-10 bracket yet
    if (selectedBets.isNotEmpty && cumulativeOdds >= 3.0) {
      return GeneratedSlip(
        title: '⚡ Custom Combo Slip',
        totalOdds: double.parse(cumulativeOdds.toStringAsFixed(2)),
        selections: selectedBets,
      );
    }

    return null; // No suitable slip found yet
  }
}
