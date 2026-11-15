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
        // Do not keep showing an old day's slip as if it were current.
        if (existing != null) await prefs.remove(_slipKey);
        return;
      }

      final slip = SuggestedSlip(
        title: generated.title,
        totalOdds: generated.totalOdds,
        selections: generated.selections,
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
/// Saves an updated stake for today's active suggested slip
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
  int _currentIndex = 0;

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
          BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet), label: 'Bankroll'),
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

  void _loadFixtures() {
    setState(() {
      _fixturesFuture = ApiService.fetchFixtures().then((fixtures) async {
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

  Widget _buildSearchAndFilters() {
    const filters = ['All', 'Upcoming', 'Live', 'Finished'];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        children: [
          // Search Bar for Teams
          TextField(
            controller: _searchController,
            onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
            decoration: InputDecoration(
              hintText: 'Search team (e.g., Santos, Flamengo)...',
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
          // Filter Chips Row
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
        ],
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
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: mutedText(context))),
                  const SizedBox(height: 8),
                  Text('${snapshot.error}',
                      textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: mutedText(context))),
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

        // 1. Filter by status (All, Upcoming, Live, Finished)
        List<FixtureModel> fixtures = FixtureModel.filterFixtures(snapshot.data!, _selectedFilter);

        // 2. Filter by search query (team names)
        if (_searchQuery.isNotEmpty) {
          fixtures = fixtures.where((f) =>
              f.homeTeam.toLowerCase().contains(_searchQuery) ||
              f.awayTeam.toLowerCase().contains(_searchQuery)).toList();
        }

        return Column(
          children: [
            _buildSearchAndFilters(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => _loadFixtures(),
                child: fixtures.isEmpty
                    ? Center(
                        child: Text(
                          'No matches found',
                          style: TextStyle(color: mutedText(context)),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        itemCount: fixtures.length,
                        itemBuilder: (context, index) {
                          final fixture = fixtures[index];
                          final isSaved = _savedKeys.contains(fixture.key);
                          
                          // Include both schedule date/time and FT score for finished matches
                          final String whenText = fixture.isFinished
                              ? '${fixture.timeLabel.isNotEmpty ? "${fixture.timeLabel} • " : ""}FT ${fixture.actualScore}'
                              : fixture.timeLabel;

                          return Card(
                            color: cardBg(context),
                            margin: const EdgeInsets.only(bottom: 12),
                            elevation: 1,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(fixture.league.toUpperCase(),
                                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: mutedText(context))),
                                      ),
                                      IconButton(
                                        icon: Icon(isSaved ? Icons.bookmark : Icons.bookmark_border, color: kPrimary),
                                        onPressed: () => _toggleSave(fixture),
                                        tooltip: 'Save to Slip',
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(fixture.homeTeam,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                      ),
                                      const Padding(
                                        padding: EdgeInsets.symmetric(horizontal: 8.0),
                                        child: Text('vs', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                      ),
                                      Expanded(
                                        child: Text(fixture.awayTeam,
                                            textAlign: TextAlign.right,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                      ),
                                    ],
                                  ),
                                  if (whenText.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(whenText, style: TextStyle(fontSize: 12, color: mutedText(context))),
                                    ),
                                  const Divider(height: 20),
                                  if (fixture.hasPrediction) ...[
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            fixture.topTip.isEmpty ? 'No clear tip' : 'Top Tip: ${fixture.topTip}',
                                            style: const TextStyle(fontWeight: FontWeight.bold, color: kPrimary, fontSize: 13),
                                          ),
                                        ),
                                        if (fixture.odds > 0)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: kPrimary.withOpacity(0.1),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Text('Odds: ${fixture.odds.toStringAsFixed(2)}',
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: kPrimary)),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Expanded(child: Text('Home: ${fixture.homeWinProb.round()}%', style: const TextStyle(fontSize: 12))),
                                        Expanded(child: Text('Draw: ${fixture.drawProb.round()}%', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
                                        Expanded(child: Text('Away: ${fixture.awayWinProb.round()}%', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
                                      ],
                                    ),
                                  ] else if (!fixture.isFinished) ...[
                                    Text('Analysis pending or unavailable',
                                        style: TextStyle(fontStyle: FontStyle.italic, color: mutedText(context), fontSize: 12)),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
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

  @override
  void initState() {
    super.initState();
    _loadSlips();
  }

  Future<_SlipsData> _fetch() async {
    final legs = await SlipStore.load();
    final suggested = await SuggestedSlipStore.load();
    return _SlipsData(legs, suggested);
  }

  void _loadSlips() {
    setState(() {
      _slipsFuture = _fetch();
    });
  }

  /// The day a saved pick belongs to, as YYYY-MM-DD (match day, or the day it
  /// was saved if the match time is unknown).
  String _dayKeyOf(SlipLeg leg) {
    final DateTime dt = DateTime.tryParse(leg.utcDate)?.toLocal() ??
        DateTime.fromMillisecondsSinceEpoch(leg.savedAt);
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  /// Safaricom Green day and date header helper
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
          color: Color(0xFF00C853), // Safaricom Green highlight
          letterSpacing: 1.2,
        ),
      ),
    );
  }
  
  /// Suggested slip card in a professional ticket style
  Widget _suggestedCard(BuildContext context, SuggestedSlip slip) {
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
            // Header: title and overall odds
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
            // Selections styled like match rows with odds on the right
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
            // Stake and possible win box
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.03),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kTealGreen.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Stake', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      const SizedBox(height: 2),
                      Text(
                        'Ksh ${slip.stake.toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Possible Win', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      const SizedBox(height: 2),
                      Text(
                        'Ksh ${slip.potentialPayout.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: kTealGreen,
                        ),
                      ),
                    ],
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
          for (int i = 0; i < grouped[day]!.length; i++)
            Card(
              color: cardBg(context),
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: kTealGreen,
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
                title: Text(
                  '${grouped[day]![i].home} vs ${grouped[day]![i].away}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Tip: ${grouped[day]![i].tip.isNotEmpty ? grouped[day]![i].tip : "None"} | Score: ${grouped[day]![i].score.isNotEmpty ? grouped[day]![i].score : "Pending"}',
                    style: TextStyle(fontSize: 12, color: mutedText(context)),
                  ),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () async {
                    await SlipStore.remove(grouped[day]![i].key);
                    _loadSlips();
                  },
                ),
              ),
            ),
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

        return ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            buildMyPicksHeader(),

            // Section 1: system-generated daily accumulator
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
              _suggestedCard(context, data.suggested!),
            ],

            // Summary card for manually saved picks (if any exist)
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

            // Section 2: manually saved bookmarks grouped by day
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
