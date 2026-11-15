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
// Suggested slip (5-10 combined odds), built automatically from fixtures
// ---------------------------------------------------------------------------
class SuggestedSlip {
  final String title;
  final double totalOdds;
  final List<Map<String, dynamic>> selections;

  const SuggestedSlip({
    required this.title,
    required this.totalOdds,
    required this.selections,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'totalOdds': totalOdds,
        'selections': selections,
      };

  factory SuggestedSlip.fromJson(Map<String, dynamic> j) {
    final sel = <Map<String, dynamic>>[];
    final raw = j['selections'];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) sel.add(Map<String, dynamic>.from(e));
      }
    }
    return SuggestedSlip(
      title: j['title']?.toString() ?? 'Suggested slip',
      totalOdds: j['totalOdds'] is num ? (j['totalOdds'] as num).toDouble() : 0,
      selections: sel,
    );
  }
}

class SuggestedSlipStore {
  static const String _slipKey = 'suggested_slip_v1';
  static const String _notifiedDayKey = 'suggested_slip_notified_day';

  static const String note =
      'Odds are model-implied (100 divided by win probability), not bookmaker odds. '
      'Real bookmaker odds will be lower. No slip is guaranteed to win.';

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

  /// Builds a slip from the latest fixtures and saves it. Sends one
  /// notification per day when a slip is available.
  static Future<void> refresh(List<FixtureModel> fixtures) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final generated = SlipGenerator.generateTargetSlip(fixtures);

      if (generated == null) {
        await prefs.remove(_slipKey);
        return;
      }

      final slip = SuggestedSlip(
        title: generated.title,
        totalOdds: generated.totalOdds,
        selections: generated.selections,
      );
      await prefs.setString(_slipKey, jsonEncode(slip.toJson()));

      final today = DateTime.now().toIso8601String().substring(0, 10);
      if (prefs.getString(_notifiedDayKey) != today) {
        await prefs.setString(_notifiedDayKey, today);
        await NotificationService.showNow(
          slip.title,
          'New slip ready: ${slip.totalOdds.toStringAsFixed(2)}x. Open the Slips tab to view the picks.',
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

  @override
  void initState() {
    super.initState();
    _loadSavedSlips();
    _loadFixtures();
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

        final fixtures = snapshot.data!;
        return RefreshIndicator(
          onRefresh: () async => _loadFixtures(),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: fixtures.length,
            itemBuilder: (context, index) {
              final fixture = fixtures[index];
              final isSaved = _savedKeys.contains(fixture.key);
              final String whenText =
                  fixture.isFinished ? 'FT ${fixture.actualScore}' : fixture.timeLabel;

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

  Widget _legStatusChip(String status) {
    Color bg;
    Color fg;
    String text;
    switch (status) {
      case 'won':
        bg = Colors.green.shade100;
        fg = Colors.green.shade800;
        text = 'WON';
        break;
      case 'lost':
        bg = Colors.red.shade100;
        fg = Colors.red.shade800;
        text = 'LOST';
        break;
      case 'void':
        bg = Colors.blueGrey.shade100;
        fg = Colors.blueGrey.shade700;
        text = 'VOID';
        break;
      case 'none':
        bg = Colors.grey.shade200;
        fg = Colors.grey.shade700;
        text = 'NO TIP';
        break;
      default:
        bg = Colors.grey.shade200;
        fg = Colors.grey.shade700;
        text = 'PENDING';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

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
            Row(
              children: [
                Expanded(
                  child: Text(slip.title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                Text('${slip.totalOdds.toStringAsFixed(2)}x',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16, color: kTealGreen)),
              ],
            ),
            const SizedBox(height: 8),
            for (int i = 0; i < slip.selections.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(
                  '${i + 1}. ${slip.selections[i]['match']} - ${slip.selections[i]['prediction']} (${slip.selections[i]['odds']})',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'Chance that every leg wins: about ${chance.toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(SuggestedSlipStore.note,
                style: TextStyle(fontSize: 11, color: mutedText(context))),
          ],
        ),
      ),
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
            if (data.suggested != null) _suggestedCard(context, data.suggested!),
            if (legs.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No saved picks yet. Bookmark matches from the Fixtures tab to add them here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: mutedText(context)),
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
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
              for (int i = 0; i < legs.length; i++)
                Card(
                  color: cardBg(context),
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: kTealGreen,
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                    title: Text('${legs[i].home} vs ${legs[i].away}'),
                    subtitle: Text(
                        'Tip: ${legs[i].tip.isEmpty ? 'None' : legs[i].tip} | Score: ${legs[i].score.isEmpty ? 'Pending' : legs[i].score}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _legStatusChip(legs[i].status),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () async {
                            await SlipStore.remove(legs[i].key);
                            _loadSlips();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
            ],
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
