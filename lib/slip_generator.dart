import 'fixture_model.dart';
import 'package:flutter/material.dart';
import 'slip_access_manager.dart';
import 'slip_subscription_sheet.dart';

class GeneratedSlip {
  final String id;
  final String title;
  final double totalOdds;
  final List selections;
  final double stake;
  final double potentialPayout;
  final Color payoutColor;
  final DateTime createdAt;
  final String note;

  GeneratedSlip({
    String? id,
    required this.title,
    required this.totalOdds,
    required this.selections,
    this.stake = 200.0,
    double? potentialPayout,
    this.payoutColor = const Color(0xFF008080),
    DateTime? createdAt,
    this.note =
        'Includes available bookmaker odds where live, otherwise model-implied.',
  })  : createdAt = createdAt ?? DateTime.now(),
        id = id ??
            'sys_${DateTime.now().year}_${DateTime.now().month}_${DateTime.now().day}',
        potentialPayout = potentialPayout ??
            double.parse((totalOdds * stake).toStringAsFixed(2));

  bool areAllMatchesSettled(List latestFixtures) {
    if (selections.isEmpty) return false;
    final fixtureMap = {for (final f in latestFixtures) f.key: f};

    for (final sel in selections) {
      final key = sel['fixtureKey']?.toString() ?? '';
      if (key.isEmpty) return false;
      final match = fixtureMap[key];
      if (match == null || !match.isFinished) {
        return false;
      }
    }
    return true;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'totalOdds': totalOdds,
        'selections': selections,
        'stake': stake,
        'potentialPayout': potentialPayout,
        'createdAt': createdAt.toIso8601String(),
      };

  factory GeneratedSlip.fromJson(Map<String, dynamic> json) {
    var rawSelections = json['selections'] as List? ?? [];
    List parsedSelections = rawSelections
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();

    return GeneratedSlip(
      id: json['id'],
      title: json['title'] ?? '🔥 Prolific Value Accumulator',
      totalOdds: (json['totalOdds'] as num).toDouble(),
      selections: parsedSelections,
      stake: (json['stake'] as num?)?.toDouble() ?? 200.0,
      potentialPayout: (json['potentialPayout'] as num?)?.toDouble(),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }
}

class _Candidate {
  final String fixtureKey;
  final String match;
  final String prediction;
  final double odds;
  final num prob;
  final String? kickoffIso;

  const _Candidate(
    this.fixtureKey,
    this.match,
    this.prediction,
    this.odds,
    this.prob,
    this.kickoffIso,
  );
}

class SlipGenerator {
  static double? _percent(String text) {
    final cleaned = text.replaceAll('%', '').trim();
    final value = double.tryParse(cleaned);
    if (value == null || value <= 0 || value >= 100) return null;
    return value;
  }

  static GeneratedSlip? generateTargetSlip(List availableFixtures) {
    final now = DateTime.now();
    final List candidates = [];

    for (final fixture in availableFixtures) {
      if (fixture is! FixtureModel) continue;
      if (fixture.isFinished || fixture.isLive) continue;
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
      final String? kickoffIso = fixture.kickoff?.toIso8601String();

      final num? tipProb = fixture.tipProb;
      if (fixture.topTip.isNotEmpty && tipProb != null && tipProb > 0) {
        final double odds =
            (fixture.odds > 0 && fixture.topTip.toLowerCase().contains('win'))
                ? fixture.odds
                : (100 / tipProb.toDouble());

        candidates.add(
          _Candidate(
            fixture.key,
            matchName,
            fixture.topTip,
            odds,
            tipProb,
            kickoffIso,
          ),
        );
      }

      if (homeProb >= 55.0) {
        final double dcProb = homeProb + drawProb;
        if (dcProb < 95.0) {
          candidates.add(
            _Candidate(
              fixture.key,
              matchName,
              'Double Chance: ${fixture.homeTeam} or Draw (1X)',
              100 / dcProb,
              dcProb,
              kickoffIso,
            ),
          );
        }
      } else if (awayProb >= 55.0) {
        final double dcProb = awayProb + drawProb;
        if (dcProb < 95.0) {
          candidates.add(
            _Candidate(
              fixture.key,
              matchName,
              'Double Chance: Draw or ${fixture.awayTeam} (X2)',
              100 / dcProb,
              dcProb,
              kickoffIso,
            ),
          );
        }
      }

      final double? over25 = _percent(fixture.over25Goals);
      if (over25 != null && over25 >= 55.0) {
        candidates.add(
          _Candidate(
            fixture.key,
            matchName,
            'Over 2.5 Goals',
            100 / over25,
            over25,
            kickoffIso,
          ),
        );
      }

      final double? btts = _percent(fixture.btts);
      if (btts != null && btts >= 55.0) {
        candidates.add(
          _Candidate(
            fixture.key,
            matchName,
            'Both Teams To Score: Yes',
            100 / btts,
            btts,
            kickoffIso,
          ),
        );
      }
    }

    candidates.sort((a, b) => b.prob.compareTo(a.prob));

    final List selectedBets = [];
    final Set usedMatches = {};
    double cumulativeOdds = 1.0;

    for (final c in candidates) {
      if (usedMatches.contains(c.match)) continue;
      if ((cumulativeOdds * c.odds) > 14.0) continue;

      selectedBets.add({
        'fixtureKey': c.fixtureKey,
        'match': c.match,
        'prediction': c.prediction,
        'odds': double.parse(c.odds.toStringAsFixed(2)),
        'kickoff': c.kickoffIso,
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

    for (final c in candidates) {
      if (selectedBets.any(
        (s) => s['match'] == c.match && s['prediction'] == c.prediction,
      )) {
        continue;
      }
      if ((cumulativeOdds * c.odds) > 14.0) continue;

      selectedBets.add({
        'fixtureKey': c.fixtureKey,
        'match': c.match,
        'prediction': c.prediction,
        'odds': double.parse(c.odds.toStringAsFixed(2)),
        'kickoff': c.kickoffIso,
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

class ProtectedSystemSlipCard extends StatefulWidget {
  final GeneratedSlip slip;
  final List latestFixtures;

  const ProtectedSystemSlipCard({
    super.key,
    required this.slip,
    required this.latestFixtures,
  });

  @override
  State<ProtectedSystemSlipCard> createState() =>
      _ProtectedSystemSlipCardState();
}

class _ProtectedSystemSlipCardState extends State<ProtectedSystemSlipCard> {
  bool _hasAccess = false;
  bool _isAdmin = false;
  int _waiverDays = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _verifyAccess();
  }

  Future<void> _verifyAccess() async {
    final status = await SlipAccessManager.checkAccess();
    if (!mounted) return;
    setState(() {
      _hasAccess = status.hasAccess;
      _isAdmin = status.isAdmin;
      _waiverDays = status.remainingWaiverDays;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isSettled =
        widget.slip.areAllMatchesSettled(widget.latestFixtures);
    final bool canViewPicks = _hasAccess || isSettled;

    return Card(
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: widget.slip.payoutColor, width: 1.2),
      ),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    widget.slip.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (_isAdmin)
                  _badge('ADMIN', Colors.amber)
                else if (_waiverDays > 0)
                  _badge('FREE TRIAL (${_waiverDays}d left)', Colors.teal)
                else if (isSettled)
                  _badge('SETTLED', Colors.blueGrey),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: widget.slip.payoutColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: widget.slip.payoutColor.withOpacity(0.5),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'TOTAL ODDS',
                        style: TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      Text(
                        '${widget.slip.totalOdds.toStringAsFixed(2)}x',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'POSSIBLE WIN (Ksh ${widget.slip.stake.toInt()} Stake)',
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                      Text(
                        'Ksh ${widget.slip.potentialPayout.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: widget.slip.payoutColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(color: Color(0xFF008080)),
                ),
              )
            else if (canViewPicks)
              ...widget.slip.selections.map(
                (sel) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              sel['match'] ?? '',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              sel['prediction'] ?? '',
                              style: const TextStyle(
                                color: Color(0xFF008080),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${sel['odds']}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.lock_outline,
                        color: Color(0xFF008080), size: 32),
                    const SizedBox(height: 8),
                    Text(
                      '${widget.slip.selections.length} High-Probability Picks Locked',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Unlock now to view matches & predictions before kickoff, or view free once settled.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF008080),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.vpn_key, size: 18),
                      label: const Text('Unlock Slip (From Ksh 50)'),
                      onPressed: () {
                        showSlipSubscriptionSheet(context, () {
                          _verifyAccess();
                        });
                      },
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
