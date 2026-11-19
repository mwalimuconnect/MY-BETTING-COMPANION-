// ---------------------------------------------------------------------------
// Fixture & market prediction models
// ---------------------------------------------------------------------------
class H2HEntry {
  final String date;
  final String home;
  final String away;
  final String score;

  const H2HEntry({
    required this.date,
    required this.home,
    required this.away,
    required this.score,
  });

  factory H2HEntry.fromJson(Map<String, dynamic> json) {
    return H2HEntry(
      date: json['date']?.toString() ?? '',
      home: json['home']?.toString() ?? '',
      away: json['away']?.toString() ?? '',
      score: json['score']?.toString() ?? '',
    );
  }
}

class PlayerScorerTip {
  final String name;
  final String team;
  final double goalProb;
  final double odds;

  const PlayerScorerTip({
    required this.name,
    required this.team,
    required this.goalProb,
    this.odds = 0.0,
  });

  factory PlayerScorerTip.fromJson(Map<String, dynamic> json) {
    final double prob = FixtureModel._d(
      json['goalProb'] ?? json['prob'] ?? json['probability'],
      0.0,
    );
    final double rawOdds = FixtureModel._d(json['odds'], 0.0);
    return PlayerScorerTip(
      name: json['name']?.toString() ?? json['player']?.toString() ?? '',
      team: json['team']?.toString() ?? '',
      goalProb: prob,
      odds: rawOdds > 0 ? rawOdds : (prob > 0 ? (100 / prob) : 0.0),
    );
  }
}

class FixtureModel {
  final String? key;
  final String homeTeam;
  final String awayTeam;
  final DateTime? kickoff;
  final DateTime? time; // Alias for kickoff required by UI
  final bool isLive;
  final bool isFinished;
  double odds; // 0 = no real bookmaker odds available (mutable so live odds can be mapped)
  final String prediction; // same as topTip
  final String league;

  // UI properties
  final bool hasPrediction;
  final String topTip; // empty when the model has no clear tip
  final double tipProb; // 0 when there is no tip
  final double homeWinProb;
  final double drawProb;
  final double awayWinProb;

  // Extra data from the server (all optional)
  final String utcDate; // ISO kickoff time (UTC)
  final String competitionCode;
  final String dateLabel; // e.g. "Thu 19 Nov"
  final String kickoffTime; // e.g. "01:30 EAT"
  final String actualScore; // e.g. "2-1", or "Pending"
  final List<String> homeForm;
  final List<String> awayForm;
  final List<H2HEntry> h2h;
  final String over25Goals;
  final String btts;
  final String cardRisk;
  final bool isProlific;
  final bool isSample;
  final bool isEstimate;
  final bool? predictionCorrect;
  bool isSaved;

  // Extended market fields (parsed if sent by backend, otherwise null/empty)
  final String over15Goals;
  final String under35Goals;
  final double? firstHalfGoalsProb;
  final double? secondHalfGoalsProb;
  final double? homeCardsProb;
  final double? drawCardsProb;
  final double? awayCardsProb;
  final double? firstHalfCardsProb;
  final double? secondHalfCardsProb;
  final List<PlayerScorerTip> anytimeScorers;

  FixtureModel({
    required this.key,
    required this.homeTeam,
    required this.awayTeam,
    required this.kickoff,
    required this.time,
    required this.isLive,
    required this.isFinished,
    required this.odds,
    required this.prediction,
    required this.league,
    required this.hasPrediction,
    required this.topTip,
    required this.tipProb,
    required this.homeWinProb,
    required this.drawProb,
    required this.awayWinProb,
    this.utcDate = '',
    this.competitionCode = '',
    this.dateLabel = '',
    this.kickoffTime = '',
    this.actualScore = 'Pending',
    this.homeForm = const [],
    this.awayForm = const [],
    this.h2h = const [],
    this.over25Goals = 'N/A',
    this.btts = 'N/A',
    this.cardRisk = 'N/A',
    this.isProlific = false,
    this.isSample = false,
    this.isEstimate = false,
    this.predictionCorrect,
    this.isSaved = false,
    this.over15Goals = 'N/A',
    this.under35Goals = 'N/A',
    this.firstHalfGoalsProb,
    this.secondHalfGoalsProb,
    this.homeCardsProb,
    this.drawCardsProb,
    this.awayCardsProb,
    this.firstHalfCardsProb,
    this.secondHalfCardsProb,
    this.anytimeScorers = const [],
  });

  /// Text such as "Thu 19 Nov, 01:30 EAT" (empty if the server sent no date).
  String get timeLabel {
    if (dateLabel.isEmpty) return kickoffTime;
    if (kickoffTime.isEmpty) return dateLabel;
    return '$dateLabel, $kickoffTime';
  }

  /// Tip confidence as a whole number, or null when there is no tip.
  int? get tipProbInt => tipProb > 0 ? tipProb.round() : null;

  // Convenience filters for UI
  bool get isUpcoming => !isLive && !isFinished;
  bool get isLiveMatch => isLive;
  bool get isFinishedMatch => isFinished;

  static double _d(dynamic v, double fallback) {
    if (v is num) return v.toDouble();
    if (v is String) {
      return double.tryParse(v.replaceAll('%', '').trim()) ?? fallback;
    }
    return fallback;
  }

  static double? _dOpt(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.replaceAll('%', '').trim());
    return null;
  }

  static List<String> _list(dynamic v) {
    if (v is List) return v.map((e) => e.toString()).toList();
    return <String>[];
  }

  static List<H2HEntry> _h2h(dynamic v) {
    if (v is! List) return const [];
    final out = <H2HEntry>[];
    for (final e in v) {
      if (e is Map) out.add(H2HEntry.fromJson(Map<String, dynamic>.from(e)));
    }
    return out;
  }

  static List<PlayerScorerTip> _scorers(dynamic v) {
    if (v is! List) return const [];
    final out = <PlayerScorerTip>[];
    for (final e in v) {
      if (e is Map) {
        final tip = PlayerScorerTip.fromJson(Map<String, dynamic>.from(e));
        if (tip.name.isNotEmpty) out.add(tip);
      }
    }
    return out;
  }

  factory FixtureModel.fromJson(Map<String, dynamic> j) {
    final String utc = j['utcDate']?.toString() ?? '';

    DateTime? parsedTime = DateTime.tryParse(utc);
    parsedTime ??= j['kickoff'] != null
        ? DateTime.tryParse(j['kickoff'].toString())
        : null;

    final String tip =
        j['topTip']?.toString() ?? j['prediction']?.toString() ?? '';
    final double home = _d(j['homeWinProb'], 0);
    final double draw = _d(j['drawProb'], 0);
    final double away = _d(j['awayWinProb'], 0);

    return FixtureModel(
      key: j['key']?.toString() ?? j['id']?.toString(),
      homeTeam: j['homeTeam']?.toString() ?? 'Home',
      awayTeam: j['awayTeam']?.toString() ?? 'Away',
      kickoff: parsedTime,
      time: parsedTime,
      isLive: j['isLive'] == true,
      isFinished: j['isFinished'] == true,
      odds: _d(j['odds'], 0),
      prediction: tip,
      league: j['league']?.toString() ?? 'General League',
      hasPrediction: (home + draw + away) > 0,
      topTip: tip,
      tipProb: _d(j['tipProb'], 0),
      homeWinProb: home,
      drawProb: draw,
      awayWinProb: away,
      utcDate: utc,
      competitionCode: j['competitionCode']?.toString() ?? '',
      dateLabel: j['dateLabel']?.toString() ?? '',
      kickoffTime: j['kickoffTime']?.toString() ?? '',
      actualScore: j['actualScore']?.toString() ?? 'Pending',
      homeForm: _list(j['homeForm']),
      awayForm: _list(j['awayForm']),
      h2h: _h2h(j['h2h']),
      over25Goals: j['over25Goals']?.toString() ?? 'N/A',
      btts: j['btts']?.toString() ?? 'N/A',
      cardRisk: j['cardRisk']?.toString() ?? 'N/A',
      isProlific: j['isProlific'] == true,
      isSample: j['isSample'] == true,
      isEstimate: j['isEstimate'] == true,
      predictionCorrect:
          j['predictionCorrect'] is bool ? j['predictionCorrect'] as bool : null,
      over15Goals: j['over15Goals']?.toString() ?? 'N/A',
      under35Goals: j['under35Goals']?.toString() ?? 'N/A',
      firstHalfGoalsProb: _dOpt(j['firstHalfGoalsProb']),
      secondHalfGoalsProb: _dOpt(j['secondHalfGoalsProb']),
      homeCardsProb: _dOpt(j['homeCardsProb']),
      drawCardsProb: _dOpt(j['drawCardsProb']),
      awayCardsProb: _dOpt(j['awayCardsProb']),
      firstHalfCardsProb: _dOpt(j['firstHalfCardsProb']),
      secondHalfCardsProb: _dOpt(j['secondHalfCardsProb']),
      anytimeScorers: _scorers(j['anytimeScorers']),
    );
  }

  /// Global filter helper method supporting status tabs and text search (teams & competitions)
  static List<FixtureModel> filterFixtures(
    List<FixtureModel> fixtures,
    String filter, {
    String searchQuery = '',
  }) {
    final statusQuery = filter.toLowerCase();
    var filtered = fixtures.where((f) {
      if (statusQuery == 'upcoming') return f.isUpcoming;
      if (statusQuery == 'live') return f.isLiveMatch;
      if (statusQuery == 'finished') return f.isFinishedMatch;
      return true;
    }).toList();

    final textQuery = searchQuery.toLowerCase().trim();
    if (textQuery.isNotEmpty) {
      filtered = filtered.where((f) {
        return f.homeTeam.toLowerCase().contains(textQuery) ||
            f.awayTeam.toLowerCase().contains(textQuery) ||
            f.league.toLowerCase().contains(textQuery) ||
            f.competitionCode.toLowerCase().contains(textQuery);
      }).toList();
    }

    return filtered;
  }
}

// ---------------------------------------------------------------------------
// Fixtures tab
// ---------------------------------------------------------------------------
class FixturesTab extends StatefulWidget {
  const FixturesTab({super.key});

  @override
  State<FixturesTab> createState() => _FixturesTabState();
}

class _FixturesTabState extends State<FixturesTab> {
  late Future<List<FixtureModel>> _fixturesFuture;
  Set<String> _savedKeys = {};
  String _selectedFilter = 'all';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  final Set<String> _openLeagues = {};
  final Set<String> _pinnedLeagues = {};
  final Map<String, int> _leagueEpoch = {};
  bool _singleOpen = false;

  // Time window in hours before kickoff. null = All
  int? _windowHours;
  static const List<int> _windowOptions = [3, 6, 12, 24, 72];

  // Market filters (empty = default summary view)
  final Set<String> _selectedMarkets = {};
  static const List<String> _marketOptions = [
    '1X2',
    'Double Chance',
    'GG',
    'Over 1.5',
    'Ov2.5',
    'Under 3.5',
    'Half with Most Goals',
    'Corner 1X2',
    'Cards 1X2',
    'Half with Most Cards',
    'Player to Score',
  ];

  @override
  void initState() {
    super.initState();
    _loadSavedSlips();
    _loadFixtures();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedSlips() async {
    final legs = await SlipStore.load();
    if (!mounted) return;
    setState(() {
      _savedKeys = legs.map((l) => l.key).toSet();
    });
  }

  static const Map<String, String> _leagueToOddsSport = {
    'PL': 'soccer_epl',
    'ELC': 'soccer_efl_champ',
    'BL1': 'soccer_germany_bundesliga',
    'SA': 'soccer_italy_serie_a',
    'PD': 'soccer_spain_la_liga',
    'FL1': 'soccer_france_ligue_one',
    'DED': 'soccer_netherlands_eredivisie',
    'PPL': 'soccer_portugal_primeira_liga',
    'BSA': 'soccer_brazil_campeonato',
    'CL': 'soccer_uefa_champs_league',
    'MLS': 'soccer_usa_mls',
    'ALE': 'soccer_australia_aleague',
    'ARG': 'soccer_argentina_primera_division',
  };

  void _loadFixtures() {
    setState(() {
      _fixturesFuture = ApiService.fetchFixtures().then((fixtures) async {
        final activeSports = fixtures
            .map((f) => _leagueToOddsSport[f.competitionCode.toUpperCase()])
            .whereType<String>()
            .toSet();

        if (activeSports.isNotEmpty) {
          try {
            final oddsResponses = await Future.wait(
              activeSports.map((sport) => ApiService.fetchOdds(sport)),
            );
            final allOdds = oddsResponses.expand((list) => list).toList();

            for (final fixture in fixtures) {
              final fHome = fixture.homeTeam.toLowerCase();
              for (final item in allOdds) {
                final oHome = item['home_team']?.toString().toLowerCase() ?? '';
                if (oHome.isEmpty) continue;

                if (fHome.contains(oHome) || oHome.contains(fHome)) {
                  final bookmakers = item['bookmakers'] as List? ?? [];
                  if (bookmakers.isNotEmpty) {
                    final markets = bookmakers[0]['markets'] as List? ?? [];
                    for (var market in markets) {
                      if (market['key'] == 'h2h') {
                        final outcomes = market['outcomes'] as List? ?? [];
                        for (var outcome in outcomes) {
                          if (outcome['name'].toString().toLowerCase() == oHome) {
                            fixture.odds =
                                (outcome['price'] as num?)?.toDouble() ?? 0.0;
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          } catch (e) {
            debugPrint('Failed to attach live odds: $e');
          }
        }

        await _safely(() => PredictionLog.update(fixtures));
        await _safely(() => SlipStore.settle(fixtures));
        await SuggestedSlipStore.refresh(fixtures);
        await _safely(() => NotificationService.scheduleKickoffReminders(
              fixtures,
              _savedKeys,
              AppSettings.favorites.value,
            ));
        return fixtures;
      });
    });
  }

  Future<void> _toggleSave(FixtureModel fixture) async {
    await SlipStore.toggle(fixture);
    await _loadSavedSlips();
    if (!mounted) return;
    final nowSaved = _savedKeys.contains(fixture.key);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(nowSaved ? 'Saved to slips' : 'Removed from saved slips'),
      ),
    );
  }

  // ---- market prediction helper -------------------------------------------

  bool _hasUsableText(String value) {
    final trimmed = value.trim();
    return trimmed.isNotEmpty && trimmed.toUpperCase() != 'N/A';
  }

  String? _predictionForMarket(FixtureModel fixture, String market) {
    switch (market) {
      case '1X2':
        if (fixture.topTip.isNotEmpty) return fixture.topTip;
        if (fixture.homeWinProb > 0 ||
            fixture.drawProb > 0 ||
            fixture.awayWinProb > 0) {
          if (fixture.homeWinProb >= fixture.awayWinProb &&
              fixture.homeWinProb >= fixture.drawProb) {
            return '${fixture.homeTeam} (${fixture.homeWinProb.round()}%)';
          }
          if (fixture.awayWinProb >= fixture.homeWinProb &&
              fixture.awayWinProb >= fixture.drawProb) {
            return '${fixture.awayTeam} (${fixture.awayWinProb.round()}%)';
          }
          return 'Draw (${fixture.drawProb.round()}%)';
        }
        return null;

      case 'Double Chance':
        if (fixture.homeWinProb > 0 ||
            fixture.drawProb > 0 ||
            fixture.awayWinProb > 0) {
          final homeDraw = fixture.homeWinProb + fixture.drawProb;
          final awayDraw = fixture.awayWinProb + fixture.drawProb;
          final homeAway = fixture.homeWinProb + fixture.awayProb;
          if (homeDraw >= awayDraw && homeDraw >= homeAway) {
            return '1X (${homeDraw.round()}%)';
          }
          if (awayDraw >= homeDraw && awayDraw >= homeAway) {
            return 'X2 (${awayDraw.round()}%)';
          }
          return '12 (${homeAway.round()}%)';
        }
        return null;

      case 'GG':
        return _hasUsableText(fixture.btts) ? fixture.btts : null;

      case 'Over 1.5':
        return _hasUsableText(fixture.over15Goals) ? fixture.over15Goals : null;

      case 'Ov2.5':
        return _hasUsableText(fixture.over25Goals) ? fixture.over25Goals : null;

      case 'Under 3.5':
        return _hasUsableText(fixture.under35Goals)
            ? fixture.under35Goals
            : null;

      case 'Half with Most Goals':
        final h1 = fixture.firstHalfGoalsProb;
        final h2 = fixture.secondHalfGoalsProb;
        if (h1 == null && h2 == null) return null;
        final p1 = h1 ?? 0;
        final p2 = h2 ?? 0;
        if (p1 == 0 && p2 == 0) return null;
        return p2 >= p1
            ? '2nd Half (${p2.round()}%)'
            : '1st Half (${p1.round()}%)';

      case 'Corner 1X2':
        // Requires backend corner probabilities/tip on FixtureModel
        return null;

      case 'Cards 1X2':
        final hc = fixture.homeCardsProb;
        final dc = fixture.drawCardsProb;
        final ac = fixture.awayCardsProb;
        if (hc != null || dc != null || ac != null) {
          final ph = hc ?? 0;
          final pd = dc ?? 0;
          final pa = ac ?? 0;
          if (ph >= pa && ph >= pd && ph > 0) {
            return '${fixture.homeTeam} (${ph.round()}%)';
          }
          if (pa >= ph && pa >= pd && pa > 0) {
            return '${fixture.awayTeam} (${pa.round()}%)';
          }
          if (pd > 0) return 'Draw (${pd.round()}%)';
        }
        return _hasUsableText(fixture.cardRisk) ? fixture.cardRisk : null;

      case 'Half with Most Cards':
        final c1 = fixture.firstHalfCardsProb;
        final c2 = fixture.secondHalfCardsProb;
        if (c1 == null && c2 == null) return null;
        final p1 = c1 ?? 0;
        final p2 = c2 ?? 0;
        if (p1 == 0 && p2 == 0) return null;
        return p2 >= p1
            ? '2nd Half (${p2.round()}%)'
            : '1st Half (${p1.round()}%)';

      case 'Player to Score':
        if (fixture.anytimeScorers.isEmpty) return null;
        final top = fixture.anytimeScorers.first;
        final probText = top.goalProb > 0 ? ' (${top.goalProb.round()}%)' : '';
        final teamText = top.team.isNotEmpty ? ' • ${top.team}' : '';
        return '${top.name}$teamText$probText';

      default:
        return null;
    }
  }

  // ---- time window filter -------------------------------------------------

  List<FixtureModel> _applyTimeWindow(List<FixtureModel> list) {
    final h = _windowHours;
    if (h == null) return list;
    final now = DateTime.now();
    final limit = now.add(Duration(hours: h));
    return list.where((f) {
      if (f.isLive) return true;
      if (f.isFinished) return false;
      final k = f.kickoff;
      if (k == null) return false;
      return k.isAfter(now) && !k.isAfter(limit);
    }).toList();
  }

  Widget _buildTimeWindows() {
    Widget item(String label, int? hours) {
      final selected = _windowHours == hours;
      return Padding(
        padding: const EdgeInsets.only(right: 4),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => setState(() => _windowHours = hours),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? kTealGreen : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                color: selected ? Colors.white : mutedText(context),
              ),
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
      child: Row(
        children: [
          for (final h in _windowOptions) item('$h h', h),
          item('All', null),
        ],
      ),
    );
  }

  Widget _buildMarketChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: _marketOptions.map((market) {
          final isSelected = _selectedMarkets.contains(market);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(market),
              selected: isSelected,
              selectedColor: kTealGreen,
              backgroundColor: cardBg(context),
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : mutedText(context),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 11,
              ),
              checkmarkColor: Colors.white,
              onSelected: (selected) {
                setState(() {
                  if (selected) {
                    _selectedMarkets.add(market);
                  } else {
                    _selectedMarkets.remove(market);
                  }
                });
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  // ---- league open/close/pin logic ----------------------------------------

  void _setAllLeagues(List<String> leagues, bool open) {
    setState(() {
      for (final l in leagues) {
        if (open) {
          _openLeagues.add(l);
        } else {
          _openLeagues.remove(l);
        }
        _leagueEpoch[l] = (_leagueEpoch[l] ?? 0) + 1;
      }
    });
  }

  void _onLeagueToggled(String league, bool open) {
    setState(() {
      if (open) {
        if (_singleOpen) {
          for (final other in _openLeagues.where((l) => l != league).toList()) {
            _openLeagues.remove(other);
            _leagueEpoch[other] = (_leagueEpoch[other] ?? 0) + 1;
          }
        }
        _openLeagues.add(league);
      } else {
        _openLeagues.remove(league);
      }
    });
  }

  void _togglePin(String league) {
    setState(() {
      if (!_pinnedLeagues.remove(league)) _pinnedLeagues.add(league);
    });
  }

  // ---- search + filter chips ----------------------------------------------

  Widget _buildSearchAndFilters() {
    const filters = ['All', 'Upcoming', 'Live', 'Finished'];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            onChanged: (val) =>
                setState(() => _searchQuery = val.trim().toLowerCase()),
            decoration: InputDecoration(
              hintText: 'Search team or competition (e.g., Barcelona , EPL)...',
              hintStyle: TextStyle(fontSize: 13, color: mutedText(context)),
              prefixIcon: const Icon(Icons.search, color: kTealGreen, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: cardBg(context),
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: kTealGreen.withOpacity(0.3)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: kTealGreen.withOpacity(0.2)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: filters.map((filter) {
                final key = filter.toLowerCase();
                final isSelected = _selectedFilter == key;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(filter),
                    selected: isSelected,
                    selectedColor: kTealGreen,
                    backgroundColor: cardBg(context),
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : mutedText(context),
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 12,
                    ),
                    onSelected: (_) => setState(() => _selectedFilter = key),
                  ),
                );
              }).toList(),
            ),
          ),
          _buildTimeWindows(),
          _buildMarketChips(),
        ],
      ),
    );
  }

  // ---- expand all / one-at-a-time row -------------------------------------

  Widget _buildLeagueControls(List<String> leagues) {
    final bool allOpen =
        leagues.isNotEmpty && leagues.every(_openLeagues.contains);
    final bool showCollapse = _singleOpen ? _openLeagues.isNotEmpty : allOpen;
    final bool disabled = leagues.isEmpty || (_singleOpen && !showCollapse);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      child: Row(
        children: [
          TextButton.icon(
            onPressed:
                disabled ? null : () => _setAllLeagues(leagues, !showCollapse),
            icon: Icon(
              showCollapse ? Icons.unfold_less : Icons.unfold_more,
              size: 18,
            ),
            label: Text(showCollapse ? 'Collapse all' : 'Expand all'),
          ),
          const Spacer(),
          Text(
            'One at a time',
            style: TextStyle(fontSize: 12, color: mutedText(context)),
          ),
          Switch(
            value: _singleOpen,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: (v) {
              setState(() => _singleOpen = v);
              if (v) _setAllLeagues(leagues, false);
            },
          ),
        ],
      ),
    );
  }

  // ---- small helpers for the match flap -----------------------------------

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: kPrimary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _formDots(String label, List<String> form) {
    Color colorFor(String r) {
      switch (r.toUpperCase()) {
        case 'W':
          return Colors.green;
        case 'D':
          return Colors.orange;
        case 'L':
          return Colors.red;
        default:
          return Colors.grey;
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          if (form.isEmpty)
            Text('N/A', style: TextStyle(fontSize: 12, color: mutedText(context)))
          else
            Row(
              children: form
                  .map(
                    (r) => Container(
                      width: 20,
                      height: 20,
                      margin: const EdgeInsets.only(left: 4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colorFor(r),
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        r.toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: TextStyle(fontSize: 12, color: mutedText(context))),
          Text(v, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // ---- one match flap -----------------------------------------------------

  Widget _buildMatchTile(FixtureModel fixture, int index) {
    final isSaved = _savedKeys.contains(fixture.key);

    final String whenText = fixture.isFinished
        ? '${fixture.timeLabel.isNotEmpty ? "${fixture.timeLabel} • " : ""}FT ${fixture.actualScore}'
        : fixture.timeLabel;

    final activeMarkets = _marketOptions
        .where((m) => _selectedMarkets.contains(m))
        .toList();

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: PageStorageKey('match_${fixture.key ?? index}'),
        tilePadding: const EdgeInsets.only(left: 16, right: 8),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${fixture.homeTeam} vs ${fixture.awayTeam}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  if (whenText.isNotEmpty)
                    Text(
                      whenText,
                      style: TextStyle(fontSize: 11, color: mutedText(context)),
                    ),
                ],
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(
                isSaved ? Icons.bookmark : Icons.bookmark_border,
                color: kPrimary,
                size: 22,
              ),
              onPressed: () => _toggleSave(fixture),
              tooltip: 'Save to Slip',
            ),
          ],
        ),
        children: [
          if (activeMarkets.isNotEmpty) ...[
            _sectionTitle('Selected Markets'),
            for (final market in activeMarkets)
              _kv(
                market,
                _predictionForMarket(fixture, market) ?? 'No server data',
              ),
          ],

          // Prediction
          _sectionTitle('Prediction'),
          if (fixture.hasPrediction) ...[
            Text(
              fixture.topTip.isEmpty
                  ? 'No clear tip'
                  : 'Top Tip: ${fixture.topTip}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Home: ${fixture.homeWinProb.round()}%',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Draw: ${fixture.drawProb.round()}%',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Away: ${fixture.awayWinProb.round()}%',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ] else
            Text(
              fixture.isFinished
                  ? 'Full time: ${fixture.actualScore}'
                  : 'Analysis pending or unavailable',
              style: TextStyle(
                fontStyle: FontStyle.italic,
                color: mutedText(context),
                fontSize: 12,
              ),
            ),

          // Odds
          _sectionTitle('Odds'),
          Text(
            fixture.odds > 0
                ? fixture.odds.toStringAsFixed(2)
                : 'No bookmaker odds available',
            style: TextStyle(
              fontSize: 13,
              fontWeight: fixture.odds > 0 ? FontWeight.bold : FontWeight.normal,
              color: fixture.odds > 0 ? null : mutedText(context),
            ),
          ),

          // Form
          _sectionTitle('Form'),
          _formDots(fixture.homeTeam, fixture.homeForm),
          _formDots(fixture.awayTeam, fixture.awayForm),

          // Insights
          _sectionTitle('Insights'),
          _kv('Over 2.5 goals', fixture.over25Goals),
          _kv('Both teams to score', fixture.btts),
          _kv('Card risk', fixture.cardRisk),
          if (fixture.h2h.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Head to head',
              style: TextStyle(fontSize: 12, color: mutedText(context)),
            ),
            ...fixture.h2h.take(3).map(
                  (h) => Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '${h.date}  ${h.home} ${h.score} ${h.away}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => showMatchInsights(context, fixture),
              icon: const Icon(Icons.insights, size: 16),
              label: const Text('Full insights'),
            ),
          ),
        ],
      ),
    );
  }

  // ---- one league flap ----------------------------------------------------

  Widget _buildLeagueTile(String league, List<FixtureModel> matches) {
    final bool pinned = _pinnedLeagues.contains(league);
    final int epoch = _leagueEpoch[league] ?? 0;

    return Card(
      color: cardBg(context),
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: ValueKey('league_${league}_$epoch'),
          initiallyExpanded: _openLeagues.contains(league),
          onExpansionChanged: (open) => _onLeagueToggled(league, open),
          tilePadding: const EdgeInsets.only(left: 16, right: 12),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  '${league.toUpperCase()} (${matches.length})',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: pinned ? 'Unpin league' : 'Pin to top',
                icon: Icon(
                  pinned ? Icons.push_pin : Icons.push_pin_outlined,
                  size: 20,
                  color: pinned ? kPrimary : mutedText(context),
                ),
                onPressed: () => _togglePin(league),
              ),
            ],
          ),
          children: [
            for (int i = 0; i < matches.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              _buildMatchTile(matches[i], i),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<FixtureModel>>(
      future: _fixturesFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 12),
                  Text(
                    'Failed to load fixtures',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: mutedText(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${snapshot.error}',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: mutedText(context)),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: _loadFixtures,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Tap to Retry'),
                  ),
                ],
              ),
            ),
          );
        } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('No fixtures available right now.'));
        }

        final List<FixtureModel> fixtures = _applyTimeWindow(
          FixtureModel.filterFixtures(
            snapshot.data!,
            _selectedFilter,
            searchQuery: _searchQuery,
          ),
        );

        final Map<String, List<FixtureModel>> byLeague = {};
        for (final f in fixtures) {
          byLeague.putIfAbsent(f.league, () => []).add(f);
        }

        final leagues = byLeague.keys.toList()
          ..sort((a, b) {
            final pa = _pinnedLeagues.contains(a) ? 0 : 1;
            final pb = _pinnedLeagues.contains(b) ? 0 : 1;
            if (pa != pb) return pa - pb;
            return byLeague[b]!.length.compareTo(byLeague[a]!.length);
          });

        final String emptyText = _windowHours == null
            ? 'No matches found'
            : 'No matches in the next $_windowHours hours';

        return Column(
          children: [
            _buildSearchAndFilters(),
            _buildLeagueControls(leagues),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => _loadFixtures(),
                child: leagues.isEmpty
                    ? ListView(
                        children: [
                          const SizedBox(height: 80),
                          Center(
                            child: Text(
                              emptyText,
                              style: TextStyle(color: mutedText(context)),
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        itemCount: leagues.length,
                        itemBuilder: (context, index) => _buildLeagueTile(
                          leagues[index],
                          byLeague[leagues[index]]!,
                        ),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}
