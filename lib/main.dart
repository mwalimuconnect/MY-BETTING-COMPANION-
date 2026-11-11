import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart';
import 'fixture_model.dart';

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

  @override
  void initState() {
    super.initState();
    _loadFixtures();
  }

  Future<void> _loadFixtures() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final savedKeys = _fixtures.where((f) => f.isSaved).map((f) => f.key).toSet();

    List<FixtureModel> data = [];
    String? error;

    // Two attempts: the first request may hit a sleeping Render server.
    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        data = await ApiService.fetchFixtures();
        error = null;
        break;
      } catch (e) {
        error = e.toString();
        debugPrint('Fetch attempt $attempt failed: $e');
        if (attempt < 2) await Future.delayed(const Duration(seconds: 3));
      }
    }

    for (final f in data) {
      f.isSaved = savedKeys.contains(f.key);
    }

    if (!mounted) return;
    setState(() {
      if (error == null) _fixtures = data; // keep old list if refresh failed
      _error = error;
      _isLoading = false;
    });
  }

  void _toggleSave(FixtureModel fixture, {bool showMessage = true}) {
    setState(() => fixture.isSaved = !fixture.isSaved);
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
    final league = f.league.toLowerCase();
    switch (selectedLeague) {
      case 'Prolific':
        return f.isProlific;
      case 'International':
        return _internationalKeywords.any(league.contains);
      case 'Premier League':
        return league.contains('premier') || league.contains('england');
      case 'La Liga':
        return league.contains('liga') || league.contains('spain');
      case 'Serie A':
        return league.contains('serie') || league.contains('italy');
      default:
        return true; // 'All Leagues'
    }
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'Tip: ${fixture.topTip} (Odds: ${fixture.odds})',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Over 2.5: ${fixture.over25Goals}',
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey[700], fontWeight: FontWeight.w600),
                ),
              ],
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
                _buildFilterChip('All Competitions', Icons.sports_soccer,
                    selectedLeague == 'All Leagues', (_) => onLeagueChanged('All Leagues')),
                const SizedBox(width: 8),
                _buildFilterChip('Prolific Basket', Icons.local_fire_department,
                    selectedLeague == 'Prolific', (_) => onLeagueChanged('Prolific'),
                    activeColor: Colors.orange[800]),
                const SizedBox(width: 8),
                _buildFilterChip('All International', Icons.public,
                    selectedLeague == 'International', (_) => onLeagueChanged('International')),
                const SizedBox(width: 8),
                _buildFilterChip('Premier League', Icons.flag,
                    selectedLeague == 'Premier League', (_) => onLeagueChanged('Premier League')),
                const SizedBox(width: 8),
                _buildFilterChip('La Liga', Icons.shield, selectedLeague == 'La Liga',
                    (_) => onLeagueChanged('La Liga')),
                const SizedBox(width: 8),
                _buildFilterChip('Serie A', Icons.sports, selectedLeague == 'Serie A',
                    (_) => onLeagueChanged('Serie A')),
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
class PredictionsOutcomeTab extends StatelessWidget {
  final List<FixtureModel> fixtures;

  const PredictionsOutcomeTab({Key? key, required this.fixtures}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final finishedFixtures = fixtures.where((f) => f.isFinished).toList();
    final hasEstimates = finishedFixtures.any((f) => f.isEstimate);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Predictions vs Outcomes Accuracy',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kPrimary),
          ),
          if (hasEstimates) ...[
            const SizedBox(height: 6),
            Text(
              'Note: tips here are placeholder estimates, not real predictions yet.',
              style: TextStyle(color: Colors.orange[800], fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          Expanded(
            child: finishedFixtures.isEmpty
                ? const Center(
                    child: Text(
                      'No finished matches available for outcome comparison yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : SingleChildScrollView(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(const Color(0xFFE8F1FF)),
                        columns: const [
                          DataColumn(
                              label: Text('Fixture',
                                  style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('AI Tip',
                                  style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('Actual Score',
                                  style: TextStyle(fontWeight: FontWeight.bold))),
                          DataColumn(
                              label: Text('Result',
                                  style: TextStyle(fontWeight: FontWeight.bold))),
                        ],
                        rows: finishedFixtures.map((f) {
                          final isWon = f.predictionCorrect ?? false;
                          return DataRow(cells: [
                            DataCell(Text('${f.homeTeam} vs ${f.awayTeam}')),
                            DataCell(Text(f.topTip)),
                            DataCell(Text(f.actualScore)),
                            DataCell(
                              Container(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isWon ? Colors.green.shade100 : Colors.red.shade100,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isWon ? 'WON \u2705' : 'LOST \u274C',
                                  style: TextStyle(
                                    color: isWon ? Colors.green[800] : Colors.red[800],
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                          ]);
                        }).toList(),
                      ),
                    ),
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
                          subtitle: Text('Tip: ${fixture.topTip} (Odds: ${fixture.odds})'),
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
