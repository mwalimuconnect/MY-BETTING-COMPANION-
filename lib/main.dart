import 'package:flutter/material.dart';
import 'api_service.dart';
import 'fixture_model.dart';
import 'prediction_log.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Color kPrimary = Color(0xFF0D6EFD);

void main() {
  runApp(const MyBettingCompanionApp());
}

class MyBettingCompanionApp extends StatelessWidget {
  const MyBettingCompanionApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MY BETTING COMPANION',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
      ),
      home: const DashboardScreen(),
    );
  }
}

// ---------------------------------------------------------------------------
// Dashboard
// ---------------------------------------------------------------------------
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  List<FixtureModel> _fixtures = [];
  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';
  String _selectedLeague = 'All Leagues';
  String _statusFilter = 'All'; // 'All', 'Live', 'Upcoming', 'Finished'
  Set<String> _savedKeys = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _savedKeys = (prefs.getStringList('saved_slip_keys') ?? []).toSet();
    _loadFixtures();
  }

  Future<void> _persistSaved() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('saved_slip_keys', _savedKeys.toList());
  }

  Future<void> _loadFixtures() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    List<FixtureModel> data = [];
    String? error;

    // Retry a few times: the first request may hit a sleeping Render server.
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        data = await ApiService.fetchFixtures();
        error = null;
        break;
      } catch (e) {
        error = e.toString();
        debugPrint('Fetch attempt $attempt failed: $e');
        if (attempt < 3) await Future.delayed(const Duration(seconds: 5));
      }
    }

    for (final f in data) {
      f.isSaved = _savedKeys.contains(f.key);
    }

    if (error == null) {
      try {
        await PredictionLog.update(data);
      } catch (e) {
        debugPrint('Prediction log update failed: $e');
      }
    }

    if (!mounted) return;
    setState(() {
      if (error == null) _fixtures = data; // keep old list if refresh failed
      _error = error;
      _isLoading = false;
    });
  }  
    
  void _toggleSave(FixtureModel fixture, {bool showMessage = true}) {
    setState(() {
      fixture.isSaved = !fixture.isSaved;
      final k = fixture.key;
      if (k != null) {
        if (fixture.isSaved) {
          _savedKeys.add(k);
        } else {
          _savedKeys.remove(k);
        }
      }
    });
    _persistSaved();
    if (showMessage) {
    
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(fixture.isSaved
              ? 'Tip added to saved slips!'
              : 'Tip removed from slips.'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final savedFixtures = _fixtures.where((f) => f.isSaved).toList();

    final List<Widget> pages = [
      MatchesAnalysisTab(
        fixtures: _fixtures,
        isLoading: _isLoading,
        error: _error,
        searchQuery: _searchQuery,
        selectedLeague: _selectedLeague,
        statusFilter: _statusFilter,
        onSearchChanged: (q) => setState(() => _searchQuery = q),
        onLeagueChanged: (l) => setState(() => _selectedLeague = l),
        onStatusChanged: (s) => setState(() => _statusFilter = s),
        onRefresh: _loadFixtures,
        onToggleSave: _toggleSave,
      ),
      PredictionsOutcomeTab(fixtures: _fixtures),
      SavedSlipsTab(
        savedFixtures: savedFixtures,
        onToggleSave: (f) => _toggleSave(f, showMessage: false),
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: Column(
          children: const [
            Text(
              'MY BETTING COMPANION',
              style: TextStyle(
                color: kPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 18,
                letterSpacing: 1.1,
              ),
            ),
            Text(
              'AI-POWERED MATCH ANALYZER & STATS',
              style: TextStyle(color: Colors.grey, fontSize: 10, letterSpacing: 0.8),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.white,
        selectedItemColor: kPrimary,
        unselectedItemColor: Colors.grey,
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.show_chart), label: 'Analyzer'),
          BottomNavigationBarItem(
              icon: Icon(Icons.table_chart_outlined), label: 'Results & Accuracy'),
          BottomNavigationBarItem(icon: Icon(Icons.bookmark_outline), label: 'Saved Slips'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Competition filters (the 12 competitions on the football-data.org free plan)
// ---------------------------------------------------------------------------
class _CompetitionFilter {
  final String label; // text on the chip (also the value stored as selectedLeague)
  final IconData icon;
  final List<String> serverNames; // competition names as sent by the server

  const _CompetitionFilter(this.label, this.icon, this.serverNames);
}

const List<_CompetitionFilter> _competitionFilters = [
  _CompetitionFilter('Premier League', Icons.flag, ['Premier League']),
  _CompetitionFilter('La Liga', Icons.shield, ['Primera Division', 'La Liga']),
  _CompetitionFilter('Serie A', Icons.sports, ['Serie A']),
  _CompetitionFilter('Bundesliga', Icons.sports_soccer, ['Bundesliga']),
  _CompetitionFilter('Ligue 1', Icons.sports_soccer, ['Ligue 1']),
  _CompetitionFilter('Champions League', Icons.emoji_events, ['UEFA Champions League']),
  _CompetitionFilter('Championship', Icons.flag, ['Championship']),
  _CompetitionFilter('Eredivisie', Icons.sports_soccer, ['Eredivisie']),
  _CompetitionFilter('Primeira Liga', Icons.sports_soccer, ['Primeira Liga']),
  _CompetitionFilter('Brasileirao', Icons.sports_soccer, ['Campeonato Brasileiro Serie A']),
  _CompetitionFilter('World Cup', Icons.public, ['FIFA World Cup']),
  _CompetitionFilter('Euros', Icons.public, ['European Championship']),
];

/// Lower-cases and strips common accents so "Série A" matches "Serie A".
String _normalize(String s) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const to = 'aaaaaeeeeiiiiooooouuuucn';
  var out = s.toLowerCase().trim();
  for (var i = 0; i < from.length; i++) {
    out = out.replaceAll(from[i], to[i]);
  }
  return out;
}

// ---------------------------------------------------------------------------
// Analyzer tab
// ---------------------------------------------------------------------------
class MatchesAnalysisTab extends StatelessWidget {
  final List<FixtureModel> fixtures;
  final bool isLoading;
  final String? error;
  final String searchQuery;
  final String selectedLeague;
  final String statusFilter;
  final Function(String) onSearchChanged;
  final Function(String) onLeagueChanged;
  final Function(String) onStatusChanged;
  final Future<void> Function() onRefresh;
  final Function(FixtureModel) onToggleSave;

  const MatchesAnalysisTab({
    Key? key,
    required this.fixtures,
    required this.isLoading,
    required this.error,
    required this.searchQuery,
    required this.selectedLeague,
    required this.statusFilter,
    required this.onSearchChanged,
    required this.onLeagueChanged,
    required this.onStatusChanged,
    required this.onRefresh,
    required this.onToggleSave,
  }) : super(key: key);

  static const List<String> _internationalKeywords = [
    'friendl',
    'nations',
    'world cup',
    'qualif',
    'copa america',
    'asian cup',
    'gold cup',
    'africa cup',
    'european championship',
    'international',
  ];

  Widget _buildFilterChip(
    String label,
    IconData icon,
    bool isSelected,
    Function(bool) onSelected, {
    Color? activeColor,
  }) {
    final chipColor = activeColor ?? kPrimary;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      showCheckmark: false, // the checkmark was overlapping the icon
      selectedColor: chipColor,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black87,
        fontWeight: FontWeight.bold,
        fontSize: 12,
      ),
      backgroundColor: Colors.white,
      avatar: Icon(icon, size: 16, color: isSelected ? Colors.white : chipColor),
      onSelected: onSelected,
      elevation: 1,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    );
  }

  bool _matchesLeague(FixtureModel f) {
    final leagueName = _normalize(f.league);

    switch (selectedLeague) {
      case 'All Leagues':
        return true;
      case 'Prolific':
        return f.isProlific;
      case 'International':
        return _internationalKeywords.any(leagueName.contains);
    }

    // One of the 12 specific competitions: match the server's exact name.
    for (final c in _competitionFilters) {
      if (c.label == selectedLeague) {
        return c.serverNames.any((n) => _normalize(n) == leagueName);
      }
    }
    return true;
  }

  bool _matchesStatus(FixtureModel f) {
    switch (statusFilter) {
      case 'Live':
        return f.isLive;
      case 'Upcoming':
        return !f.isLive && !f.isFinished;
      case 'Finished':
        return f.isFinished;
      default:
        return true;
    }
  }

  Widget _badge(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
      child: Text(text,
          style: TextStyle(color: fg, fontSize: 9, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildFixtureCard(FixtureModel fixture) {
    return Card(
      color: Colors.white,
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        fixture.league,
                        style: const TextStyle(
                            color: kPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      if (fixture.isProlific)
                        _badge('\u{1F525} PROLIFIC', Colors.orange.shade100, Colors.orange),
                      if (fixture.isSample)
                        _badge('SAMPLE', Colors.purple.shade100, Colors.purple.shade700)
                      else if (fixture.isEstimate)
                        _badge('ESTIMATE', Colors.blueGrey.shade100, Colors.blueGrey.shade700),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (fixture.isFinished)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: Colors.grey[700], borderRadius: BorderRadius.circular(4)),
                        child: Text('FT: ${fixture.actualScore}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                      )
                    else if (fixture.isLive)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: Colors.red, borderRadius: BorderRadius.circular(4)),
                        child: Text('LIVE: ${fixture.time}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold)),
                      )
                    else
                      Text(fixture.time,
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(
                        fixture.isSaved ? Icons.bookmark : Icons.bookmark_border,
                        color: kPrimary,
                        size: 20,
                      ),
                      onPressed: () => onToggleSave(fixture),
                      constraints: const BoxConstraints(),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Flexible(
                  child: Text(fixture.homeTeam,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('VS',
                      style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                ),
                Flexible(
                  child: Text(fixture.awayTeam,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ],
            ),
            const Divider(height: 20),
            Text(
              'Tip: ${fixture.topTip}',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.black87),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(List<FixtureModel> filtered) {
    if (isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 40.0),
          child: Column(
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Waking up server & fetching fixtures...',
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
        ),
      );
    }

    // A real connection/server failure and an empty filter result are different.
    if (error != null && fixtures.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            children: [
              const Icon(Icons.cloud_off, size: 40, color: Colors.grey),
              const SizedBox(height: 12),
              const Text("Couldn't load fixtures.",
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry Connection'),
              ),
            ],
          ),
        ),
      );
    }

    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            children: [
              const Text('No fixtures match your search or filter criteria.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ),
      );
    }
    return Column(children: filtered.map(_buildFixtureCard).toList());
  }

  @override
  Widget build(BuildContext context) {
    final query = searchQuery.toLowerCase();
    final filteredFixtures = fixtures.where((f) {
      final matchesSearch = query.isEmpty ||
          f.homeTeam.toLowerCase().contains(query) ||
          f.awayTeam.toLowerCase().contains(query) ||
          f.league.toLowerCase().contains(query);
      return matchesSearch && _matchesLeague(f) && _matchesStatus(f);
    }).toList();

    // Competition chips: general filters first, then the 12 competitions.
    final List<Widget> competitionChips = [
      _buildFilterChip('All Competitions', Icons.sports_soccer,
          selectedLeague == 'All Leagues', (_) => onLeagueChanged('All Leagues')),
      _buildFilterChip('Prolific Basket', Icons.local_fire_department,
          selectedLeague == 'Prolific', (_) => onLeagueChanged('Prolific'),
          activeColor: Colors.orange[800]),
      _buildFilterChip('All International', Icons.public,
          selectedLeague == 'International', (_) => onLeagueChanged('International')),
      for (final c in _competitionFilters)
        _buildFilterChip(c.label, c.icon, selectedLeague == c.label,
            (_) => onLeagueChanged(c.label)),
    ];

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        children: [
          TextField(
            onChanged: onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Search team (e.g. France, Real Madrid...)',
              hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
              prefixIcon: const Icon(Icons.search, color: kPrimary),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE9ECEF)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < competitionChips.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  competitionChips[i],
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
            children: [
                _buildFilterChip('All Status', Icons.list, statusFilter == 'All',
                    (_) => onStatusChanged('All')),
                const SizedBox(width: 8),
                _buildFilterChip('Live', Icons.sensors, statusFilter == 'Live',
                    (_) => onStatusChanged('Live')),
                const SizedBox(width: 8),
                _buildFilterChip('Upcoming', Icons.schedule, statusFilter == 'Upcoming',
                    (_) => onStatusChanged('Upcoming')),
                const SizedBox(width: 8),
                _buildFilterChip('Finished (FT)', Icons.done_all, statusFilter == 'Finished',
                    (_) => onStatusChanged('Finished')),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildBody(filteredFixtures),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Results & Accuracy tab
// ---------------------------------------------------------------------------
class _PredictionsOutcomeTabState extends State<PredictionsOutcomeTab> {
  List<LogEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant PredictionsOutcomeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.fixtures, widget.fixtures)) _reload();
  }

  Future<void> _reload() async {
    final e = await PredictionLog.load();
    if (!mounted) return;
    setState(() {
      _entries = e.reversed.toList(); // newest first
      _loading = false;
    });
  }

  Widget _chip(LogEntry e) {
    String text;
    Color bg;
    Color fg;
    if (!e.settled) {
      text = 'PENDING';
      bg = Colors.grey.shade200;
      fg = Colors.grey.shade700;
    } else if (e.isVoid) {
      text = 'VOID';
      bg = Colors.blueGrey.shade100;
      fg = Colors.blueGrey.shade700;
    } else if (e.won == true) {
      text = 'WON';
      bg = Colors.green.shade100;
      fg = Colors.green.shade800;
    } else {
      text = 'LOST';
      bg = Colors.red.shade100;
      fg = Colors.red.shade800;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(text,
          style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }

  Widget _summary(LogStats s) {
    final hit = s.settled == 0
        ? '-'
        : '${(s.hitRate * 100).toStringAsFixed(1)}%';
    return Card(
      color: Colors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Logged: ${s.total}   Pending: ${s.pending}   Void: ${s.voided}',
                style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 6),
            Text('Settled: ${s.settled}   Won: ${s.wins}',
                style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 6),
            Text('Hit rate: $hit',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(
              'Odds are not shown: the server does not provide real bookmaker odds yet, so profit cannot be measured.',
              style: TextStyle(color: Colors.grey[700], fontSize: 11),
            ),
            if (s.settled < 100) ...[
              const SizedBox(height: 6),
              Text(
                'Small sample: under ~100 settled tips, results are mostly luck.',
                style: TextStyle(color: Colors.orange[800], fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stats = PredictionLog.stats(_entries);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Prediction Log',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kPrimary)),
          const SizedBox(height: 4),
          const Text(
            'Tips are saved before kickoff and checked against the real final score.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 12),
          _summary(stats),
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _entries.isEmpty
                    ? const Center(
                        child: Text(
                          'Nothing logged yet. Open the Analyzer tab and upcoming matches will be recorded automatically.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _entries.length,
                        itemBuilder: (context, i) {
                          final e = _entries[i];
                          return Card(
                            child: ListTile(
                              title: Text('${e.home} vs ${e.away}',
                                  style: const TextStyle(fontSize: 14)),
                              subtitle: Text(
                                  '${e.tip}${e.settled ? '  •  FT ${e.score}' : '  •  ${e.kickoff}'}',
                                  style: const TextStyle(fontSize: 12)),
                              trailing: _chip(e),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
                                                                                                                                             
// ---------------------------------------------------------------------------
// Saved Slips tab
// ---------------------------------------------------------------------------
class SavedSlipsTab extends StatelessWidget {
  final List<FixtureModel> savedFixtures;
  final Function(FixtureModel) onToggleSave;

  const SavedSlipsTab({
    Key? key,
    required this.savedFixtures,
    required this.onToggleSave,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Saved Slips',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kPrimary)),
          const SizedBox(height: 12),
          Expanded(
            child: savedFixtures.isEmpty
                ? const Center(
                    child: Text('No bookmarked tips yet.', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    itemCount: savedFixtures.length,
                    itemBuilder: (context, index) {
                      final fixture = savedFixtures[index];
                      return Card(
                        child: ListTile(
                          title: Text('${fixture.homeTeam} vs ${fixture.awayTeam}'),
                          subtitle: Text('Tip: ${fixture.topTip}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => onToggleSave(fixture),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

