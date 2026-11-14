import 'package:flutter/material.dart';
import 'app_settings.dart';
import 'api_service.dart';
import 'fixture_model.dart';
import 'bankroll.dart';
import 'league_data.dart';
import 'notification_service.dart';
import 'prediction_log.dart';
import 'slip_store.dart';

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

class MainHomeScreen extends StatefulWidget {
  const MainHomeScreen({super.key});

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    FixturesTab(),
    StandingsScorersTab(),
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
    setState(() {
      _savedKeys = legs.map((l) => l.key).toSet();
    });
  }

  void _loadFixtures() {
    setState(() {
      _fixturesFuture = ApiService.fetchFixtures().then((fixtures) async {
        await PredictionLog.update(fixtures);
        await SlipStore.settle(fixtures);
        await NotificationService.scheduleKickoffReminders(
          fixtures,
          _savedKeys,
          AppSettings.favorites.value,
        );
        return fixtures;
      });
    });
  }

  Future<void> _toggleSave(FixtureModel fixture) async {
    await SlipStore.toggle(fixture);
    await _loadSavedSlips();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_savedKeys.contains(fixture.key) ? 'Removed from saved slips' : 'Saved to slips')),
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
                          Text(fixture.league.toUpperCase(),
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: mutedText(context))),
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
                      const Divider(height: 20),
                      if (fixture.hasPrediction) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Top Tip: ${fixture.topTip}',
                                style: const TextStyle(fontWeight: FontWeight.bold, color: kPrimary, fontSize: 13)),
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
                            Expanded(child: Text('Home: ${fixture.homeWinProb}%', style: const TextStyle(fontSize: 12))),
                            Expanded(child: Text('Draw: ${fixture.drawProb}%', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
                            Expanded(child: Text('Away: ${fixture.awayWinProb}%', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
                          ],
                        ),
                      ] else ...[
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

class SavedSlipsTab extends StatefulWidget {
  const SavedSlipsTab({super.key});

  @override
  State<SavedSlipsTab> createState() => _SavedSlipsTabState();
}

class _SavedSlipsTabState extends State<SavedSlipsTab> {
  late Future<List<SlipLeg>> _slipsFuture;

  @override
  void initState() {
    super.initState();
    _loadSlips();
  }

  void _loadSlips() {
    setState(() {
      _slipsFuture = SlipStore.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SlipLeg>>(
      future: _slipsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('No saved slips yet. Bookmark matches from the fixtures tab!'));
        }

        final legs = snapshot.data!;
        final summary = SlipStore.summary(legs);

        return Column(
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
                      _statItem('Accumulator Status', summary.status),
                      _statItem('Won', '${summary.won}'),
                      _statItem('Lost', '${summary.lost}'),
                      _statItem('Pending', '${summary.pending}'),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: legs.length,
                itemBuilder: (context, index) {
                  final leg = legs[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text('${leg.home} vs ${leg.away}'),
                      subtitle: Text('Tip: ${leg.tip} | Score: ${leg.score.isEmpty ? 'Pending' : leg.score}'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () async {
                          await SlipStore.remove(leg.key);
                          _loadSlips();
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
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
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('No prediction history recorded yet.'));
        }

        final entries = snapshot.data!;
        final stats = PredictionLog.stats(entries);

        return Column(
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

class StandingsScorersTab extends StatefulWidget {
  const StandingsScorersTab({super.key});

  @override
  State<StandingsScorersTab> createState() => _StandingsScorersTabState();
}

class _StandingsScorersTabState extends State<StandingsScorersTab> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedLeague = 'PL';

  final Map<String, String> _leagues = {
    'PL': 'Premier League',
    'CL': 'Champions League',
    'PD': 'La Liga',
    'SA': 'Serie A',
    'BL1': 'Bundesliga',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Select League:', style: TextStyle(fontWeight: FontWeight.bold)),
              DropdownButton<String>(
                value: _selectedLeague,
                items: _leagues.entries.map((entry) {
                  return DropdownMenuItem(
                    value: entry.key,
                    child: Text(entry.value),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedLeague = val;
                    });
                  }
                },
              ),
            ],
          ),
        ),
        TabBar(
          controller: _tabController,
          labelColor: kPrimary,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(text: 'Standings'),
            Tab(text: 'Top Scorers'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              StandingsView(code: _selectedLeague),
              ScorersView(code: _selectedLeague),
            ],
          ),
        ),
      ],
    );
  }
}

class StandingsView extends StatelessWidget {
  final String code;
  const StandingsView({super.key, required this.code});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<StandingGroup>>(
      future: LeagueApi.standings(code),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}', textAlign: TextAlign.center));
        } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('No standings available.'));
        }

        final groups = snapshot.data!;
        return ListView.builder(
          itemCount: groups.length,
          itemBuilder: (context, gIndex) {
            final group = groups[gIndex];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (group.name.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Text(group.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: group.rows.length,
                  itemBuilder: (context, rIndex) {
                    final row = group.rows[rIndex];
                    return ListTile(
                      leading: Text('${row.position}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      title: Text(row.team),
                      subtitle: Text('P: ${row.played} | GD: ${row.goalDifference}'),
                      trailing: Text('${row.points} pts', style: const TextStyle(fontWeight: FontWeight.bold, color: kPrimary)),
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class ScorersView extends StatelessWidget {
  final String code;
  const ScorersView({super.key, required this.code});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ScorerRow>>(
      future: LeagueApi.scorers(code),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}', textAlign: TextAlign.center));
        } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('No top scorers available.'));
        }

        final scorers = snapshot.data!;
        return ListView.builder(
          itemCount: scorers.length,
          itemBuilder: (context, index) {
            final scorer = scorers[index];
            return ListTile(
              leading: Text('${index + 1}', style: const TextStyle(fontWeight: FontWeight.bold)),
              title: Text(scorer.name),
              subtitle: Text(scorer.team),
              trailing: Text('${scorer.goals} Goals', style: const TextStyle(fontWeight: FontWeight.bold, color: kPrimary)),
            );
          },
        );
      },
    );
  }
}
