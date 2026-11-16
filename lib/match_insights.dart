import 'package:flutter/material.dart';
import 'app_settings.dart';
import 'fixture_model.dart';

/// Opens a bottom sheet that explains why the app made its prediction for a
/// match. Everything shown comes from the server's real data (probabilities,
/// recent form, meetings this season). Nothing is invented.
void showMatchInsights(BuildContext context, FixtureModel fixture) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: cardBg(context),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.of(context).size.height * 0.9,
    ),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) => _InsightSheet(fixture: fixture),
  );
}

class _InsightSheet extends StatelessWidget {
  final FixtureModel fixture;

  const _InsightSheet({required this.fixture});

  // W = 3 points, D = 1, L = 0
  int _points(List<String> form) {
    var total = 0;
    for (final r in form) {
      if (r == 'W') {
        total += 3;
      } else if (r == 'D') {
        total += 1;
      }
    }
    return total;
  }

  int _count(List<String> form, String result) =>
      form.where((r) => r == result).length;

  Widget _title(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 14,
          color: Color(0xFF008080), // Teal Green
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _bullet(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6, right: 8),
            child: Icon(Icons.circle, size: 6, color: Color(0xFF008080)),
          ),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.35))),
        ],
      ),
    );
  }

  Widget _probBar() {
    int flex(double v) => v.round() <= 0 ? 1 : v.round();
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 10,
        child: Row(
          children: [
            Expanded(flex: flex(fixture.homeWinProb), child: Container(color: kPrimary)),
            Expanded(flex: flex(fixture.drawProb), child: Container(color: Colors.grey)),
            Expanded(flex: flex(fixture.awayWinProb), child: Container(color: Colors.orange)),
          ],
        ),
      ),
    );
  }

  Widget _formStrip(BuildContext context, String team, List<String> form) {
    if (form.isEmpty) return const SizedBox.shrink();

    Color colorFor(String r) {
      if (r == 'W') return Colors.green;
      if (r == 'D') return Colors.grey;
      return Colors.red;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(team, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
          ),
          for (final r in form)
            Container(
              width: 24,
              height: 24,
              margin: const EdgeInsets.only(left: 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: colorFor(r), borderRadius: BorderRadius.circular(5)),
              child: Text(r,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
            ),
        ],
      ),
    );
  }

  /// Plain-language reasons built only from the real numbers we have.
  List<String> _reasons() {
    final reasons = <String>[];
    final home = fixture.homeTeam;
    final away = fixture.awayTeam;
    final hp = fixture.homeWinProb.round();
    final dp = fixture.drawProb.round();
    final ap = fixture.awayWinProb.round();

    final bool homeFav = fixture.homeWinProb >= fixture.awayWinProb;
    final String fav = homeFav ? home : away;
    final String other = homeFav ? away : home;
    final int favP = homeFav ? hp : ap;
    final int otherP = homeFav ? ap : hp;

    reasons.add(
        '$fav is rated the more likely winner: $favP% against $otherP% for $other, with a draw at $dp%.');

    if (homeFav && fixture.homeWinProb > 0) {
      reasons.add('$home also has home advantage, which the model includes.');
    }

    if (fixture.homeForm.isNotEmpty && fixture.awayForm.isNotEmpty) {
      final hPts = _points(fixture.homeForm);
      final aPts = _points(fixture.awayForm);
      final hMax = fixture.homeForm.length * 3;
      final aMax = fixture.awayForm.length * 3;
      reasons.add(
          'Recent form: $home took $hPts of $hMax points in the last ${fixture.homeForm.length} '
          '(${_count(fixture.homeForm, 'W')}W ${_count(fixture.homeForm, 'D')}D ${_count(fixture.homeForm, 'L')}L), '
          '$away took $aPts of $aMax '
          '(${_count(fixture.awayForm, 'W')}W ${_count(fixture.awayForm, 'D')}D ${_count(fixture.awayForm, 'L')}L).');
    }

    if (fixture.over25Goals != 'N/A' && fixture.btts != 'N/A') {
      reasons.add(
          'Goals outlook: ${fixture.over25Goals} chance of over 2.5 goals and ${fixture.btts} that both teams score.');
    }

    if (fixture.topTip.isEmpty) {
      reasons.add(
          'No tip is shown because neither side reaches the 45% confidence the app requires.');
    }

    return reasons;
  }

  @override
  Widget build(BuildContext context) {
    final int? tipPct = fixture.tipProbInt;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${fixture.homeTeam} vs ${fixture.awayTeam}',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            Text(
              fixture.timeLabel.isEmpty ? fixture.league : '${fixture.league}  |  ${fixture.timeLabel}',
              style: TextStyle(fontSize: 12, color: mutedText(context)),
            ),
            const Divider(height: 24),

            if (!fixture.hasPrediction) ...[
              _title('NO PREDICTION YET'),
              _bullet(context,
                  'The model needs at least 5 finished matches this season for both teams (and 20 in the competition) before it can estimate this match.'),
              _bullet(context,
                  'Cup and international matches often have too little data, so they may stay unavailable.'),
            ] else ...[
              // The prediction itself
              _title('THE PREDICTION'),
              Text(
                fixture.topTip.isEmpty ? 'No clear tip' : fixture.topTip,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kPrimary),
              ),
              if (tipPct != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('Model confidence: $tipPct%',
                      style: TextStyle(fontSize: 12, color: mutedText(context))),
                ),
              const SizedBox(height: 12),
              _probBar(),
              const SizedBox(height: 8),
              _row('${fixture.homeTeam} win', '${fixture.homeWinProb.round()}%'),
              _row('Draw', '${fixture.drawProb.round()}%'),
              _row('${fixture.awayTeam} win', '${fixture.awayWinProb.round()}%'),

              // Why
              _title('WHY THE MODEL SAYS THIS'),
              for (final r in _reasons()) _bullet(context, r),

              // Form
              if (fixture.homeForm.isNotEmpty || fixture.awayForm.isNotEmpty) ...[
                _title('RECENT FORM (OLDEST TO NEWEST)'),
                _formStrip(context, fixture.homeTeam, fixture.homeForm),
                _formStrip(context, fixture.awayTeam, fixture.awayForm),
              ],

              // Head to head
              if (fixture.h2h.isNotEmpty) ...[
                _title('MEETINGS THIS SEASON'),
                for (final m in fixture.h2h)
                  _row('${m.home} ${m.score} ${m.away}', m.date),
              ],

              // Goals
              if (fixture.over25Goals != 'N/A') ...[
                _title('GOALS'),
                _row('Over 2.5 goals', fixture.over25Goals),
                _row('Both teams to score', fixture.btts),
              ],

              // How it works
              _title('HOW IT IS CALCULATED'),
              Text(
                'The model counts the goals each team has scored and conceded in this season\'s finished matches in the same competition, '
                'adjusts for home advantage, and pulls small samples toward the league average. '
                'It then simulates the possible scorelines to get the win, draw and goals chances. '
                'It does not know about injuries, suspensions, lineups or odds.',
                style: TextStyle(fontSize: 12, height: 1.4, color: mutedText(context)),
              ),
            ],

            const SizedBox(height: 16),
            Text(
              'Estimates only. No tip is guaranteed to win.',
              style: TextStyle(fontSize: 11, color: mutedText(context)),
            ),
          ],
        ),
      ),
    );
  }
}
