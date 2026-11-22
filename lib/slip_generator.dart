import 'package:flutter/material.dart';
import 'fixture_model.dart';
import 'slip_access_manager.dart';
import 'slip_subscription_sheet.dart';

//==================
// GeneratedSlip
//==================

class SlipEvaluation {
  final bool isSettled;
  final bool isWon;
  final List<dynamic> legs;

  const SlipEvaluation({
    required this.isSettled,
    required this.isWon,
    this.legs = const [],
  });

  bool get isLost => isSettled && !isWon;
}

class GeneratedSlip {
  final String id;
  final String title;
  final double totalOdds;
  final List<dynamic> selections;
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
    final Map<String, dynamic> fixtureMap = {};
    for (final f in latestFixtures) {
      if (f.key != null) fixtureMap[f.key.toString()] = f;
    }
    for (final sel in selections) {
      final key = sel['fixtureKey']?.toString() ?? '';
      if (key.isEmpty) return false;
      final match = fixtureMap[key];
      if (match == null || match.isFinished != true) return false;
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
    final rawSelections = json['selections'] as List? ?? const [];
    final parsedSelections = <Map<String, dynamic>>[];
    for (final item in rawSelections) {
      if (item is Map) {
        parsedSelections.add(Map<String, dynamic>.from(item));
      }
    }
    return GeneratedSlip(
      id: (json['id'] == null || json['id'].toString().isEmpty)
          ? null
          : json['id'].toString(),
      title: json['title']?.toString() ?? '🔥 Prolific Value Accumulator',
      totalOdds: (json['totalOdds'] as num?)?.toDouble() ?? 0.0,
      selections: parsedSelections,
      stake: (json['stake'] as num?)?.toDouble() ?? 200.0,
      potentialPayout: (json['potentialPayout'] as num?)?.toDouble(),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  SlipEvaluation evaluateOutcome(List<dynamic> latestFixtures) {
    if (selections.isEmpty || !areAllMatchesSettled(latestFixtures)) {
      return const SlipEvaluation(isSettled: false, isWon: false);
    }

    final Map<String, dynamic> fixtureMap = {};
    for (final f in latestFixtures) {
      if (f.key != null) fixtureMap[f.key.toString()] = f;
    }

    for (final sel in selections) {
      final key = (sel['fixtureKey'] ?? '').toString();
      final match = fixtureMap[key];
      if (match == null) {
        return const SlipEvaluation(isSettled: false, isWon: false);
      }
      if (!_isSelectionWon(sel, match)) {
        return const SlipEvaluation(isSettled: true, isWon: false);
      }
    }
    return const SlipEvaluation(isSettled: true, isWon: true);
  }
  
  bool _isSelectionWon(Map<dynamic, dynamic> sel, dynamic match) {
    // TODO: wire market/prediction logic here
    return false;
  }
}
   
//=================
// class _LeagueRule
//=================
class _LeagueRule {
  final Set<String> preferredMarkets;
  final Set<String> blockedMarkets;
  final Map<String, double> marketBonuses;
  final double minOver15Prob;
  final double minUnder35Prob;

  const _LeagueRule({
    this.preferredMarkets = const {},
    this.blockedMarkets = const {},
    this.marketBonuses = const {},
    this.minOver15Prob = 73.0,
    this.minUnder35Prob = 75.0,
  });
}

//====================
// class _Candidate
//====================
class _Candidate {
  final String fixtureKey;
  final String league;
  final String match;
  final String market;
  final String prediction;
  final double odds;
  final double prob;
  final double score;
  final String? kickoffIso;

  const _Candidate({
    required this.fixtureKey,
    this.league = '',
    required this.match,
    required this.market,
    required this.prediction,
    required this.odds,
    required this.prob,
    this.score = 0.0,
    this.kickoffIso,
  });
}

//=================
// SlipGenerator
//=================
class SlipGenerator {
  static String _normalizeMarket(String market) {
    switch (market.trim().toLowerCase()) {
      case '1x2':
      case '1x2 / tip':
        return '1X2';
      case 'double chance':
      case 'dc':
        return 'Double Chance';
      case 'gg':
      case 'btts':
      case 'both teams to score':
        return 'GG';
      case 'over 1.5':
      case 'ov1.5':
        return 'Over 1.5';
      case 'ov2.5':
      case 'over 2.5':
        return 'Ov2.5';
      case 'under 3.5':
      case 'un3.5':
        return 'Under 3.5';
      default:
        return market.trim();
    }
  }

  static String _normalizeLeague(String rawLeague) {
    final String l = rawLeague.trim().toLowerCase();
    if (l.contains('eredivisie')) return 'Eredivisie';
    if (l.contains('serie a')) return 'Serie A';
    if (l.contains('ligue 1')) return 'Ligue 1';
    if (l.contains('premier league') || l == 'epl') return 'Premier League';
    if (l.contains('bundesliga')) return 'Bundesliga';
    return rawLeague.trim().isEmpty ? 'Other' : rawLeague.trim();
  }

  static _LeagueRule _ruleForLeague(String normalizedLeague) {
    switch (normalizedLeague) {
      case 'Eredivisie':
        return const _LeagueRule(
          preferredMarkets: {'Over 1.5', 'Double Chance'},
          blockedMarkets: {'Under 3.5'},
          marketBonuses: {
            'Over 1.5': 6.0,
            'Double Chance': 4.5,
          },
          minOver15Prob: 73.0,
        );

      case 'Serie A':
        return const _LeagueRule(
          preferredMarkets: {'Over 1.5', '1X2', 'Double Chance'},
          marketBonuses: {
            'Over 1.5': 5.0,
            '1X2': 3.5,
            'Double Chance': 3.0,
          },
          minOver15Prob: 73.0,
          minUnder35Prob: 76.0,
        );

      case 'Ligue 1':
        return const _LeagueRule(
          preferredMarkets: {'Over 1.5', 'Double Chance'},
          marketBonuses: {
            'Over 1.5': 4.5,
            'Double Chance': 4.0,
          },
          minOver15Prob: 73.0,
          minUnder35Prob: 78.0,
        );

      case 'Premier League':
        return const _LeagueRule(
          preferredMarkets: {'Over 1.5', 'Double Chance'},
          blockedMarkets: {'1X2'},
          marketBonuses: {
            'Over 1.5': 4.5,
            'Double Chance': 4.0,
          },
          minOver15Prob: 73.0,
          minUnder35Prob: 76.0,
        );

      case 'Bundesliga':
        return const _LeagueRule(
          preferredMarkets: {'Double Chance', 'Ov2.5'},
          blockedMarkets: {'Under 3.5'},
          marketBonuses: {
            'Double Chance': 3.5,
          },
          minOver15Prob: 78.0,
        );

      default:
        return const _LeagueRule(
          preferredMarkets: {'Over 1.5', 'Double Chance'},
          marketBonuses: {
            'Over 1.5': 3.0,
            'Double Chance': 2.5,
          },
          minOver15Prob: 73.0,
          minUnder35Prob: 76.0,
        );
    }
  }

  static double? _percent(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) {
      final double v = raw.toDouble();
      return (v > 0 && v < 100) ? v : null;
    }
    final String cleaned = raw.toString().replaceAll('%', '').trim();
    final double? value = double.tryParse(cleaned);
    if (value == null || value <= 0 || value >= 100) return null;
    return value;
  }

  static double _impliedOdds(double prob) {
    if (prob <= 1.0 || prob >= 100.0) return 1.25;
    final double raw = 100.0 / prob;
    return raw.clamp(1.15, 12.0).toDouble();
  }

  static bool _passesGlobalRiskFilter({
    required String market,
    required _LeagueRule rule,
    required double? over15Prob,
    required double? bttsProb,
  }) {
    final String normalizedMarket = _normalizeMarket(market);

    if (rule.blockedMarkets.contains(normalizedMarket)) {
      return false;
    }

    if (normalizedMarket == 'Under 3.5') {
      if ((over15Prob ?? 0.0) >= 70.0) return false;
      if ((bttsProb ?? 0.0) >= 50.0) return false;
    }

    return true;
  }

  static GeneratedSlip? generateTargetSlip(
    List<dynamic> availableFixtures, {
    Set<String>? allowedMarkets,
    int maxLegs = 7,
    int maxLegsPerLeague = 2,
    bool strictPreferredMarketsOnly = false,
  }) {
    final DateTime now = DateTime.now();
    final List<_Candidate> candidates = [];

    final Set<String>? normalizedAllowed =
        (allowedMarkets == null || allowedMarkets.isEmpty)
            ? null
            : allowedMarkets.map(_normalizeMarket).toSet();

    for (final fixture in availableFixtures) {
      if (fixture is! FixtureModel) continue;
      if (fixture.effectiveIsFinished || fixture.effectiveIsLive) continue;
      if (fixture.kickoff == null) continue;

      final DateTime localKickoff = fixture.kickoff!.toLocal();
      if (localKickoff.year != now.year ||
          localKickoff.month != now.month ||
          localKickoff.day != now.day) {
        continue;
      }
    
      final double homeProb = fixture.homeWinProb.toDouble();
      final double drawProb = fixture.drawProb.toDouble();
      final double awayProb = fixture.awayWinProb.toDouble();
      if (homeProb <= 0 && awayProb <= 0) continue;

      final String league = _normalizeLeague(fixture.league);
      final _LeagueRule rule = _ruleForLeague(league);

      final String matchName = '${fixture.homeTeam} vs ${fixture.awayTeam}';
      final String safeKey = fixture.key ?? '';
      final String? kickoffIso = fixture.kickoff?.toIso8601String();

      final double? over25 = _percent(fixture.over25Goals);
      final double? explicitOver15 = _percent(fixture.over15Goals);
      final double? over15Prob = explicitOver15 ??
          (over25 != null
              ? (over25 + 16.0).clamp(55.0, 88.0).toDouble()
              : null);
      final double? bttsProb = _percent(fixture.btts);

      void addCandidateIfValid({
        required String market,
        required String prediction,
        required double odds,
        required double prob,
      }) {
        final String normMarket = _normalizeMarket(market);

        if (normalizedAllowed != null &&
            !normalizedAllowed.contains(normMarket)) {
          return;
        }
        if (strictPreferredMarketsOnly &&
            rule.preferredMarkets.isNotEmpty &&
            !rule.preferredMarkets.contains(normMarket)) {
          return;
        }
        if (!_passesGlobalRiskFilter(
          market: normMarket,
          rule: rule,
          over15Prob: over15Prob,
          bttsProb: bttsProb,
        )) {
          return;
        }

        final double bonus = rule.marketBonuses[normMarket] ?? 0.0;
        candidates.add(
        _Candidate(
          fixtureKey: safeKey,
          league: league,
          match: matchName,
          market: normMarket,
          prediction: prediction,
          odds: odds,
          prob: prob,
          score: prob + bonus,
          kickoffIso: kickoffIso,
        ),
      );
      // 1. Over 1.5 Goals
      if (over15Prob != null && over15Prob >= rule.minOver15Prob) {
        addCandidateIfValid(
          market: 'Over 1.5',
          prediction: 'Over 1.5 Goals',
          odds: _impliedOdds(over15Prob),
          prob: over15Prob,
        );
      }

      // 2. Double Chance (1X / X2)
      if (homeProb >= 55.0) {
        final double dcProb = homeProb + drawProb;
        if (dcProb < 95.0) {
          addCandidateIfValid(
            market: 'Double Chance',
            prediction: 'Double Chance: ${fixture.homeTeam} or Draw (1X)',
            odds: _impliedOdds(dcProb),
            prob: dcProb,
          );
        }
      } else if (awayProb >= 55.0) {
        final double dcProb = awayProb + drawProb;
        if (dcProb < 95.0) {
          addCandidateIfValid(
            market: 'Double Chance',
            prediction: 'Double Chance: Draw or ${fixture.awayTeam} (X2)',
            odds: _impliedOdds(dcProb),
            prob: dcProb,
          );
        }
      }

      // 3. 1X2 / Tip
      final double tipProb = fixture.tipProb.toDouble();
      if (fixture.topTip.isNotEmpty && tipProb >= 62.0) {
        final double odds =
            (fixture.odds > 0 && fixture.topTip.toLowerCase().contains('win'))
                ? fixture.odds
                : _impliedOdds(tipProb);

        addCandidateIfValid(
          market: '1X2',
          prediction: fixture.topTip,
          odds: odds,
          prob: tipProb,
        );
      }

      // 4. Under 3.5 Goals
      final double? explicitUnder35 = _percent(fixture.under35Goals);
      final double? under35Prob = explicitUnder35 ??
          (over25 != null
              ? (100.0 - over25 + 22.0).clamp(55.0, 86.0).toDouble()
              : null);
      if (under35Prob != null && under35Prob >= rule.minUnder35Prob) {
        addCandidateIfValid(
          market: 'Under 3.5',
          prediction: 'Under 3.5 Goals',
          odds: _impliedOdds(under35Prob),
          prob: under35Prob,
        );
      }

      // 5. Ov2.5 Goals
      if (over25 != null && over25 >= 65.0) {
        addCandidateIfValid(
          market: 'Ov2.5',
          prediction: 'Over 2.5 Goals',
          odds: _impliedOdds(over25),
          prob: over25,
        );
      }

      // 6. GG (BTTS)
      if (bttsProb != null && bttsProb >= 65.0) {
        addCandidateIfValid(
          market: 'GG',
          prediction: 'Both Teams To Score: Yes',
          odds: _impliedOdds(bttsProb),
          prob: bttsProb,
        );
      }
    }

    candidates.sort((a, b) => b.score.compareTo(a.score));

    final List<Map<String, dynamic>> selectedBets = [];
    final Set<String> usedMatches = {};
    final Map<String, int> leagueCounts = {};
    double cumulativeOdds = 1.0;

    // Pass 1: Spread across leagues (maxLegsPerLeague) + 1 pick per match
    for (final c in candidates) {
      if (selectedBets.length >= maxLegs) break;
      if (usedMatches.contains(c.match)) continue;
      if ((leagueCounts[c.league] ?? 0) >= maxLegsPerLeague) continue;
      if ((cumulativeOdds * c.odds) > 10.0) continue;

      selectedBets.add({
        'fixtureKey': c.fixtureKey,
        'league': c.league,
        'match': c.match,
        'market': c.market,
        'prediction': c.prediction,
        'odds': double.parse(c.odds.toStringAsFixed(2)),
        'kickoff': c.kickoffIso,
      });

      usedMatches.add(c.match);
      leagueCounts[c.league] = (leagueCounts[c.league] ?? 0) + 1;

      usedMatches.add(c.match);
      leagueCounts[c.league] = (leagueCounts[c.league] ?? 0) + 1;
      cumulativeOdds *= c.odds;

      if (cumulativeOdds >= 5.00 && cumulativeOdds <= 10.00) {
        return GeneratedSlip(
          title: '🔥 Prolific Value Accumulator',
          totalOdds: double.parse(cumulativeOdds.toStringAsFixed(2)),
          selections: selectedBets,
        );
      }
    }

    // Pass 2: Relax per-league cap if fewer leagues are active today
    for (final c in candidates) {
      if (selectedBets.length >= maxLegs) break;
      if (usedMatches.contains(c.match)) continue;
      if ((cumulativeOdds * c.odds) > 10.0) continue;

      selectedBets.add({
        'fixtureKey': c.fixtureKey,
        'league': c.league,
        'match': c.match,
        'market': c.market,
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
}
  
//=================================
// class ProtectedSystemSlipCard
//=================================
class ProtectedSystemSlipCard extends StatefulWidget {
  final GeneratedSlip slip;
  final List<dynamic> latestFixtures;

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
    final evaluation = widget.slip.evaluateOutcome(widget.latestFixtures);
    final bool isSettled = evaluation.isSettled ||
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
                  _badge('FREE TRIAL ($_waiverDays d left)', Colors.teal)
                else if (evaluation.isWon)
                  _badge('WON', Colors.green)
                else if (evaluation.isLost)
                  _badge('LOST', Colors.red)
                else if (isSettled)
                  _badge('SETTLED', Colors.blueGrey),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: widget.slip.payoutColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: widget.slip.payoutColor.withOpacity(0.35),
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
                        'POSSIBLE WIN (Ksh ${widget.slip.stake.toStringAsFixed(0)})',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
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
              ...widget.slip.selections.asMap().entries.map((entry) {
                final int idx = entry.key;
                final dynamic sel = entry.value;
                final legEval =
                    idx < evaluation.legs.length ? evaluation.legs[idx] : null;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              sel['match']?.toString() ?? '',
                              style: const TextStyle(color: Colors.white),
                            ),
                            Text(
                              sel['prediction']?.toString() ?? '',
                              style: const TextStyle(
                                color: Color(0xFF008080),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (legEval?.won != null) ...[
                            PredictionOutcomeBadge(won: legEval!.won),
                            const SizedBox(width: 6),
                          ],
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black45,
                              borderRadius: BorderRadius.circular(8),
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
                    ],
                  ),
                );
              })
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
                    const Icon(
                      Icons.lock_outline,
                      color: Color(0xFF008080),
                      size: 32,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${widget.slip.selections.length} High-Value Picks Locked',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Unlock now to view matches & predictions',
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
                        showSlipSubscriptionSheet(context, () async {
                          await _verifyAccess();
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
  
