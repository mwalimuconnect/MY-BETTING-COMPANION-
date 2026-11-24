import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_settings.dart';
import 'api_service.dart';
import 'fixture_model.dart';
import 'bankroll.dart';
import 'notification_service.dart';
import 'prediction_log.dart';
import 'slip_generator.dart';
import 'slip_store.dart';
import 'tables_screen.dart';
import 'match_insights.dart';
import 'slip_access_manager.dart';
import 'slip_subscription_sheet.dart';

const Color kTealGreen = Color(0xFF008080);
const Color kSafaricomGreen = Color(0xFF3AA335);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.load();
  await NotificationService.init();
  await NotificationService.requestPermission();
  runApp(const MyBettingCompanionApp());
}

class MyBettingCompanionApp extends StatelessWidget {
  const MyBettingCompanionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppSettings.themeMode,
      builder: (context, currentMode, _) {
        return MaterialApp(
          title: 'My Betting Companion',
          debugShowCheckedModeBanner: false,
          themeMode: currentMode,
          theme: ThemeData(
            brightness: Brightness.light,
            primaryColor: kPrimary,
            scaffoldBackgroundColor: const Color(0xFFF8F9FA),
            colorScheme: ColorScheme.fromSeed(
              seedColor: kPrimary,
              brightness: Brightness.light,
            ),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primaryColor: kPrimary,
            scaffoldBackgroundColor: const Color(0xFF12161C),
            colorScheme: ColorScheme.fromSeed(
              seedColor: kPrimary,
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
          ),
          home: const MainHomeScreen(),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Home screen
// ---------------------------------------------------------------------------
class MainHomeScreen extends StatefulWidget {
  const MainHomeScreen({super.key});

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  int _currentIndex = 0; // Starts on Bankroll (leftmost tab)
  int _tabRefreshTick = 0;

  Widget _buildCurrentTab() {
    switch (_currentIndex) {
      case 0:
        return const BankrollTab();
      case 1:
        return const FixturesTab();
      case 2:
        return PredictionLogTab(key: ValueKey('pred_$_tabRefreshTick'));
      case 3:
        return SavedSlipsTab(key: ValueKey('slips_$_tabRefreshTick'));
      case 4:
      default:
        return const TablesScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'My Betting Companion',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: isDark ? const Color(0xFF1E2228) : Colors.white,
        elevation: 1,
        actions: [
          IconButton(
            icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
            tooltip: 'Toggle Theme',
            onPressed: () {
              AppSettings.setDark(!isDark);
            },
          ),
        ],
      ),
      body: _buildCurrentTab(),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed,
        onTap: (index) => setState(() {
          _currentIndex = index;
          _tabRefreshTick++;
        }),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.account_balance_wallet),
            label: 'Bankroll',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.sports_soccer),
            label: 'Fixtures',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'Prediction',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bookmark),
            label: 'Saved Slips',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.leaderboard),
            label: 'Standings',
          ),
        ],
      ),
    );
  }
}
// ---------------------------------------------------------------------------
// Suggested slip (5-10 combined odds), built automatically from fixtures daily
// ---------------------------------------------------------------------------
class SuggestedSlip {
  final String title;
  final double totalOdds;
  final List> selections;
  final double stake;
  final double potentialPayout;
  final String date;

  const SuggestedSlip({
    required this.title,
    required this.totalOdds,
    required this.selections,
    this.stake = 200.0,
    double? potentialPayout,
    required this.date,
  }) : potentialPayout = potentialPayout ?? (totalOdds * stake);

  Map<String, dynamic> toJson() => {
        'title': title,
        'totalOdds': totalOdds,
        'selections': selections,
        'stake': stake,
        'potentialPayout': potentialPayout,
        'date': date,
      };

  factory SuggestedSlip.fromJson(Map<String, dynamic> j) {
    final List> sel = [];
    final raw = j['selections'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          sel.add(Map<String, dynamic>.from(e));
        }
      }
    }
    final double odds =
        j['totalOdds'] is num ? (j['totalOdds'] as num).toDouble() : 0;
    final double parsedStake =
        j['stake'] is num ? (j['stake'] as num).toDouble() : 200.0;
    final double parsedPayout = j['potentialPayout'] is num
        ? (j['potentialPayout'] as num).toDouble()
        : (odds * parsedStake);

    return SuggestedSlip(
      title: j['title']?.toString() ?? 'Suggested slip',
      totalOdds: odds,
      selections: sel,
      stake: parsedStake,
      potentialPayout: parsedPayout,
      date: j['date']?.toString() ?? SuggestedSlipStore.todayString(),
    );
  }
}

class SuggestedSlipStore {
  static const String _slipKey = 'suggested_slip_v2';
  static const String _historyKey = 'suggested_slip_history_7d_v1';
  static const String _notifiedDayKey = 'suggested_slip_notified_day';

  static const String note =
      'Odds are model-implied (100 divided by win probability), not bookmaker odds. '
      'Real bookmaker odds will be lower. No slip is guaranteed to win.';

  /// Today's date as YYYY-MM-DD (phone time).
  static String todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  static String yesterdayString() {
    final y = DateTime.now().subtract(const Duration(days: 1));
    return '${y.year}-${y.month.toString().padLeft(2, '0')}-${y.day.toString().padLeft(2, '0')}';
  }

  static String _cutoffDateString([DateTime? now]) {
    final current = now ?? DateTime.now();
    final cutoff = DateTime(current.year, current.month, current.day)
        .subtract(const Duration(days: 6)); // 7 days inclusive: today + 6 prior days
    return '${cutoff.year}-${cutoff.month.toString().padLeft(2, '0')}-${cutoff.day.toString().padLeft(2, '0')}';
  }

  static Map<String, SuggestedSlip> _prune7Days(
      Map<String, SuggestedSlip> source) {
    final cutoff = _cutoffDateString();
    final entries = source.entries
        .where((e) => e.key.compareTo(cutoff) >= 0)
        .toList()
      ..sort((a, b) => b.key.compareTo(a.key)); // Newest day first
    return {for (final e in entries) e.key: e.value};
  }

  static Future> loadHistory7Days() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_historyKey);
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};

      final map = <String, SuggestedSlip>{};
      decoded.forEach((key, value) {
        if (value is Map) {
          final slip = SuggestedSlip.fromJson(Map<String, dynamic>.from(value));
          final dateKey = slip.date.isNotEmpty ? slip.date : key.toString();
          map[dateKey] = slip;
        }
      });

      final pruned = _prune7Days(map);
      await prefs.setString(
        _historyKey,
        jsonEncode({for (final e in pruned.entries) e.key: e.value.toJson()}),
      );
      return pruned;
    } catch (e) {
      debugPrint('Could not load 7-day suggested slip history: $e');
      return {};
    }
  }

  static Future<void> saveSlipForHistory(SuggestedSlip slip) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final history = await loadHistory7Days();
      final key = slip.date.isNotEmpty ? slip.date : todayString();
      history[key] = slip;
      final pruned = _prune7Days(history);
      await prefs.setString(
        _historyKey,
        jsonEncode({for (final e in pruned.entries) e.key: e.value.toJson()}),
      );
    } catch (e) {
      debugPrint('Could not save slip to 7-day history: $e');
    }
  }

  static Future<SuggestedSlip?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_slipKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return SuggestedSlip.fromJson(Map<String, dynamic>.from(decoded));
    } catch (e) {
      debugPrint('Could not load suggested slip: $e');
      return null;
    }
  }

  /// Saves an updated custom stake for today's active suggested slip and updates 7-day history
  static Future<void> updateStake(double newStake) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final slip = await load();
      if (slip != null) {
        final updatedSlip = SuggestedSlip(
          title: slip.title,
          totalOdds: slip.totalOdds,
          selections: slip.selections,
          stake: newStake,
          date: slip.date,
        );
        await prefs.setString(_slipKey, jsonEncode(updatedSlip.toJson()));
        await saveSlipForHistory(updatedSlip);
      }
    } catch (e) {
      debugPrint('Could not update suggested slip stake: $e');
    }
  }

  /// Builds one slip per day from the latest fixtures, archives into 7-day history,
  /// and sends one notification for it.
  static Future<void> refresh(List<FixtureModel> fixtures) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final todayStr = todayString();
      final existing = await load();

      // Today's slip already exists: keep it and ensure it is in 7-day history.
      if (existing != null && existing.date == todayStr) {
        await saveSlipForHistory(existing);
        return;
      }

      // Archive yesterday's/prior slip before replacing active slot if present
      if (existing != null && existing.date.isNotEmpty) {
        await saveSlipForHistory(existing);
      }

      final generated = SlipGenerator.generateTargetSlip(fixtures);
      if (generated == null) {
        if (existing != null) await prefs.remove(_slipKey);
        return;
      }

      final slip = SuggestedSlip(
        title: generated.title,
        totalOdds: generated.totalOdds,
        selections: List.from(generated.selections),
        date: todayStr,
      );

      await prefs.setString(_slipKey, jsonEncode(slip.toJson()));
      await saveSlipForHistory(slip);

      if (prefs.getString(_notifiedDayKey) != todayStr) {
        await prefs.setString(_notifiedDayKey, todayStr);
        await NotificationService.showNow(
          slip.title,
          'New daily slip ready: ${slip.totalOdds.toStringAsFixed(2)}x. Open the Slips tab to view the picks.',
        );
      }
    } catch (e) {
      debugPrint('Suggested slip refresh failed: $e');
    }
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

  // Optional market filters (empty = all supported markets)
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
          final homeAway = fixture.homeWinProb + fixture.awayWinProb;
          if (homeDraw >= awayDraw && homeDraw >= homeAway) {
            return '1X (${fixture.homeTeam} or Draw)';
          }
          if (awayDraw >= homeDraw && awayDraw >= homeAway) {
            return 'X2 (${fixture.awayTeam} or Draw)';
          }
          return '12 (${fixture.homeTeam} or ${fixture.awayTeam})';
        }
        return null;

      case 'GG':
        if (fixture.btts.isNotEmpty && fixture.btts.toUpperCase() != 'N/A') {
          return fixture.btts;
        }
        return null;

      case 'Over 1.5':
        return null;

      case 'Ov2.5':
        if (fixture.over25Goals.isNotEmpty &&
            fixture.over25Goals.toUpperCase() != 'N/A') {
          return fixture.over25Goals;
        }
        return null;

      case 'Under 3.5':
        return null;

      case 'Half with Most Goals':
        return null;

      case 'Corner 1X2':
        return null;

      case 'Cards 1X2':
        if (fixture.cardRisk.isNotEmpty &&
            fixture.cardRisk.toUpperCase() != 'N/A') {
          return fixture.cardRisk;
        }
        return null;

      case 'Half with Most Cards':
        return null;

      case 'Player to Score':
        return null;

      default:
        return null;
    }
  }

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
        try {
          final activeSports = fixtures
              .map((f) => _leagueToOddsSport[f.competitionCode.toUpperCase()])
              .whereType<String>()
              .toSet();

          if (activeSports.isNotEmpty) {
            final oddsResponses = await Future.wait(
              activeSports.map(
                (sport) => ApiService.fetchOdds(sport),
              ),
            );

            final allOdds = oddsResponses.expand((list) => list).toList();

            for (final fixture in fixtures) {
              final fHome = fixture.homeTeam.toLowerCase();

              for (final item in allOdds) {
                final oHome =
                    item['home_team']?.toString().toLowerCase() ?? '';

                if (oHome.isEmpty) continue;

                if (fHome.contains(oHome) || oHome.contains(fHome)) {
                  final bookmakers = item['bookmakers'] as List? ?? [];

                  if (bookmakers.isNotEmpty) {
                    final markets = bookmakers[0]['markets'] as List? ?? [];

                    for (final market in markets) {
                      if (market['key'] == 'h2h') {
                        final outcomes = market['outcomes'] as List? ?? [];

                        for (final outcome in outcomes) {
                          if (outcome['name']
                                  ?.toString()
                                  .toLowerCase() ==
                              oHome) {
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
          }
        } catch (e) {
          debugPrint('Failed to attach live odds: $e');
        }

        await _safely(() => PredictionLog.update(fixtures));
        await _safely(() => SlipStore.settle(fixtures));
        await SuggestedSlipStore.refresh(fixtures);
        await _safely(
          () => NotificationService.scheduleKickoffReminders(
            fixtures,
            _savedKeys,
            AppSettings.favorites.value,
          ),
        );

        return fixtures;
      });
    });
  }

  Future<void> _safely(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      debugPrint('Ignored background error: $e');
    }
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
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
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
          return kSafaricomGreen;
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

  Widget _buildAnalysedBadge(FixtureModel fixture) {
    if (!fixture.hasAnalysis) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color.fromARGB(36, 58, 163, 53),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kSafaricomGreen, width: 1),
      ),
      child: const Text(
        'Analysed',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: kSafaricomGreen,
        ),
      ),
    );
  }

  Widget _buildPredictionOutcomeBadge(FixtureModel fixture) {
    final bool? won = fixture.isPredictionWon;
    if (won == null) {
      return const SizedBox.shrink();
    }
    final Color badgeColor = won ? kSafaricomGreen : const Color(0xFFC62828);
    final Color bgColor = won
        ? const Color.fromARGB(36, 58, 163, 53)
        : const Color.fromARGB(36, 198, 40, 40);

    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: badgeColor, width: 1),
      ),
      child: Text(
        won ? 'WON' : 'LOST',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: badgeColor,
        ),
      ),
    );
  }

  List<Widget> _buildExtendedInsightsWidgets(FixtureModel fixture) {
    final List<Widget> items = [
      _kv('Over 1.5 goals', fixture.over15Goals),
      _kv('Over 2.5 goals', fixture.over25Goals),
      _kv('Under 3.5 goals', fixture.under35Goals),
      _kv('Both teams to score', fixture.btts),
      _kv('Card risk', fixture.cardRisk),
    ];

    if (fixture.firstHalfGoalsProb != null) {
      items.add(
        _kv('1st half goals prob', '${fixture.firstHalfGoalsProb!.round()}%'),
      );
    }
    if (fixture.secondHalfGoalsProb != null) {
      items.add(
        _kv('2nd half goals prob', '${fixture.secondHalfGoalsProb!.round()}%'),
      );
    }
    if (fixture.homeCardsProb != null) {
      items.add(
        _kv('Home cards prob', '${fixture.homeCardsProb!.round()}%'),
      );
    }
    if (fixture.drawCardsProb != null) {
      items.add(
        _kv('Draw cards prob', '${fixture.drawCardsProb!.round()}%'),
      );
    }
    if (fixture.awayCardsProb != null) {
      items.add(
        _kv('Away cards prob', '${fixture.awayCardsProb!.round()}%'),
      );
    }
    if (fixture.firstHalfCardsProb != null) {
      items.add(
        _kv('1st half cards prob', '${fixture.firstHalfCardsProb!.round()}%'),
      );
    }
    if (fixture.secondHalfCardsProb != null) {
      items.add(
        _kv('2nd half cards prob', '${fixture.secondHalfCardsProb!.round()}%'),
      );
    }
    if (fixture.anytimeScorers.isNotEmpty) {
      items.add(
        _kv(
          'Anytime scorer',
          '${fixture.anytimeScorers.first.name} (${fixture.anytimeScorers.first.goalProb.round()}%)',
        ),
      );
    }

    return items;
  }

  Widget _buildMatchTile(FixtureModel fixture, int index) {
    final isSaved = _savedKeys.contains(fixture.key);

    final String label = fixture.formattedLocalTime;
    final String whenText = fixture.effectiveIsFinished
        ? '${label.isNotEmpty ? '$label · ' : ''}FT ${fixture.actualScore}'
        : label;

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
            _buildAnalysedBadge(fixture),
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
          // Prediction
          _sectionTitle('Prediction'),
          if (fixture.hasPrediction) ...[
            Row(
              children: [
                _buildPredictionOutcomeBadge(fixture),
                Expanded(
                  child: Text(
                    fixture.effectiveIsFinished
                        ? (fixture.topTip.isNotEmpty
                            ? 'Top Tip: ${fixture.topTip} (FT ${fixture.actualScore})'
                            : 'Full time: ${fixture.actualScore}')
                        : (fixture.topTip.isEmpty
                            ? 'No clear tip'
                            : 'Top Tip: ${fixture.topTip}'),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
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
            Row(
              children: [
                _buildPredictionOutcomeBadge(fixture),
                Expanded(
                  child: Text(
                    fixture.effectiveIsFinished
                        ? 'Full time: ${fixture.actualScore}'
                        : 'Analysis pending or unavailable',
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: mutedText(context),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
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
          ..._buildExtendedInsightsWidgets(fixture),

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

// ---------------------------------------------------------------------------
// Slips tab (SYSTEM PICKS)
// ---------------------------------------------------------------------------
class _SlipsData {
  final List<SlipLeg> legs;
  final SuggestedSlip? suggested;
  final Map<String, SuggestedSlip> history7Days;
  final List<FixtureModel> fixtures;

  const _SlipsData(
    this.legs,
    this.suggested, [
    this.history7Days = const {},
    this.fixtures = const [],
  ]);
}

class SavedSlipsTab extends StatefulWidget {
  const SavedSlipsTab({super.key});

  @override
  State<SavedSlipsTab> createState() => _SavedSlipsTabState();
}

class _SavedSlipsTabState extends State<SavedSlipsTab> {
  late Future<_SlipsData> _slipsFuture;
  late Future<SlipAccessStatus> _accessFuture;
  List<FixtureModel> _fixtures = const [];

  final TextEditingController _suggestedStakeController = TextEditingController();
  double? _customSuggestedStake;
  bool _isEditingSuggested = false;

  @override
  void initState() {
    super.initState();
    _loadSlips();
  }

  @override
  void dispose() {
    _suggestedStakeController.dispose();
    super.dispose();
  }

  Future<_SlipsData> _fetch() async {
    final legs = await SlipStore.loadLast7Days();
    final suggested = await SuggestedSlipStore.load();
    final history = await SuggestedSlipStore.loadHistory7Days();

    List<FixtureModel> fixtures = _fixtures;
    try {
      fixtures = await ApiService.fetchFixtures();
    } catch (e) {
      debugPrint('Could not load fixtures for slip evaluation: $e');
    }

    if (suggested != null && _customSuggestedStake == null) {
      _customSuggestedStake = suggested.stake;
      _suggestedStakeController.text = suggested.stake.toStringAsFixed(0);
    }
    return _SlipsData(legs, suggested, history, fixtures);
  }

  void _loadSlips() {
    setState(() {
      _slipsFuture = _fetch();
      _accessFuture = SlipAccessManager.checkAccess();
    });
  }

  /// true = all legs won, false = at least one leg lost, null = pending/unsettled.
  bool? _evaluateSuggestedSlipWon(
    SuggestedSlip slip,
    List<FixtureModel> fixtures,
  ) {
    if (slip.selections.isEmpty) return null;

    bool anyPending = false;
    for (final leg in slip.selections) {
      final String matchText = (leg['match'] ?? '').toString().toLowerCase();
      final String tipText = (leg['prediction'] ?? '').toString().toLowerCase();

      FixtureModel? match;
      for (final f in fixtures) {
        final home = f.homeTeam.toLowerCase();
        final away = f.awayTeam.toLowerCase();
        if (matchText.contains(home) && matchText.contains(away)) {
          match = f;
          break;
        }
      }

      if (match == null || !match.effectiveIsFinished) {
        anyPending = true;
        continue;
      }

      final bool? legWon = _evaluateLegAgainstFixture(match, tipText);
      if (legWon == false) return false;
      if (legWon == null) anyPending = true;
    }

    return anyPending ? null : true;
  }

  bool? _evaluateLegAgainstFixture(FixtureModel f, String tipLower) {
    final parts = f.actualScore.split(RegExp(r'\s*[-:]\s*'));
    if (parts.length != 2) return f.isPredictionWon;
    final int? h = int.tryParse(parts[0].trim());
    final int? a = int.tryParse(parts[1].trim());
    if (h == null || a == null) return f.isPredictionWon;

    final int total = h + a;
    final home = f.homeTeam.toLowerCase();
    final away = f.awayTeam.toLowerCase();

    if (tipLower.contains('over 1.5')) return total > 1;
    if (tipLower.contains('under 1.5')) return total < 1;
    if (tipLower.contains('over 2.5')) return total > 2;
    if (tipLower.contains('under 2.5')) return total < 2;
    if (tipLower.contains('over 3.5')) return total > 3;
    if (tipLower.contains('under 3.5')) return total < 3;
    if (tipLower.contains('btts') || tipLower.contains('gg')) {
      return h > 0 && a > 0;
    }
    if (tipLower.contains('(1x)') || tipLower.contains('$home or draw')) {
      return h >= a;
    }
    if (tipLower.contains('(x2)') || tipLower.contains('$away or draw')) {
      return a >= h;
    }
    if (tipLower.contains('(12)')) return h != a;
    if (tipLower.contains('$home win') || tipLower == home) return h > a;
    if (tipLower.contains('$away win') || tipLower == away) return a > h;
    if (tipLower.contains('draw')) return h == a;

    return f.isPredictionWon;
  }

  Widget _buildSystemPicksHeader() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        'SYSTEM PICKS',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: kTealGreen,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildDayHeader(String dateStr) {
    final dt = DateTime.tryParse(dateStr);
    const months = [
      'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
      'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
    ];
    const days = [
      'MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY',
      'FRIDAY', 'SATURDAY', 'SUNDAY',
    ];
    final label = dt == null
        ? dateStr
        : '${days[dt.weekday - 1]}, ${dt.day} ${months[dt.month - 1]} ${dt.year}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Color(0xFF00C853),
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _archiveSuggestedCard(
    BuildContext context,
    SuggestedSlip slip,
    List<FixtureModel> fixtures,
  ) {
    final double chance = slip.totalOdds > 0 ? 100 / slip.totalOdds : 0;
    final bool? won = _evaluateSuggestedSlipWon(slip, fixtures);
    final String statusLabel =
        won == null ? 'PENDING' : (won ? 'WON' : 'LOST');
    final Color statusColor = won == null
        ? Colors.orange.shade800
        : (won ? kSafaricomGreen : Colors.red.shade700);

    return Card(
      color: ticketCardBg(context),
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: ticketBorderColor(context), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    slip.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                const SizedBox(width: 6),
                ticketStatusPill(statusLabel, statusColor),
                const SizedBox(width: 6),
                Text(
                  '${slip.totalOdds.toStringAsFixed(2)}x',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: kTealGreen,
                  ),
                ),
              ],
            ),
            const Divider(height: 12),
            for (int i = 0; i < slip.selections.length; i++) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${i + 1}. ${slip.selections[i]['match']}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 12),
                          ),
                          Text(
                            'Prediction: ${slip.selections[i]['prediction']}',
                            style: TextStyle(
                                fontSize: 11, color: mutedText(context)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${slip.selections[i]['odds']}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: kTealGreen,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const Divider(height: 12),
            Text(
              'Stake: Ksh ${slip.stake.toStringAsFixed(0)}  •  Possible Win: Ksh ${slip.potentialPayout.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              'Chance that every leg wins: about ${chance.toStringAsFixed(0)}%',
              style: TextStyle(fontSize: 11, color: mutedText(context)),
            ),
          ],
        ),
      ),
    );
  }
  Widget _buildPrevious7DaysFlap(
    BuildContext context,
    Map<String, SuggestedSlip> history7Days,
    String todayStr,
    List<FixtureModel> fixtures,
  ) {
    final yesterdayStr = SuggestedSlipStore.yesterdayString();
    final pastEntries = history7Days.entries
        .where((e) => e.key != todayStr)
        .toList()
      ..sort((a, b) => b.key.compareTo(a.key));

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Card(
        color: ticketCardBg(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: ticketBorderColor(context), width: 1),
        ),
        child: ExpansionTile(
          initiallyExpanded: false,
          iconColor: kTealGreen,
          collapsedIconColor: kTealGreen,
          title: Text(
            'PREVIOUS 7 DAYS SLIPS (${pastEntries.length}d)',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: kTealGreen,
              letterSpacing: 0.8,
            ),
          ),
          subtitle: Text(
            pastEntries.isEmpty
                ? 'No previous days stored yet'
                : 'Tap to unfold days of the week',
            style: TextStyle(fontSize: 11, color: mutedText(context)),
          ),
          children: pastEntries.map((entry) {
            final dayKey = entry.key;
            final slip = entry.value;
            final dayLabel =
                dayKey == yesterdayStr ? 'YESTERDAY • $dayKey' : dayKey;

            return ExpansionTile(
              title: Text(
                dayLabel,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                '${slip.title} • ${slip.totalOdds.toStringAsFixed(2)}x',
                style: TextStyle(fontSize: 11, color: mutedText(context)),
              ),
              children: [_archiveSuggestedCard(context, slip, fixtures)],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _suggestedCard(
    BuildContext context,
    SuggestedSlip slip,
    List<FixtureModel> fixtures,
  ) {
    final double currentStake = _customSuggestedStake ?? slip.stake;
    final double potentialPayout = slip.totalOdds * currentStake;
    final double chance = slip.totalOdds > 0 ? 100 / slip.totalOdds : 0;

    final bool? won = _evaluateSuggestedSlipWon(slip, fixtures);
    final String statusLabel =
        won == null ? 'PENDING' : (won ? 'WON' : 'LOST');
    final Color statusColor = won == null
        ? Colors.orange.shade800
        : (won ? kSafaricomGreen : Colors.red.shade700);

    return Card(
      color: ticketCardBg(context),
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: ticketBorderColor(context), width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    slip.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                const SizedBox(width: 8),
                ticketStatusPill(statusLabel, statusColor),
                const SizedBox(width: 8),
                Text(
                  '${slip.totalOdds.toStringAsFixed(2)}x',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: kTealGreen,
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            for (int i = 0; i < slip.selections.length; i++) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${i + 1}. ${slip.selections[i]['match']}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Prediction: ${slip.selections[i]['prediction']}',
                            style: TextStyle(
                                fontSize: 12, color: mutedText(context)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${slip.selections[i]['odds']}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: kTealGreen,
                      ),
                    ),
                  ],
                ),
              ),
              if (i < slip.selections.length - 1)
                const Divider(height: 8, color: Colors.black12),
            ],
            const Divider(height: 16),
            Text(
              'Chance that every leg wins: about ${chance.toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.03),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kTealGreen.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Stake (Ksh)',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.grey)),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(50, 20),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () async {
                                if (_isEditingSuggested) {
                                  final parsed = double.tryParse(
                                      _suggestedStakeController.text.trim());
                                  if (parsed != null && parsed >= 0) {
                                    setState(() {
                                      _customSuggestedStake = parsed;
                                      _isEditingSuggested = false;
                                    });
                                    await SuggestedSlipStore.updateStake(parsed);
                                  }
                                } else {
                                  setState(() {
                                    _isEditingSuggested = true;
                                  });
                                }
                              },
                              icon: Icon(
                                _isEditingSuggested ? Icons.save : Icons.edit,
                                size: 14,
                                color: kTealGreen,
                              ),
                              label: Text(
                                _isEditingSuggested ? 'Save' : 'Edit',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: kTealGreen,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        _isEditingSuggested
                            ? TextField(
                                controller: _suggestedStakeController,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.bold),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                      vertical: 4, horizontal: 8),
                                  border: OutlineInputBorder(),
                                ),
                              )
                            : Text(
                                'Ksh ${currentStake.toStringAsFixed(0)}',
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.bold),
                              ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('Possible Win',
                            style: TextStyle(fontSize: 11, color: Colors.grey)),
                        const SizedBox(height: 4),
                        Text(
                          'Ksh ${potentialPayout.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: kTealGreen,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              SuggestedSlipStore.note,
              style: TextStyle(fontSize: 10, color: mutedText(context)),
            ),
          ],
        ),
      ),
    );
  }
  Widget _buildLockedSuggestedCard(BuildContext context) {
    return Card(
      color: ticketCardBg(context),
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: ticketBorderColor(context), width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            const Icon(Icons.lock, size: 42, color: kTealGreen),
            const SizedBox(height: 10),
            const Text(
              'Daily Prolific System Slip Locked',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Your free access waiver has expired. Unlock today\'s high-confidence value accumulator',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: kTealGreen,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.lock_open),
              label: const Text('Pay to View Slip'),
              onPressed: () {
                showSlipSubscriptionSheet(context, () async {
                  _loadSlips();
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final todayStr = SuggestedSlipStore.todayString();

    return FutureBuilder<_SlipsData>(
      future: _slipsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Column(
            children: [
              _buildSystemPicksHeader(),
              const Expanded(child: Center(child: CircularProgressIndicator())),
            ],
          );
        }

        final data = snapshot.data ?? const _SlipsData([], null, {}, []);
        _fixtures = data.fixtures;

        return FutureBuilder<SlipAccessStatus>(
          future: _accessFuture,
          builder: (context, accessSnapshot) {
            final hasAccess = accessSnapshot.data?.hasAccess ?? true;

            return ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                _buildSystemPicksHeader(),
                if (data.suggested != null) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text(
                      '\u{1F525} DAILY VALUE ACCUMULATOR',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: kTealGreen,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
                  _buildDayHeader(data.suggested!.date),
                  if (!hasAccess)
                    _buildLockedSuggestedCard(context)
                  else
                    _suggestedCard(context, data.suggested!, data.fixtures),
                ],
                _buildPrevious7DaysFlap(
                    context, data.history7Days, todayStr, data.fixtures),
                if (data.suggested == null && data.history7Days.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No system slips available yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: mutedText(context)),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// History tab (PROLIFIC)
// ---------------------------------------------------------------------------
class PredictionLogTab extends StatefulWidget {
  const PredictionLogTab({super.key});

  @override
  State<PredictionLogTab> createState() => _PredictionLogTabState();
}

class _PredictionLogTabState extends State<PredictionLogTab> {
  late Future<List<LogEntry>> _logFuture;

  @override
  void initState() {
    super.initState();
    _loadLog();
  }

  void _loadLog() {
    setState(() {
      _logFuture = PredictionLog.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<LogEntry>>(
      future: _logFuture,
      builder: (context, snapshot) {
        Widget body;

        if (snapshot.connectionState == ConnectionState.waiting) {
          body = const Center(child: CircularProgressIndicator());
        } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
          body = const Center(child: Text('No prediction history recorded yet.'));
        } else {
          final entries = snapshot.data!;
          final stats = PredictionLog.stats(entries);

          body = Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Card(
                  color: cardBg(context),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _statItem('Total', '${stats.total}'),
                        _statItem('Settled', '${stats.settled}'),
                        _statItem('Wins', '${stats.wins}'),
                        _statItem('Hit Rate',
                            '${(stats.hitRate * 100).toStringAsFixed(1)}%'),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return Card(
                      color: cardBg(context),
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        // Tapping any history item opens its audit breakdown dialog
                        onTap: () => showLogEntryInsight(context, entry),
                        title: Text('${entry.home} vs ${entry.away}'),
                        subtitle:
                            Text('Tip: ${entry.tip} | League: ${entry.league}'),
                        trailing: _buildStatusBadge(entry),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        }

        return Column(
          children: [
            buildProlificHeader(),
            Expanded(child: body),
          ],
        );
      },
    );
  }

  Widget _statItem(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildStatusBadge(LogEntry entry) {
    if (!entry.settled) {
      return const Chip(
        label: Text('Pending', style: TextStyle(fontSize: 10)),
        backgroundColor: Colors.amberAccent,
      );
    } else if (entry.isVoid) {
      return const Chip(
        label: Text('Void', style: TextStyle(fontSize: 10)),
        backgroundColor: Colors.grey,
      );
    } else if (entry.won == true) {
      return const Chip(
        label: Text('Won', style: TextStyle(fontSize: 10, color: Colors.white)),
        backgroundColor: kSafaricomGreen,
      );
    } else {
      return const Chip(
        label: Text('Lost', style: TextStyle(fontSize: 10, color: Colors.white)),
        backgroundColor: Colors.red,
      );
    }
  }
}
