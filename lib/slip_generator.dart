import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'fixture_model.dart';
import 'notification_service.dart';
import 'pick_evaluator.dart';
import 'slip_access_manager.dart';
import 'slip_subscription_sheet.dart';

//=================
// SlipEvaluation
//=================
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

/// Index fixtures by their key for fast lookup.
Map<String, dynamic> _indexFixtures(List<dynamic> fixtures) {
  final Map<String, dynamic> map = {};
  for (final f in fixtures) {
    if (f.key != null) map[f.key.toString()] = f;
  }
  return map;
}

//=================
// GeneratedSlip
//=================
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
        id = id ?? _defaultId(),
        potentialPayout = potentialPayout ??
            double.parse((totalOdds * stake).toStringAsFixed(2));

  /// One system slip per day: sys_YYYY_M_D
  static String _defaultId() {
    final d = DateTime.now();
    return 'sys_${d.year}_${d.month}_${d.day}';
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
    final List<Map<String, dynamic>> parsedSelections = [
      for (final item in rawSelections)
        if (item is Map) Map<String, dynamic>.from(item),
    ];

    final rawId = json['id']?.toString() ?? '';

    return GeneratedSlip(
      id: rawId.isEmpty ? null : rawId,
      title: json['title']?.toString() ?? '馃敟 Prolific Value Accumulator',
      totalOdds: (json['totalOdds'] as num?)?.toDouble() ?? 0.0,
      selections: parsedSelections,
      stake: (json['stake'] as num?)?.toDouble() ?? 200.0,
      potentialPayout: (json['potentialPayout'] as num?)?.toDouble(),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  // ------------------------------------------------------------
  // Settlement
  // ------------------------------------------------------------
  bool _isMatchFinished(dynamic match) {
    try {
      if (match.effectiveIsFinished == true) return true;
    } catch (_) {}
    try {
      if (match.isFinished == true) return true;
    } catch (_) {}
    return false;
  }

  bool areAllMatchesSettled(List latestFixtures) {
    if (selections.isEmpty) return false;
    final fixtureMap = _indexFixtures(latestFixtures);

    for (final sel in selections) {
      final key = sel['fixtureKey']?.toString() ?? '';
      if (key.isEmpty) return false;
      final match = fixtureMap[key];
      if (match == null || !_isMatchFinished(match)) return false;
    }
    return true;
  }

  SlipEvaluation evaluateOutcome(List<dynamic> latestFixtures) {
    if (selections.isEmpty || !areAllMatchesSettled(latestFixtures)) {
      return const SlipEvaluation(isSettled: false, isWon: false);
    }

    final fixtureMap = _indexFixtures(latestFixtures);

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

  /// Delegates to the shared evaluator. Picks that can't be judged from the
  /// final score count as not won (same behaviour as before).
  bool _isSelectionWon(Map<dynamic, dynamic> sel, dynamic match) {
    return evaluatePick(
          pick: (sel['prediction'] ?? sel['pick'] ?? '').toString(),
          home: (match.homeTeam ?? '').toString(),
          away: (match.awayTeam ?? '').toString(),
          score: (match.actualScore ?? '').toString(),
        ) ==
        true;
  }
}

//=================
// _LeagueRule
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

//=================
// _Candidate
//=================
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
  // Slip targets
  static const double _targetMinOdds = 5.0;
  static const double _targetMaxOdds = 10.0;
  static const double _comboMinOdds = 2.0;

  // Candidate thresholds
  static const double _dcMinSideProb = 55.0;
  static const double _dc12MinProb = 72.0;
  static const double _dcMaxProb = 95.0;
  static const double _tipMinProb = 62.0;
  static const double _over25MinProb = 65.0;
  static const double _bttsMinProb = 65.0;

  // ------------------------------------------------------------
  // Normalisers
  // ------------------------------------------------------------
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

  /// Maps a raw competition name to a league that has its own rules. Shared
  /// with the Prolific log so both use the same league names.
  static String normalizeLeague(String rawLeague) {
    final String l = rawLeague.trim().toLowerCase();
    if (l.contains('eredivisie')) return 'Eredivisie';
    if (l.contains('serie a')) return 'Serie A';
    if (l.contains('ligue 1')) return 'Ligue 1';
    // Exact names only, so "Kenyan Premier League" or "Russian Premier
    // League" are not treated as the English league.
    if (l == 'premier league' ||
        l == 'epl' ||
        l == 'english premier league' ||
        l.contains('england - premier')) {
      return 'Premier League';
    }
    if (l.contains('bundesliga')) return 'Bundesliga';
    return rawLeague.trim().isEmpty ? 'Other' : rawLeague.trim();
  }

  static _LeagueRule _ruleForLeague(String normalizedLeague) {
    switch (normalizedLeague) {
      case 'Eredivisie':
        return const _LeagueRule(
          preferredMarkets: {'Over 1.5', 'Double Chance'},
          blockedMarkets: {'Under 3.5'},
          marketBonuses: {'Over 1.5': 6.0, 'Double Chance': 4.5},
          minOver15Prob: 73.0,
        );

      case 'Serie A':
        return const _LeagueRule(
          preferredMarkets: {'Over 1.5', '1X2', 'Double Chance'},
          marketBonuses: {'Over 1.5': 5.0, '1X2': 3.5, 'Double Chance': 3.0},
          minOver15Prob: 73.0,
          minUnder35Prob: 76.0,
        );

      case 'Ligue 1':
        return const _LeagueRule(
          preferredMarkets: {'Over 1.5', 'Double Chance'},
          marketBonuses: {'Over 1.5': 4.5, 'Double Chance': 4.0},
          minOver15Prob: 73.0,
          minUnder35Prob: 78.0,
        );

      case 'Premier League':
        return const _LeagueRule(
          preferredMarkets: {'Over 1.5', 'Double Chance'},
          blockedMarkets: {'1X2'},
          marketBonuses: {'Over 1.5': 4.5, 'Double Chance': 4.0},
          minOver15Prob: 73.0,
          minUnder35Prob: 76.0,
        );

      case 'Bundesliga':
        return const _LeagueRule(
          preferredMarkets: {'Double Chance', 'Ov2.5'},
          blockedMarkets: {'Under 3.5'},
          marketBonuses: {'Double Chance': 3.5},
          minOver15Prob: 78.0,
        );

      default:
        return const _LeagueRule(
          preferredMarkets: {'Over 1.5', 'Double Chance'},
          marketBonuses: {'Over 1.5': 3.0, 'Double Chance': 2.5},
          minOver15Prob: 73.0,
          minUnder35Prob: 76.0,
        );
    }
  }

  // ------------------------------------------------------------
  // Probability / odds helpers
  // ------------------------------------------------------------
  /// Returns a percentage in (0, 100) or null if missing/invalid.
  static double? percent(dynamic raw) {
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

  /// Over 1.5 probability: the explicit figure, or an estimate from Over 2.5.
  /// Shared so slips and the Prolific log never disagree on it.
  static double? estimateOver15(FixtureModel f) {
    final double? explicit = percent(f.over15Goals);
    if (explicit != null) return explicit;
    final double? o25 = percent(f.over25Goals);
    return o25 == null ? null : (o25 + 16.0).clamp(55.0, 88.0).toDouble();
  }

  /// Under 3.5 probability: the explicit figure, or an estimate from Over 2.5.
  static double? estimateUnder35(FixtureModel f) {
    final double? explicit = percent(f.under35Goals);
    if (explicit != null) return explicit;
    final double? o25 = percent(f.over25Goals);
    return o25 == null
        ? null
        : (100.0 - o25 + 22.0).clamp(55.0, 86.0).toDouble();
  }

  static double _impliedOdds(double prob) {
    if (prob <= 1.0 || prob >= 100.0) return 1.25;
    return (100.0 / prob).clamp(1.15, 12.0).toDouble();
  }

  static double _round2(double v) => double.parse(v.toStringAsFixed(2));

  static bool _isSameDay(DateTime kickoff, DateTime day) {
    final DateTime local = kickoff.toLocal();
    final DateTime d = day.toLocal();
    return local.year == d.year && local.month == d.month && local.day == d.day;
  }

  static bool _passesGlobalRiskFilter({
    required String market,
    required _LeagueRule rule,
    required double? over15Prob,
    required double? bttsProb,
  }) {
    final String normalizedMarket = _normalizeMarket(market);

    if (rule.blockedMarkets.contains(normalizedMarket)) return false;

    if (normalizedMarket == 'Under 3.5') {
      if ((over15Prob ?? 0.0) >= 70.0) return false;
      if ((bttsProb ?? 0.0) >= 50.0) return false;
    }

    return true;
  }

  // ------------------------------------------------------------
  // Public entry point
  // ------------------------------------------------------------
  static GeneratedSlip? generateTargetSlip(
    List<dynamic> availableFixtures, {
    Set<String>? allowedMarkets,
    int maxLegs = 7,
    int maxLegsPerLeague = 2,
    bool strictPreferredMarketsOnly = false,
    DateTime? targetDay,
  }) {
    // Day the slip is built for (default: today).
    final DateTime day = targetDay ?? DateTime.now();

    final Set<String>? normalizedAllowed =
        (allowedMarkets == null || allowedMarkets.isEmpty)
            ? null
            : allowedMarkets.map(_normalizeMarket).toSet();

    final List<_Candidate> candidates = [];

    for (final fixture in availableFixtures) {
      if (fixture is! FixtureModel) continue;
      if (fixture.effectiveIsFinished || fixture.effectiveIsLive) continue;
      if (fixture.kickoff == null) continue;
      if (!_isSameDay(fixture.kickoff!, day)) continue;

      candidates.addAll(
        _candidatesForFixture(
          fixture,
          normalizedAllowed: normalizedAllowed,
          strictPreferredMarketsOnly: strictPreferredMarketsOnly,
        ),
      );
    }

    debugPrint(
      'candidates: ${candidates.length}, '
      'markets: ${candidates.map((c) => c.market).toSet()}',
    );

    if (candidates.isEmpty) return null;

    // Best-scored candidates first
    candidates.sort((a, b) => b.score.compareTo(a.score));

    return _selectSlip(
      candidates,
      maxLegs: maxLegs,
      maxLegsPerLeague: maxLegsPerLeague,
    );
  }
    // ------------------------------------------------------------
  // Candidate building (one fixture -> 0..n candidates)
  // ------------------------------------------------------------
  static List<_Candidate> _candidatesForFixture(
    FixtureModel fixture, {
    required Set<String>? normalizedAllowed,
    required bool strictPreferredMarketsOnly,
  }) {
    final double homeProb = fixture.homeWinProb.toDouble();
    final double drawProb = fixture.drawProb.toDouble();
    final double awayProb = fixture.awayWinProb.toDouble();
    if (homeProb <= 0 && awayProb <= 0) return const [];

    final String league = normalizeLeague(fixture.league);
    final _LeagueRule rule = _ruleForLeague(league);

    final String matchName = '${fixture.homeTeam} vs ${fixture.awayTeam}';
    final String safeKey = fixture.key ?? '';
    final String? kickoffIso = fixture.kickoff?.toIso8601String();

    final double? over25 = percent(fixture.over25Goals);
    final double? over15Prob = estimateOver15(fixture);
    final double? under35Prob = estimateUnder35(fixture);
    final double? bttsProb = percent(fixture.btts);

    final List<_Candidate> out = [];

    void add({
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
      out.add(
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
    }

    // 1. Over 1.5 Goals
    if (over15Prob != null && over15Prob >= rule.minOver15Prob) {
      add(
        market: 'Over 1.5',
        prediction: 'Over 1.5 Goals',
        odds: _impliedOdds(over15Prob),
        prob: over15Prob,
      );
    }

    // 2. Double Chance (1X / X2 / 12)
    if (homeProb >= _dcMinSideProb) {
      final double dcProb = homeProb + drawProb;
      if (dcProb < _dcMaxProb) {
        add(
          market: 'Double Chance',
          prediction: 'Double Chance: ${fixture.homeTeam} or Draw (1X)',
          odds: _impliedOdds(dcProb),
          prob: dcProb,
        );
      }
    } else if (awayProb >= _dcMinSideProb) {
      final double dcProb = awayProb + drawProb;
      if (dcProb < _dcMaxProb) {
        add(
          market: 'Double Chance',
          prediction: 'Double Chance: Draw or ${fixture.awayTeam} (X2)',
          odds: _impliedOdds(dcProb),
          prob: dcProb,
        );
      }
    }

    final double dc12Prob = homeProb + awayProb;
    if (dc12Prob >= _dc12MinProb && dc12Prob < _dcMaxProb) {
      add(
        market: 'Double Chance',
        prediction:
            'Double Chance: ${fixture.homeTeam} or ${fixture.awayTeam} (12)',
        odds: _impliedOdds(dc12Prob),
        prob: dc12Prob,
      );
    }

    // 3. 1X2 / Tip
    final double tipProb = fixture.tipProb.toDouble();
    if (fixture.topTip.isNotEmpty && tipProb >= _tipMinProb) {
      final bool useBookmakerOdds =
          fixture.odds > 0 && fixture.topTip.toLowerCase().contains('win');
      add(
        market: '1X2',
        prediction: fixture.topTip,
        odds: useBookmakerOdds ? fixture.odds : _impliedOdds(tipProb),
        prob: tipProb,
      );
    }

    // 4. Under 3.5 Goals
    if (under35Prob != null && under35Prob >= rule.minUnder35Prob) {
      add(
        market: 'Under 3.5',
        prediction: 'Under 3.5 Goals',
        odds: _impliedOdds(under35Prob),
        prob: under35Prob,
      );
    }

    // 5. Over 2.5 Goals
    if (over25 != null && over25 >= _over25MinProb) {
      add(
        market: 'Ov2.5',
        prediction: 'Over 2.5 Goals',
        odds: _impliedOdds(over25),
        prob: over25,
      );
    }

    // 6. GG (BTTS)
    if (bttsProb != null && bttsProb >= _bttsMinProb) {
      add(
        market: 'GG',
        prediction: 'Both Teams To Score: Yes',
        odds: _impliedOdds(bttsProb),
        prob: bttsProb,
      );
    }

    return out;
  }

  // ------------------------------------------------------------
  // Slip selection
  // ------------------------------------------------------------
  static Map<String, dynamic> _toSelectionMap(_Candidate c) => {
        'fixtureKey': c.fixtureKey,
        'league': c.league,
        'match': c.match,
        'market': c.market,
        'prediction': c.prediction,
        'odds': _round2(c.odds),
        'kickoff': c.kickoffIso,
      };

  static GeneratedSlip _buildSlip(
    String title,
    List<_Candidate> picks,
    double odds,
  ) {
    return GeneratedSlip(
      title: title,
      totalOdds: _round2(odds),
      selections: picks.map(_toSelectionMap).toList(),
    );
  }

  static GeneratedSlip? _selectSlip(
    List<_Candidate> candidates, {
    required int maxLegs,
    required int maxLegsPerLeague,
  }) {
    final List<_Candidate> picks = [];
    final Set<String> usedMatches = {};
    final Map<String, int> leagueCounts = {};
    double odds = 1.0;

    // Pass 1 respects the per-league cap (spreads risk across leagues).
    // Pass 2 drops the cap so quiet days with few leagues still work.
    for (final enforceLeagueCap in [true, false]) {
      for (final c in candidates) {
        if (picks.length >= maxLegs) break;
        if (usedMatches.contains(c.match)) continue; // 1 pick per match
        if (enforceLeagueCap &&
            (leagueCounts[c.league] ?? 0) >= maxLegsPerLeague) {
          continue;
        }
        if (odds * c.odds > _targetMaxOdds) continue;

        picks.add(c);
        usedMatches.add(c.match);
        leagueCounts[c.league] = (leagueCounts[c.league] ?? 0) + 1;
        odds *= c.odds;

        if (odds >= _targetMinOdds && odds <= _targetMaxOdds) {
          return _buildSlip('🔥 Prolific Value Accumulator', picks, odds);
        }
      }
    }

    if (picks.isEmpty) return null;

    if (odds >= _comboMinOdds) {
      return _buildSlip(
        odds <= _targetMinOdds
            ? '💎  Daily Value Combo (2-5x)'
            : '🎯  Custom Combo Slip',
        picks,
        odds,
      );
    }

    return _buildSlip('⚡  Light Slate Combo', picks, odds);
  }
}

//=================================
// ProtectedSystemSlipCard
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
  static const Color _teal = Color(0xFF008080);

  bool _hasAccess = false;
  bool _isAdmin = false;
  int _waiverDays = 0;
  bool _loading = true;
  bool _notified = false;

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

  /// Sends the settled notification once per card instance.
  void _notifyIfSettled(SlipEvaluation evaluation) {
    if (!evaluation.isSettled || _notified) return;
    _notified = true;

    final slip = widget.slip;
    final double amount = evaluation.isWon
        ? (slip.potentialPayout > 0
            ? slip.potentialPayout
            : slip.stake * slip.totalOdds)
        : slip.stake;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.notifySlipSettled(
        slipId: slip.id,
        title: slip.title,
        isWon: evaluation.isWon,
        stake: slip.stake,
        payoutOrLoss: amount,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final slip = widget.slip;
    final evaluation = slip.evaluateOutcome(widget.latestFixtures);
    final bool canViewPicks = _hasAccess || evaluation.isSettled;

    _notifyIfSettled(evaluation);

    return Card(
      color: const Color(0xFF1E1E1E),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: slip.payoutColor, width: 1.2),
      ),
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(evaluation),
            const SizedBox(height: 12),
            _buildOddsPanel(),
            const SizedBox(height: 14),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(color: _teal),
                ),
              )
            else if (canViewPicks)
              ..._buildPickRows(evaluation)
            else
              _buildLockedPanel(),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // UI pieces
  // ------------------------------------------------------------
  Widget _buildHeader(SlipEvaluation evaluation) {
    final Widget? badge = _statusBadge(evaluation);
    return Row(
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
        if (badge != null) badge,
      ],
    );
  }

  Widget? _statusBadge(SlipEvaluation e) {
    if (_isAdmin) return _badge('ADMIN', Colors.amber);
    if (_waiverDays > 0) {
      return _badge('FREE TRIAL ($_waiverDays d left)', Colors.teal);
    }
    if (e.isWon) return _badge('WON', Colors.green);
    if (e.isLost) return _badge('LOST', Colors.red);
    if (e.isSettled) return _badge('SETTLED', Colors.blueGrey);
    return null;
  }

  Widget _buildOddsPanel() {
    final slip = widget.slip;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: slip.payoutColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: slip.payoutColor.withOpacity(0.35)),
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
                '${slip.totalOdds.toStringAsFixed(2)}x',
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
                'POSSIBLE WIN (Ksh ${slip.stake.toStringAsFixed(0)})',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              Text(
                'Ksh ${slip.potentialPayout.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: slip.payoutColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPickRows(SlipEvaluation evaluation) {
    return widget.slip.selections.asMap().entries.map((entry) {
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
                    style: const TextStyle(color: _teal, fontSize: 13),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
    }).toList();
  }

  Widget _buildLockedPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black38,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          const Icon(Icons.lock_outline, color: _teal, size: 32),
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
              backgroundColor: _teal,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.vpn_key, size: 18),
            label: const Text('Unlock Slip (From Ksh 50)'),
            onPressed: () {
            showSlipSubscriptionSheet(context, _verifyAccess);
             },
           ),
          ],
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

  
