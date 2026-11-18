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
            colorScheme: ColorScheme.fromSeed(seedColor: kPrimary, brightness: Brightness.light),
            useMaterial3: true,
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primaryColor: kPrimary,
            scaffoldBackgroundColor: const Color(0xFF12161C),
            colorScheme: ColorScheme.fromSeed(seedColor: kPrimary, brightness: Brightness.dark),
            useMaterial3: true,
          ),
          home: const MainHomeScreen(),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Suggested slip (5-10 combined odds), built automatically from fixtures daily
// ---------------------------------------------------------------------------
class SuggestedSlip {
  final String title;
  final double totalOdds;
  final List<Map<String, dynamic>> selections;
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
    final List<Map<String, dynamic>> sel = [];
    final raw = j['selections'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          sel.add(Map<String, dynamic>.from(e));
        }
      }
    }
    final double odds = j['totalOdds'] is num ? (j['totalOdds'] as num).toDouble() : 0;
    final double parsedStake = j['stake'] is num ? (j['stake'] as num).toDouble() : 200.0;
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
  static const String _notifiedDayKey = 'suggested_slip_notified_day';

  static const String note =
      'Odds are model-implied (100 divided by win probability), not bookmaker odds. '
      'Real bookmaker odds will be lower. No slip is guaranteed to win.';

  /// Today's date as YYYY-MM-DD (phone time).
  static String todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
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

  /// Saves an updated custom stake for today's active suggested slip
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
      }
    } catch (e) {
      debugPrint('Could not update suggested slip stake: $e');
    }
  }

  /// Builds one slip per day from the latest fixtures and sends one
  /// notification for it.
  static Future<void> refresh(List<FixtureModel> fixtures) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final todayStr = todayString();
      final existing = await load();

      // Today's slip already exists: keep it.
      if (existing != null && existing.date == todayStr) return;

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

Future<void> _safely(Future<void> Function() action) async {
  try {
    await action();
  } catch (e) {
    debugPrint('Background task failed: $e');
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
  int _currentIndex = 4;

  final List<Widget> _screens = const [
    FixturesTab(),
    TablesScreen(),
    SavedSlipsTab(),
    PredictionLogTab(),
    BankrollTab(),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Betting Companion', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
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
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        type: BottomNavigationBarType.fixed,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.sports_soccer), label: 'Fixtures'),
          BottomNavigationBarItem(icon: Icon(Icons.leaderboard), label: 'Standings'),
          BottomNavigationBarItem(icon: Icon(Icons.bookmark), label: 'Slips'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
          BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet), label: 'Bankroll Account'),
        ],
      ),
    );
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
        // 1. Determine which sport keys are present in the current fixtures list
        final activeSports = fixtures
            .map((f) => _leagueToOddsSport[f.competitionCode.toUpperCase()])
            .whereType<String>()
            .toSet();

        // 2. Fetch odds for all active sports concurrently
        if (activeSports.isNotEmpty) {
          try {
            final oddsResponses = await Future.wait(
              activeSports.map((sport) => ApiService.fetchOdds(sport)),
            );
            final allOdds = oddsResponses.expand((list) => list).toList();

            // 3. Map the odds to matching fixtures based on team names
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
                            fixture.odds = (outcome['price'] as num?)?.toDouble() ?? 0.0;
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
      SnackBar(content: Text(nowSaved ? 'Saved to slips' : 'Removed from saved slips')),
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
            onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
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
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
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
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                    onSelected: (_) => setState(() => _selectedFilter = key),
                  ),
                );
              }).toList(),
            ),
          ),
          _buildTimeWindows(),
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
            icon: Icon(showCollapse ? Icons.unfold_less : Icons.unfold_more,
                size: 18),
            label: Text(showCollapse ? 'Collapse all' : 'Expand all'),
          ),
          const Spacer(),
          Text('One at a time',
              style: TextStyle(fontSize: 12, color: mutedText(context))),
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
            child: Text(label,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12)),
          ),
          if (form.isEmpty)
            Text('N/A', style: TextStyle(fontSize: 12, color: mutedText(context)))
          else
            Row(
              children: form
                  .map((r) => Container(
                        width: 20,
                        height: 20,
                        margin: const EdgeInsets.only(left: 4),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: colorFor(r),
                          shape: BoxShape.circle,
                        ),
                        child: Text(r.toUpperCase(),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                      ))
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
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  if (whenText.isNotEmpty)
                    Text(whenText,
                        style: TextStyle(fontSize: 11, color: mutedText(context))),
                ],
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: Icon(isSaved ? Icons.bookmark : Icons.bookmark_border,
                  color: kPrimary, size: 22),
              onPressed: () => _toggleSave(fixture),
              tooltip: 'Save to Slip',
            ),
          ],
        ),
        children: [
          // Prediction
          _sectionTitle('Prediction'),
          if (fixture.hasPrediction) ...[
            Text(
              fixture.topTip.isEmpty ? 'No clear tip' : 'Top Tip: ${fixture.topTip}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                    child: Text('Home: ${fixture.homeWinProb.round()}%',
                        style: const TextStyle(fontSize: 12))),
                Expanded(
                    child: Text('Draw: ${fixture.drawProb.round()}%',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 12))),
                Expanded(
                    child: Text('Away: ${fixture.awayWinProb.round()}%',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontSize: 12))),
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
                  fontSize: 12),
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
            Text('Head to head',
                style: TextStyle(fontSize: 12, color: mutedText(context))),
            ...fixture.h2h.take(3).map((h) => Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('${h.date}  ${h.home} ${h.score} ${h.away}',
                      style: const TextStyle(fontSize: 12)),
                )),
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
                      fontWeight: FontWeight.bold, fontSize: 14),
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
                  Text('Failed to load fixtures',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: mutedText(context))),
                  const SizedBox(height: 8),
                  Text('${snapshot.error}',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: mutedText(context))),
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

        // status + search filter, then time window
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

        // Pinned leagues first, then the leagues with the most matches
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
                            leagues[index], byLeague[leagues[index]]!),
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
// Slips tab (MY PICKS)
// ---------------------------------------------------------------------------
class _SlipsData {
  final List<SlipLeg> legs;
  final SuggestedSlip? suggested;

  const _SlipsData(this.legs, this.suggested);
}

class SavedSlipsTab extends StatefulWidget {
  const SavedSlipsTab({super.key});

  @override
  State<SavedSlipsTab> createState() => _SavedSlipsTabState();
}

class _SavedSlipsTabState extends State<SavedSlipsTab> {
  late Future<_SlipsData> _slipsFuture;
  late Future<SlipAccessStatus> _accessFuture;
  
  // Controllers and edit modes for suggested slip & daily manual slips
  final TextEditingController _suggestedStakeController = TextEditingController();
  double? _customSuggestedStake;
  bool _isEditingSuggested = false;
  
  // Maps to hold controllers and edit states for each day's saved manual slip
  final Map<String, TextEditingController> _manualStakeControllers = {};
  final Map<String, double> _customManualStakes = {};
  final Map<String, bool> _isEditingManual = {};

  @override
  void initState() {
    super.initState();
    _loadSlips();
  }

  @override
  void dispose() {
    _suggestedStakeController.dispose();
    for (var c in _manualStakeControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<_SlipsData> _fetch() async {
    final legs = await SlipStore.load();
    final suggested = await SuggestedSlipStore.load();
    if (suggested != null && _customSuggestedStake == null) {
      _customSuggestedStake = suggested.stake;
      _suggestedStakeController.text = suggested.stake.toStringAsFixed(0);
    }
    return _SlipsData(legs, suggested);
  }

  void _loadSlips() {
    setState(() {
      _slipsFuture = _fetch();
      _accessFuture = SlipAccessManager.checkAccess();
    });
  }

  /// The day a saved pick belongs to, as YYYY-MM-DD
  String _dayKeyOf(SlipLeg leg) {
    final DateTime dt = DateTime.tryParse(leg.utcDate)?.toLocal() ??
        DateTime.fromMillisecondsSinceEpoch(leg.savedAt);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  /// Day and date header helper
  Widget _buildDayHeader(String dateStr) {
    final dt = DateTime.tryParse(dateStr);
    String formatted = dateStr;
    if (dt != null) {
      const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
      const days = ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY'];
      formatted = '${days[dt.weekday - 1]}, ${dt.day} ${months[dt.month - 1]} ${dt.year}';
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Text(
        formatted.toUpperCase(),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Color(0xFF00C853),
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  /// Suggested slip card with edit and save stake buttons
  Widget _suggestedCard(BuildContext context, SuggestedSlip slip) {
    final double currentStake = _customSuggestedStake ?? slip.stake;
    final double potentialPayout = slip.totalOdds * currentStake;
    final double chance = slip.totalOdds > 0 ? 100 / slip.totalOdds : 0;

    return Card(
      color: cardBg(context),
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: kTealGreen, width: 1),
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
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
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
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Prediction: ${slip.selections[i]['prediction']}',
                            style: TextStyle(fontSize: 12, color: mutedText(context)),
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
                            const Text('Stake (Ksh)', style: TextStyle(fontSize: 11, color: Colors.grey)),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(50, 20),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () async {
                                if (_isEditingSuggested) {
                                  // Save action
                                  final parsed = double.tryParse(_suggestedStakeController.text.trim());
                                  if (parsed != null && parsed >= 0) {
                                    setState(() {
                                      _customSuggestedStake = parsed;
                                      _isEditingSuggested = false;
                                    });
                                    await SuggestedSlipStore.updateStake(parsed);
                                  }
                                } else {
                                  // Edit action
                                  setState(() {
                                    _isEditingSuggested = true;
                                  });
                                }
                              },
                              icon: Icon(_isEditingSuggested ? Icons.save : Icons.edit, size: 14, color: kTealGreen),
                              label: Text(
                                _isEditingSuggested ? 'Save' : 'Edit',
                                style: const TextStyle(fontSize: 11, color: kTealGreen, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        _isEditingSuggested
                            ? TextField(
                                controller: _suggestedStakeController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                  border: OutlineInputBorder(),
                                ),
                              )
                            : Text(
                                'Ksh ${currentStake.toStringAsFixed(0)}',
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                              ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('Possible Win', style: TextStyle(fontSize: 11, color: Colors.grey)),
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

  /// Locked Paywall card for suggested slip
  Widget _buildLockedSuggestedCard(BuildContext context) {
    return Card(
      color: cardBg(context),
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: kTealGreen, width: 1),
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
              'Your free access waiver has expired. Unlock today\'s high-confidence value accumulator via M-Pesa.',
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

  /// Manual Saved Picks Ticket per day with edit & save stake buttons
  Widget _buildManualSlipCard(String day, List<SlipLeg> dayLegs) {
    // Default standard combined odds calculation for saved manual legs
    double totalOdds = 1.0;
    for (int i = 0; i < dayLegs.length; i++) {
      totalOdds *= 1.85; // Standard model-implied accumulator multiplier per leg
    }

    _manualStakeControllers.putIfAbsent(day, () => TextEditingController(text: (_customManualStakes[day] ?? 200.0).toStringAsFixed(0)));
    final double currentStake = _customManualStakes[day] ?? 200.0;
    final double potentialPayout = totalOdds * currentStake;
    final bool isEditing = _isEditingManual[day] ?? false;

    return Card(
      color: cardBg(context),
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: kTealGreen, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Saved Accumulator Ticket',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                Text(
                  '${totalOdds.toStringAsFixed(2)}x',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: kTealGreen,
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            for (int i = 0; i < dayLegs.length; i++) ...[
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
                            '${i + 1}. ${dayLegs[i].home} vs ${dayLegs[i].away}',
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Date: ${dayLegs[i].utcDate.isNotEmpty ? dayLegs[i].utcDate : day} | Tip: ${dayLegs[i].tip.isNotEmpty ? dayLegs[i].tip : "None"}',
                            style: TextStyle(fontSize: 11, color: mutedText(context)),
                          ),
                          Text(
                            'Score: ${dayLegs[i].score.isNotEmpty ? dayLegs[i].score : "Pending"}',
                            style: TextStyle(fontSize: 11, color: mutedText(context)),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                      onPressed: () async {
                        await SlipStore.remove(dayLegs[i].key);
                        _loadSlips();
                      },
                    ),
                  ],
                ),
              ),
              if (i < dayLegs.length - 1)
                const Divider(height: 8, color: Colors.black12),
            ],
            const Divider(height: 16),
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
                            const Text('Stake (Ksh)', style: TextStyle(fontSize: 11, color: Colors.grey)),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(50, 20),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              onPressed: () {
                                if (isEditing) {
                                  final parsed = double.tryParse(_manualStakeControllers[day]?.text.trim() ?? '');
                                  if (parsed != null && parsed >= 0) {
                                    setState(() {
                                      _customManualStakes[day] = parsed;
                                      _isEditingManual[day] = false;
                                    });
                                  }
                                } else {
                                  setState(() {
                                    _isEditingManual[day] = true;
                                  });
                                }
                              },
                              icon: Icon(isEditing ? Icons.save : Icons.edit, size: 14, color: kTealGreen),
                              label: Text(
                                isEditing ? 'Save' : 'Edit',
                                style: const TextStyle(fontSize: 11, color: kTealGreen, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        isEditing
                            ? TextField(
                                controller: _manualStakeControllers[day],
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                  border: OutlineInputBorder(),
                                ),
                              )
                            : Text(
                                'Ksh ${currentStake.toStringAsFixed(0)}',
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                              ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('Possible Win', style: TextStyle(fontSize: 11, color: Colors.grey)),
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
          ],
        ),
      ),
    );
  }

  Widget _buildGroupedManualList(List<SlipLeg> legs) {
    if (legs.isEmpty) return const SizedBox.shrink();

    final Map<String, List<SlipLeg>> grouped = {};
    for (final leg in legs) {
      grouped.putIfAbsent(_dayKeyOf(leg), () => []).add(leg);
    }

    final sortedDays = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text(
            '\u26A1 MY SAVED PICKS',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: kTealGreen,
              letterSpacing: 1.1,
            ),
          ),
        ),
        for (final day in sortedDays) ...[
          _buildDayHeader(day),
          _buildManualSlipCard(day, grouped[day]!),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_SlipsData>(
      future: _slipsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Column(
            children: [
              buildMyPicksHeader(),
              const Expanded(child: Center(child: CircularProgressIndicator())),
            ],
          );
        }

        final data = snapshot.data ?? const _SlipsData([], null);
        final legs = data.legs;
        final summary = SlipStore.summary(legs);

        return FutureBuilder<SlipAccessStatus>(
          future: _accessFuture,
          builder: (context, accessSnapshot) {
            final hasAccess = accessSnapshot.data?.hasAccess ?? true;

            return ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                buildMyPicksHeader(),

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
                    _suggestedCard(context, data.suggested!),
                ],

                if (legs.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    child: Card(
                      color: cardBg(context),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _statItem('Accumulator', summary.status),
                            _statItem('Won', '${summary.won}'),
                            _statItem('Lost', '${summary.lost}'),
                            _statItem('Pending', '${summary.pending}'),
                          ],
                        ),
                      ),
                    ),
                  ),

                if (legs.isEmpty && data.suggested == null)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No saved picks yet. Bookmark matches from the Fixtures tab to add them here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: mutedText(context)),
                    ),
                  )
                else
                  _buildGroupedManualList(legs),
              ],
            );
          },
        );
      },
    );
  }

  Widget _statItem(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ],
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
                        _statItem('Hit Rate', '${(stats.hitRate * 100).toStringAsFixed(1)}%'),
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
                        subtitle: Text('Tip: ${entry.tip} | League: ${entry.league}'),
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
        Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildStatusBadge(LogEntry entry) {
    if (!entry.settled) {
      return const Chip(label: Text('Pending', style: TextStyle(fontSize: 10)), backgroundColor: Colors.amberAccent);
    } else if (entry.isVoid) {
      return const Chip(label: Text('Void', style: TextStyle(fontSize: 10)), backgroundColor: Colors.grey);
    } else if (entry.won == true) {
      return const Chip(label: Text('Won', style: TextStyle(fontSize: 10, color: Colors.white)), backgroundColor: Colors.green);
    } else {
      return const Chip(label: Text('Lost', style: TextStyle(fontSize: 10, color: Colors.white)), backgroundColor: Colors.red);
    }
  }
}
