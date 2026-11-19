import 'package:flutter/material.dart';
import 'fixture_model.dart';
import 'slip_access_manager.dart';
import 'slip_subscription_sheet.dart';

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
      if (match == null || match.isFinished != true) {
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

  factory GeneratedSlip.fromJson(Map<dynamic, dynamic> json) {
    final rawSelections = json['selections'] as List? ?? const [];
    final List> parsedSelections = [];
    for (final item in rawSelections) {
      if (item is Map) {
        parsedSelections.add(Map<String, dynamic>.from(item));
      }
    }

    final double totalOdds = (json['totalOdds'] as num?)?.toDouble() ?? 1.0;
    final double stake = (json['stake'] as num?)?.toDouble() ?? 200.0;

    return GeneratedSlip(
      id: json['id']?.toString(),
      title: json['title']?.toString() ?? '🔥 Prolific Value Accumulator',
      totalOdds: totalOdds,
      selections: parsedSelections,
      stake: stake,
      potentialPayout: (json['potentialPayout'] as num?)?.toDouble(),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class _Candidate {
  final String fixtureKey;
  final String match;
  final String market;
  final String prediction;
  final double odds;
  final double prob;
  final String? kickoffIso;

  const _Candidate(
    this.fixtureKey,
    this.match,
    this.market,
    this.prediction,
    this.odds,
    this.prob,
    this.kickoffIso,
  );
}

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
      case 'half with most goals':
        return 'Half with Most Goals';
      case 'corner 1x2':
      case 'corners 1x2':
        return 'Corner 1X2';
      case 'cards 1x2':
        return 'Cards 1X2';
      case 'half with most cards':
        return 'Half with Most Cards';
      case 'player to score':
      case 'anytime goalscorer':
        return 'Player to Score';
      default:
        return market.trim();
    }
  }

  static double? _percent(dynamic raw) {
    if (raw == null) return null;
    if (raw is num) {
      final v = raw.toDouble();
      return (v > 0 && v < 100) ? v : null;
    }
    final cleaned = raw.toString().replaceAll('%', '').trim();
    final value = double.tryParse(cleaned);
    if (value == null || value <= 0 || value >= 100) return null;
    return value;
  }

  static double _impliedOdds(double prob) {
    if (prob <= 1.0 || prob >= 100.0) return 1.25;
    final raw = 100.0 / prob;
    return raw.clamp(1.15, 12.0).toDouble();
  }

  static dynamic _readField(dynamic obj, List<String> names) {
    if (obj == null) return null;
    if (obj is Map) {
      for (final name in names) {
        if (obj.containsKey(name) && obj[name] != null) return obj[name];
      }
      return null;
    }
    final dynamic dyn = obj;
    for (final name in names) {
      try {
        switch (name) {
          case 'over15Goals':
            if (dyn.over15Goals != null) return dyn.over15Goals;
            break;
          case 'under35Goals':
            if (dyn.under35Goals != null) return dyn.under35Goals;
            break;
          case 'firstHalfGoalsProb':
            if (dyn.firstHalfGoalsProb != null) return dyn.firstHalfGoalsProb;
            break;
          case 'secondHalfGoalsProb':
            if (dyn.secondHalfGoalsProb != null) return dyn.secondHalfGoalsProb;
            break;
          case 'homeCardsProb':
            if (dyn.homeCardsProb != null) return dyn.homeCardsProb;
            break;
          case 'drawCardsProb':
            if (dyn.drawCardsProb != null) return dyn.drawCardsProb;
            break;
          case 'awayCardsProb':
            if (dyn.awayCardsProb != null) return dyn.awayCardsProb;
            break;
          case 'firstHalfCardsProb':
            if (dyn.firstHalfCardsProb != null) return dyn.firstHalfCardsProb;
            break;
          case 'secondHalfCardsProb':
            if (dyn.secondHalfCardsProb != null) return dyn.secondHalfCardsProb;
            break;
          case 'anytimeScorers':
            if (dyn.anytimeScorers != null) return dyn.anytimeScorers;
            break;
          case 'keyPlayers':
            if (dyn.keyPlayers != null) return dyn.keyPlayers;
            break;
          case 'players':
            if (dyn.players != null) return dyn.players;
            break;
        }
      } catch (_) {
        // Property not present on object; continue safely.
      }
    }
    return null;
  }

  static void _addPlayerScorerCandidates({
    required FixtureModel fixture,
    required String safeKey,
    required String matchName,
    required String? kickoffIso,
    required double homeProb,
    required double awayProb,
    required List<_Candidate> candidates,
  }) {
    final rawScorers = _readField(
      fixture,
      ['anytimeScorers', 'keyPlayers', 'players'],
    );

    bool addedExplicit = false;
    if (rawScorers is List) {
      for (final item in rawScorers) {
        if (item is PlayerScorerTip) {
          if (item.name.trim().isNotEmpty && item.goalProb >= 25.0) {
            final double p = item.goalProb.clamp(25.0, 85.0).toDouble();
            candidates.add(
              _Candidate(
                safeKey,
                matchName,
                'Player to Score',
                'Anytime Goalscorer: ${item.name.trim()}',
                item.odds > 0 ? item.odds : _impliedOdds(p),
                p,
                kickoffIso,
              ),
            );
            addedExplicit = true;
          }
        } else if (item is Map) {
          final name = (item['name'] ?? item['player'] ?? '').toString().trim();
          final prob = _percent(item['prob'] ?? item['goalProb']) ?? 35.0;
          if (name.isNotEmpty && prob >= 25.0) {
            candidates.add(
              _Candidate(
                safeKey,
                matchName,
                'Player to Score',
                'Anytime Goalscorer: $name',
                _impliedOdds(prob),
                prob,
                kickoffIso,
              ),
            );
            addedExplicit = true;
          }
        } else if (item is String && item.trim().isNotEmpty) {
          const prob = 36.0;
          candidates.add(
            _Candidate(
              safeKey,
              matchName,
              'Player to Score',
              'Anytime Goalscorer: ${item.trim()}',
              _impliedOdds(prob),
              prob,
              kickoffIso,
            ),
          );
          addedExplicit = true;
        }
      }
    }

    if (!addedExplicit) {
      if (homeProb >= 55.0) {
        final double scorerProb =
            (homeProb * 0.62).clamp(28.0, 52.0).toDouble();
        candidates.add(
          _Candidate(
            safeKey,
            matchName,
            'Player to Score',
            'Anytime Goalscorer: ${fixture.homeTeam} Lead Attacker',
            _impliedOdds(scorerProb),
            scorerProb,
            kickoffIso,
          ),
        );
      } else if (awayProb >= 55.0) {
        final double scorerProb =
            (awayProb * 0.62).clamp(28.0, 52.0).toDouble();
        candidates.add(
          _Candidate(
            safeKey,
            matchName,
            'Player to Score',
            'Anytime Goalscorer: ${fixture.awayTeam} Lead Attacker',
            _impliedOdds(scorerProb),
            scorerProb,
            kickoffIso,
          ),
        );
      }
    }
  }

  static GeneratedSlip? generateTargetSlip(
    List<dynamic> availableFixtures, {
    Set<String>? allowedMarkets,
  }) {
    final now = DateTime.now();
    final List<_Candidate> candidates = [];

    final Set<String>? normalizedAllowed =
        (allowedMarkets == null || allowedMarkets.isEmpty)
            ? null
            : allowedMarkets.map(_normalizeMarket).toSet();

    bool allows(String market) {
      if (normalizedAllowed == null) return true;
      return normalizedAllowed.contains(_normalizeMarket(market));
    }

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
      final String safeKey = fixture.key ?? '';
      final String? kickoffIso = fixture.kickoff?.toIso8601String();

      // 1. 1X2 / Tip
      final double tipProb = fixture.tipProb.toDouble();
      if (allows('1X2') && fixture.topTip.isNotEmpty && tipProb > 0) {
        final double odds =
            (fixture.odds > 0 && fixture.topTip.toLowerCase().contains('win'))
                ? fixture.odds
                : _impliedOdds(tipProb);

        candidates.add(
          _Candidate(
            safeKey,
            matchName,
            '1X2',
            fixture.topTip,
            odds,
            tipProb,
            kickoffIso,
          ),
        );
      }

      // 2. Double Chance
      if (allows('Double Chance')) {
        if (homeProb >= 55.0) {
          final double dcProb = homeProb + drawProb;
          if (dcProb < 95.0) {
            candidates.add(
              _Candidate(
                safeKey,
                matchName,
                'Double Chance',
                'Double Chance: ${fixture.homeTeam} or Draw (1X)',
                _impliedOdds(dcProb),
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
                safeKey,
                matchName,
                'Double Chance',
                'Double Chance: Draw or ${fixture.awayTeam} (X2)',
                _impliedOdds(dcProb),
                dcProb,
                kickoffIso,
              ),
            );
          }
        }
      }

      // 3. Over 1.5 Goals
      final double? over25 = _percent(fixture.over25Goals);
      if (allows('Over 1.5')) {
        final double? explicitOver15 =
            _percent(_readField(fixture, ['over15Goals']));
        final double? over15Prob = explicitOver15 ??
            (over25 != null
                ? (over25 + 16.0).clamp(55.0, 88.0).toDouble()
                : null);
        if (over15Prob != null && over15Prob >= 55.0) {
          candidates.add(
            _Candidate(
              safeKey,
              matchName,
              'Over 1.5',
              'Over 1.5 Goals',
              _impliedOdds(over15Prob),
              over15Prob,
              kickoffIso,
            ),
          );
        }
      }

      // 4. Under 3.5 Goals
      if (allows('Under 3.5')) {
        final double? explicitUnder35 =
            _percent(_readField(fixture, ['under35Goals']));
        final double? under35Prob = explicitUnder35 ??
            (over25 != null
                ? (100.0 - over25 + 22.0).clamp(55.0, 86.0).toDouble()
                : null);
        if (under35Prob != null && under35Prob >= 55.0) {
          candidates.add(
            _Candidate(
              safeKey,
              matchName,
              'Under 3.5',
              'Under 3.5 Goals',
              _impliedOdds(under35Prob),
              under35Prob,
              kickoffIso,
            ),
          );
        }
      }

      // 5. Ov2.5 Goals
      if (allows('Ov2.5') && over25 != null && over25 >= 55.0) {
        candidates.add(
          _Candidate(
            safeKey,
            matchName,
            'Ov2.5',
            'Over 2.5 Goals',
            _impliedOdds(over25),
            over25,
            kickoffIso,
          ),
        );
      }

      // 6. GG (BTTS)
      final double? btts = _percent(fixture.btts);
      if (allows('GG') && btts != null && btts >= 55.0) {
        candidates.add(
          _Candidate(
            safeKey,
            matchName,
            'GG',
            'Both Teams To Score: Yes',
            _impliedOdds(btts),
            btts,
            kickoffIso,
          ),
        );
      }

      // 7. Half with Most Goals (only when half probabilities are present)
      if (allows('Half with Most Goals')) {
        final double? h1Prob =
            _percent(_readField(fixture, ['firstHalfGoalsProb']));
        final double? h2Prob =
            _percent(_readField(fixture, ['secondHalfGoalsProb']));
        if (h1Prob != null || h2Prob != null) {
          final double p1 = h1Prob ?? 0.0;
          final double p2 = h2Prob ?? 0.0;
          if (p2 >= p1 && p2 >= 50.0) {
            candidates.add(
              _Candidate(
                safeKey,
                matchName,
                'Half with Most Goals',
                'Half with Most Goals: 2nd Half',
                _impliedOdds(p2),
                p2,
                kickoffIso,
              ),
            );
          } else if (p1 > p2 && p1 >= 50.0) {
            candidates.add(
              _Candidate(
                safeKey,
                matchName,
                'Half with Most Goals',
                'Half with Most Goals: 1st Half',
                _impliedOdds(p1),
                p1,
                kickoffIso,
              ),
            );
          }
        }
      }

      // 8. Cards 1X2 (only when card probabilities are present)
      if (allows('Cards 1X2')) {
        final double? homeCardsProb =
            _percent(_readField(fixture, ['homeCardsProb']));
        final double? awayCardsProb =
            _percent(_readField(fixture, ['awayCardsProb']));
        final double? drawCardsProb =
            _percent(_readField(fixture, ['drawCardsProb']));

        if (homeCardsProb != null ||
            awayCardsProb != null ||
            drawCardsProb != null) {
          final double ph = homeCardsProb ?? 0.0;
          final double pa = awayCardsProb ?? 0.0;
          final double pd = drawCardsProb ?? 0.0;

          if (ph >= pa && ph >= pd && ph >= 40.0) {
            candidates.add(
              _Candidate(
                safeKey,
                matchName,
                'Cards 1X2',
                'Cards 1X2: ${fixture.homeTeam} (1)',
                _impliedOdds(ph),
                ph,
                kickoffIso,
              ),
            );
          } else if (pa > ph && pa >= pd && pa >= 40.0) {
            candidates.add(
              _Candidate(
                safeKey,
                matchName,
                'Cards 1X2',
                'Cards 1X2: ${fixture.awayTeam} (2)',
                _impliedOdds(pa),
                pa,
                kickoffIso,
              ),
            );
          }
        }
      }

      // 9. Half with Most Cards (only when half card probabilities are present)
      if (allows('Half with Most Cards')) {
        final double? h1Cards =
            _percent(_readField(fixture, ['firstHalfCardsProb']));
        final double? h2Cards =
            _percent(_readField(fixture, ['secondHalfCardsProb']));
        if (h1Cards != null || h2Cards != null) {
          final double c1 = h1Cards ?? 0.0;
          final double c2 = h2Cards ?? 0.0;
          if (c2 >= c1 && c2 >= 50.0) {
            candidates.add(
              _Candidate(
                safeKey,
                matchName,
                'Half with Most Cards',
                'Half with Most Cards: 2nd Half',
                _impliedOdds(c2),
                c2,
                kickoffIso,
              ),
            );
          } else if (c1 > c2 && c1 >= 50.0) {
            candidates.add(
              _Candidate(
                safeKey,
                matchName,
                'Half with Most Cards',
                'Half with Most Cards: 1st Half',
                _impliedOdds(c1),
                c1,
                kickoffIso,
              ),
            );
          }
        }
      }

      // 10. Player to Score
      if (allows('Player to Score')) {
        _addPlayerScorerCandidates(
          fixture: fixture,
          safeKey: safeKey,
          matchName: matchName,
          kickoffIso: kickoffIso,
          homeProb: homeProb,
          awayProb: awayProb,
          candidates: candidates,
        );
      }
    }

    candidates.sort((a, b) => b.prob.compareTo(a.prob));

    final List> selectedBets = [];.
    final Set<String> usedMatches = {};
    double cumulativeOdds = 1.0;

    for (final c in candidates) {
      if (usedMatches.contains(c.match)) continue;
      if ((cumulativeOdds * c.odds) > 14.0) continue;

      selectedBets.add({
        'fixtureKey': c.fixtureKey,
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

    for (final c in candidates) {
      bool alreadyUsed = false;
      for (final s in selectedBets) {
        if (s['match'] == c.match && s['prediction'] == c.prediction) {
          alreadyUsed = true;
          break;
        }
      }
      if (alreadyUsed) continue;
      if ((cumulativeOdds * c.odds) > 14.0) continue;

      selectedBets.add({
        'fixtureKey': c.fixtureKey,
        'match': c.match,
        'market': c.market,
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
                  _badge('FREE TRIAL ($_waiverDays d left)', Colors.teal)
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
                        'POSSIBLE WIN (Ksh ${(widget.slip.stake.toInt() * widget.slip.totalOdds).toStringAsFixed(2)})',
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
                              sel['match']?.toString() ?? '',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
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
                    const Icon(
                      Icons.lock_outline,
                      color: Color(0xFF008080),
                      size: 32,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${widget.slip.selections.length} High-Probability Picks locked',
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
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
