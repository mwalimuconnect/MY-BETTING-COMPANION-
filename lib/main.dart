import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

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

class FixtureModel {
  final String league;
  final String time;
  final String homeTeam;
  final String awayTeam;
  final List<String> homeForm;
  final List<String> awayForm;
  final int homeWinProb;
  final int drawProb;
  final int awayWinProb;
  final String over25Goals;
  final String btts;
  final String cardRisk;
  final String topTip;
  final double odds;
  final bool isLive;
  final bool isFinished;
  final String actualScore;
  final bool? predictionCorrect;
  final bool isProlific;
  bool isSaved;

  FixtureModel({
    required this.league,
    required this.time,
    required this.homeTeam,
    required this.awayTeam,
    required this.homeForm,
    required this.awayForm,
    required this.homeWinProb,
    required this.drawProb,
    required this.awayWinProb,
    required this.over25Goals,
    required this.btts,
    required this.cardRisk,
    required this.topTip,
    required this.odds,
    this.isLive = false,
    this.isFinished = false,
    this.actualScore = 'Pending',
    this.predictionCorrect,
    this.isProlific = false,
    this.isSaved = false,
  });

  factory FixtureModel.fromJson(Map<String, dynamic> json) {
    return FixtureModel(
      league: json['league']?.toString() ?? '',
      time: json['time']?.toString() ?? '',
      homeTeam: json['homeTeam']?.toString() ?? '',
      awayTeam: json['awayTeam']?.toString() ?? '',
      homeForm: json['homeForm'] != null ? List<String>.from(json['homeForm']) : ['W', 'D', 'W', 'W', 'L'],
      awayForm: json['awayForm'] != null ? List<String>.from(json['awayForm']) : ['L', 'W', 'D', 'W', 'W'],
      homeWinProb: int.tryParse(json['homeWinProb']?.toString() ?? '') ?? 45,
      drawProb: int.tryParse(json['drawProb']?.toString() ?? '') ?? 30,
      awayWinProb: int.tryParse(json['awayWinProb']?.toString() ?? '') ?? 25,
      over25Goals: json['over25Goals']?.toString() ?? '65%',
      btts: json['btts']?.toString() ?? '60%',
      cardRisk: json['cardRisk']?.toString() ?? 'Medium',
      topTip: json['topTip']?.toString() ?? 'Home Win',
      odds: double.tryParse(json['odds']?.toString() ?? '') ?? 1.85,
      isLive: json['isLive'] == true,
      isFinished: json['isFinished'] == true,
      actualScore: json['actualScore']?.toString() ?? 'Pending',
      predictionCorrect: json['predictionCorrect'] is bool ? json['predictionCorrect'] : null,
      isProlific: json['isProlific'] == true,
    );
  }
}

class ApiService {
  static const String apiUrl = 'https://my-betting-companion.onrender.com/api/fixtures';

  static Future<List<FixtureModel>> fetchFixtures() async {
    try {
      print('HTTP GETting fixtures from: $apiUrl');
      final response = await http.get(Uri.parse(apiUrl)).timeout(const Duration(seconds: 40));
      print('Response Status Code: ${response.statusCode}');
      print('Response Body: ${response.body}');

      if (response.statusCode == 200) {
        var decoded = jsonDecode(response.body);
        List<dynamic> body = [];
        
        if (decoded is List) {
          body = decoded;
        } else if (decoded is Map) {
          body = decoded['fixtures'] ?? decoded['response'] ?? [];
        }

        print('Parsed ${body.length} items from JSON body');
        return body.map((dynamic item) => FixtureModel.fromJson(item)).toList();
      } else {
        print('Server returned non-200 code: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('CRITICAL FETCH ERROR: $e');
      return [];
    }
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({Key? key}) : super(key: key);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  List<FixtureModel> _fixtures = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedLeague = 'All Leagues';
  String _statusFilter = 'All'; // 'All', 'Live', 'Upcoming', 'Finished'

  @override
  void initState() {
    super.initState();
    _loadFixtures();
  }

  Future<void> _loadFixtures() async {
    setState(() => _isLoading = true);
    
    List<FixtureModel> data = await ApiService.fetchFixtures();
    
    // Automatic retry if Render cold start delayed the first request
    if (data.isEmpty) {
      print('First fetch empty (Render cold start). Retrying in 3 seconds...');
      await Future.delayed(const Duration(seconds: 3));
      data = await ApiService.fetchFixtures();
    }

    setState(() {
      _fixtures = data;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final savedFixtures = _fixtures.where((f) => f.isSaved).toList();

    final List<Widget> pages = [
      MatchesAnalysisTab(
        fixtures: _fixtures,
        isLoading: _isLoading,
        searchQuery: _searchQuery,
        selectedLeague: _selectedLeague,
        statusFilter: _statusFilter,
        onSearchChanged: (q) => setState(() => _searchQuery = q),
        onLeagueChanged: (l) => setState(() => _selectedLeague = l),
        onStatusChanged: (s) => setState(() => _statusFilter = s),
        onRefresh: _loadFixtures,
        onToggleSave: (fixture) {
          setState(() {
            fixture.isSaved = !fixture.isSaved;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(fixture.isSaved ? 'Tip added to saved slips!' : 'Tip removed from slips.'),
              duration: const Duration(seconds: 1),
            ),
          );
        },
      ),
      PredictionsOutcomeTab(fixtures: _fixtures),
      SavedSlipsTab(
        savedFixtures: savedFixtures,
        onToggleSave: (fixture) {
          setState(() {
            fixture.isSaved = !fixture.isSaved;
          });
        },
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
                color: Color(0xFF0D6EFD),
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
        selectedItemColor: const Color(0xFF0D6EFD),
        unselectedItemColor: Colors.grey,
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.show_chart), label: 'Analyzer'),
          BottomNavigationBarItem(icon: Icon(Icons.table_chart_outlined), label: 'Results & Accuracy'),
          BottomNavigationBarItem(icon: Icon(Icons.bookmark_outline), label: 'Saved Slips'),
        ],
      ),
    );
  }
}
class MatchesAnalysisTab extends StatelessWidget {
  final List<FixtureModel> fixtures;
  final bool isLoading;
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
    required this.searchQuery,
    required this.selectedLeague,
    required this.statusFilter,
    required this.onSearchChanged,
    required this.onLeagueChanged,
    required this.onStatusChanged,
    required this.onRefresh,
    required this.onToggleSave,
  }) : super(key: key);

  Widget _buildFilterChip(String label, IconData icon, bool isSelected, Function(bool) onSelected, {Color? activeColor}) {
    final chipColor = activeColor ?? const Color(0xFF0D6EFD);
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
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

  @override
  Widget build(BuildContext context) {
    final filteredFixtures = fixtures.where((f) {
      final matchesSearch = searchQuery.isEmpty ||
          f.homeTeam.toLowerCase().contains(searchQuery.toLowerCase()) ||
          f.awayTeam.toLowerCase().contains(searchQuery.toLowerCase()) ||
          f.league.toLowerCase().contains(searchQuery.toLowerCase());

      bool matchesLeague = selectedLeague == 'All Leagues';
      if (selectedLeague == 'Prolific') {
        matchesLeague = f.isProlific;
      } else if (selectedLeague == 'Euro') {
        matchesLeague = f.league.toLowerCase().contains('euro');
      } else if (selectedLeague == 'Copa') {
        matchesLeague = f.league.toLowerCase().contains('copa');
      } else if (selectedLeague == 'Asian Cup') {
        matchesLeague = f.league.toLowerCase().contains('asian');
      } else if (selectedLeague == 'Gold Cup') {
        matchesLeague = f.league.toLowerCase().contains('gold cup') || f.league.toLowerCase().contains('concacaf');
      } else if (selectedLeague == 'OFC') {
        matchesLeague = f.league.toLowerCase().contains('ofc') || f.league.toLowerCase().contains('nations cup');
      } else if (selectedLeague == 'Premier League') {
        matchesLeague = f.league.toLowerCase().contains('premier') || f.league.toLowerCase().contains('england');
      } else if (selectedLeague == 'La Liga') {
        matchesLeague = f.league.toLowerCase().contains('liga') || f.league.toLowerCase().contains('spain');
      } else if (selectedLeague == 'Serie A') {
        matchesLeague = f.league.toLowerCase().contains('serie') || f.league.toLowerCase().contains('italy');
      }

      bool matchesStatus = true;
      if (statusFilter == 'Live') {
        matchesStatus = f.isLive;
      } else if (statusFilter == 'Upcoming') {
        matchesStatus = !f.isLive && !f.isFinished;
      } else if (statusFilter == 'Finished') {
        matchesStatus = f.isFinished;
      }

      return matchesSearch && matchesLeague && matchesStatus;
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
              prefixIcon: const Icon(Icons.search, color: Color(0xFF0D6EFD)),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE9ECEF))),
            ),
          ),
SingleChildScrollView(
  scrollDirection: Axis.horizontal,
  child: Row(
    children: [
      _buildFilterChip('All Competitions', Icons.sports_soccer, selectedLeague == 'All Leagues', (_) => onLeagueChanged('All Leagues')),
      const SizedBox(width: 8),
      _buildFilterChip('Prolific Basket', Icons.local_fire_department, selectedLeague == 'Prolific', (_) => onLeagueChanged('Prolific'), activeColor: Colors.orange[800]),
      const SizedBox(width: 8),
      _buildFilterChip('All International', Icons.public, selectedLeague == 'International', (_) => onLeagueChanged('International')),
      const SizedBox(width: 8),
      _buildFilterChip('Premier League', Icons.flag, selectedLeague == 'Premier League', (_) => onLeagueChanged('Premier League')),
      const SizedBox(width: 8),
      _buildFilterChip('La Liga', Icons.shield, selectedLeague == 'La Liga', (_) => onLeagueChanged('La Liga')),
      const SizedBox(width: 8),
      _buildFilterChip('Serie A', Icons.sports, selectedLeague == 'Serie A', (_) => onLeagueChanged('Serie A')),
    ],
  ),
),
const SizedBox(height: 10),
SingleChildScrollView(
  scrollDirection: Axis.horizontal,
  child: Row(
    children: [
      _buildFilterChip('All Status', Icons.list, statusFilter == 'All', (_) => onStatusChanged('All')),
      const SizedBox(width: 8),
      _buildFilterChip('Live', Icons.sensors, statusFilter == 'Live', (_) => onStatusChanged('Live')),
      const SizedBox(width: 8),
      _buildFilterChip('Upcoming', Icons.schedule, statusFilter == 'Upcoming', (_) => onStatusChanged('Upcoming')),
      const SizedBox(width: 8),
      _buildFilterChip('Finished (FT)', Icons.done_all, statusFilter == 'Finished', (_) => onStatusChanged('Finished')),
    ],
  ),
),
   const SizedBox(height: 16),
          isLoading
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 40.0),
                    child: Column(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('Waking up server & fetching fixtures...', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ],
                    ),
                  ),
                )
              : filteredFixtures.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          children: [
                            const Text('No fixtures match your search or filter criteria.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 13)),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: onRefresh,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry Connection'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Column(
                      children: filteredFixtures.map((fixture) {
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
                                    Row(
                                      children: [
                                        Text(fixture.league, style: const TextStyle(color: Color(0xFF0D6EFD), fontSize: 13, fontWeight: FontWeight.bold)),
                                        if (fixture.isProlific) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                            decoration: BoxDecoration(color: Colors.orange[100], borderRadius: BorderRadius.circular(4)),
                                            child: const Text('🔥 PROLIFIC', style: TextStyle(color: Colors.orange, fontSize: 9, fontWeight: FontWeight.bold)),
                                          ),
                                        ],
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        if (fixture.isFinished)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(color: Colors.grey[700], borderRadius: BorderRadius.circular(4)),
                                            child: Text('FT: ${fixture.actualScore}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                          )
                                        else if (fixture.isLive)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
                                            child: Text('LIVE: ${fixture.time}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                          )
                                        else
                                          Text(fixture.time, style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                                        const SizedBox(width: 8),
                                        IconButton(
                                          icon: Icon(
                                            fixture.isSaved ? Icons.bookmark : Icons.bookmark_border,
                                            color: const Color(0xFF0D6EFD),
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
                                    Text(fixture.homeTeam, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                    const Text('VS', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                                    Text(fixture.awayTeam, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                  ],
                                ),
                                const Divider(height: 20),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Tip: ${fixture.topTip} (Odds: ${fixture.odds})', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black87)),
                                    Text('Over 2.5: ${fixture.over25Goals}', style: TextStyle(fontSize: 11, color: Colors.grey[700], fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
        ],
      ),
    );
  }
}

class PredictionsOutcomeTab extends StatelessWidget {
  final List<FixtureModel> fixtures;

  const PredictionsOutcomeTab({Key? key, required this.fixtures}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final finishedFixtures = fixtures.where((f) => f.isFinished).toList();

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Predictions vs Outcomes Accuracy', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0D6EFD))),
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
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(const Color(0xFFE8F1FF)),
                      columns: const [
                        DataColumn(label: Text('Fixture', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('AI Tip', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Actual Score', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Result', style: TextStyle(fontWeight: FontWeight.bold))),
                      ],
                      rows: finishedFixtures.map((f) {
                        bool isWon = f.predictionCorrect ?? false;
                        return DataRow(cells: [
                          DataCell(Text('${f.homeTeam} vs ${f.awayTeam}')),
                          DataCell(Text(f.topTip)),
                          DataCell(Text(f.actualScore)),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isWon ? Colors.green.shade100 : Colors.red.shade100,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isWon ? 'WON ✅' : 'LOST ❌',
                                style: TextStyle(color: isWon ? Colors.green[800] : Colors.red[800], fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ]);
                      }).toList(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
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
          const Text('Saved Slips', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0D6EFD))),
          const SizedBox(height: 12),
          Expanded(
            child: savedFixtures.isEmpty
                ? const Center(child: Text('No bookmarked tips yet.', style: TextStyle(color: Colors.grey)))
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
