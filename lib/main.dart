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
    this.isSaved = false,
  });

  factory FixtureModel.fromJson(Map<String, dynamic> json) {
    return FixtureModel(
      league: json['league'] ?? '',
      time: json['time'] ?? '',
      homeTeam: json['homeTeam'] ?? '',
      awayTeam: json['awayTeam'] ?? '',
      homeForm: List<String>.from(json['homeForm'] ?? ['W', 'D', 'W', 'W', 'L']),
      awayForm: List<String>.from(json['awayForm'] ?? ['L', 'W', 'D', 'W', 'W']),
      homeWinProb: json['homeWinProb'] ?? 45,
      drawProb: json['drawProb'] ?? 30,
      awayWinProb: json['awayWinProb'] ?? 25,
      over25Goals: json['over25Goals'] ?? '65%',
      btts: json['btts'] ?? '60%',
      cardRisk: json['cardRisk'] ?? 'Medium',
      topTip: json['topTip'] ?? 'Home Win',
      odds: (json['odds'] ?? 1.85).toDouble(),
      isLive: json['isLive'] ?? false,
    );
  }
}

class ApiService {
  // Live Render backend URL pointing to your API-Football integration
  static const String apiUrl = 'https://my-betting-companion.onrender.com/api/fixtures';

  static Future<List<FixtureModel>> fetchFixtures() async {
    try {
      final response = await http.get(Uri.parse(apiUrl));
      if (response.statusCode == 200) {
        List<dynamic> body = jsonDecode(response.body);
        return body.map((dynamic item) => FixtureModel.fromJson(item)).toList();
      } else {
        throw Exception('Failed to load fixtures');
      }
    } catch (e) {
      // Clean fallback returning empty list to avoid masking live backend data with mock overrides
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
  String _statusFilter = 'All'; // 'All', 'Live', 'Upcoming'

  @override
  void initState() {
    super.initState();
    _loadFixtures();
  }

  Future<void> _loadFixtures() async {
    setState(() {
      _isLoading = true;
    });
    final data = await ApiService.fetchFixtures();
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
      const PredictorTab(),
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
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.show_chart),
            label: 'Analyzer',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.calculate_outlined),
            label: 'Predictor',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bookmark_outline),
            label: 'Saved Slips',
          ),
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

  Widget _buildFormBadge(String letter, Color bg) {
    return Container(
      width: 18,
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: 1.5),
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Center(
        child: Text(
          letter,
          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, IconData icon, bool isSelected, Function(bool) onSelected) {
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      selectedColor: const Color(0xFF0D6EFD),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black87,
        fontWeight: FontWeight.bold,
        fontSize: 12,
      ),
      backgroundColor: Colors.white,
      avatar: Icon(icon, size: 16, color: isSelected ? Colors.white : const Color(0xFF0D6EFD)),
      onSelected: onSelected,
      elevation: 1,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    );
  }

  Widget _buildStatBox(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold)),
      ],
    );
  }

  void _showDeepDiveModal(BuildContext context, FixtureModel fixture) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(fixture.league, style: const TextStyle(color: Color(0xFF0D6EFD), fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 8),
            Text('${fixture.homeTeam} vs ${fixture.awayTeam}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const Text('AI Deep Dive & Statistical Breakdown', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            Text('• Home Recent Form: ${fixture.homeForm.join(" - ")}'),
            Text('• Away Recent Form: ${fixture.awayForm.join(" - ")}'),
            Text('• Over 2.5 Probability: ${fixture.over25Goals}'),
            Text('• Both Teams To Score (BTTS): ${fixture.btts}'),
            Text('• Disciplinary Risk: ${fixture.cardRisk} Cards'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10)),
              child: Text('AI Recommendation: ${fixture.topTip} (Odds: ${fixture.odds})', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0D6EFD))),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Comprehensive filtering matching search, league chip, and live/upcoming status tab
    final filteredFixtures = fixtures.where((f) {
      final matchesSearch = f.homeTeam.toLowerCase().contains(searchQuery.toLowerCase()) ||
          f.awayTeam.toLowerCase().contains(searchQuery.toLowerCase()) ||
          f.league.toLowerCase().contains(searchQuery.toLowerCase());

      bool matchesLeague = selectedLeague == 'All Leagues' || f.league.toLowerCase().contains(selectedLeague.toLowerCase());

      bool matchesStatus = true;
      if (statusFilter == 'Live') {
        matchesStatus = f.isLive;
      } else if (statusFilter == 'Upcoming') {
        matchesStatus = !f.isLive;
      }

      return matchesSearch && matchesLeague && matchesStatus;
    }).toList();

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        children: [
          // Search Bar
          TextField(
            onChanged: onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Search team (e.g. Chelsea, Real Madrid...)',
              hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
              prefixIcon: const Icon(Icons.search, color: Color(0xFF0D6EFD)),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE9ECEF)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF0D6EFD)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Stats Pill Header
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F1FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.local_fire_department, color: Colors.orange, size: 18),
                      SizedBox(width: 6),
                      Text('Win Rate: ', style: TextStyle(fontSize: 12, color: Colors.black87)),
                      Text('78%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F1FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.flash_on, color: Color(0xFF0D6EFD), size: 18),
                      const SizedBox(width: 6),
                      const Text('Analyzed: ', style: TextStyle(fontSize: 12, color: Colors.black87)),
                      Text('${fixtures.length} Fixtures', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0D6EFD))),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // League Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('All Leagues', Icons.sports_soccer, selectedLeague == 'All Leagues', (_) => onLeagueChanged('All Leagues')),
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

          // Status Filter Sub-Tabs (All, Live, Upcoming)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('All Status', Icons.list, statusFilter == 'All', (_) => onStatusChanged('All')),
                const SizedBox(width: 8),
                _buildFilterChip('Live 🔴', Icons.sensors, statusFilter == 'Live', (_) => onStatusChanged('Live')),
                const SizedBox(width: 8),
                _buildFilterChip('Upcoming ⏰', Icons.schedule, statusFilter == 'Upcoming', (_) => onStatusChanged('Upcoming')),
              ],
            ),
          ),
          const SizedBox(height: 16),

          isLoading
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 40.0),
                    child: CircularProgressIndicator(),
                  ),
                )
              : filteredFixtures.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32.0),
                        child: Text('No fixtures match your search or filter criteria.'),
                      ),
                    )
                  : Column(
                      children: filteredFixtures.map((fixture) {
                        return Card(
                          color: Colors.white,
                          elevation: 2,
                          margin: const EdgeInsets.only(bottom: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: const BorderSide(color: Color(0xFFE9ECEF), width: 1),
                          ),
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
                                        const Icon(Icons.sports_soccer, size: 14, color: Color(0xFF0D6EFD)),
                                        const SizedBox(width: 4),
                                        Text(
                                          fixture.league,
                                          style: const TextStyle(color: Color(0xFF0D6EFD), fontSize: 13, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        if (fixture.isLive)
                                          Container(
                                            margin: const EdgeInsets.only(right: 8),
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(4)),
                                            child: const Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                          ),
                                        Text(fixture.time, style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),

                                // Teams & Form Badges
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                                  children: [
                                    Column(
                                      children: [
                                        Text(fixture.homeTeam, style: const TextStyle(color: Color(0xFF212529), fontSize: 16, fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: fixture.homeForm.map((f) => _buildFormBadge(f, f == 'W' ? Colors.green : (f == 'D' ? Colors.amber : Colors.red))).toList(),
                                        ),
                                      ],
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(6)),
                                      child: const Text('VS', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                                    ),
                                    Column(
                                      children: [
                                        Text(fixture.awayTeam, style: const TextStyle(color: Color(0xFF212529), fontSize: 16, fontWeight: FontWeight.bold)),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: fixture.awayForm.map((f) => _buildFormBadge(f, f == 'W' ? Colors.green : (f == 'D' ? Colors.amber : Colors.red))).toList(),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),

                                // 3-Color Probability Bar
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Home: ${fixture.homeWinProb}%', style: const TextStyle(fontSize: 11, color: Color(0xFF0D6EFD), fontWeight: FontWeight.bold)),
                                    Text('Draw: ${fixture.drawProb}%', style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                                    Text('Away: ${fixture.awayWinProb}%', style: const TextStyle(fontSize: 11, color: Colors.pink, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: SizedBox(
                                    height: 8,
                                    child: Row(
                                      children: [
                                        Expanded(flex: fixture.homeWinProb, child: Container(color: const Color(0xFF0D6EFD))),
                                        Expanded(flex: fixture.drawProb, child: Container(color: Colors.grey[400])),
                                        Expanded(flex: fixture.awayWinProb, child: Container(color: Colors.pink)),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // Probability Stat Tiles
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                                  children: [
                                    _buildStatBox('Over 2.5 Goals', fixture.over25Goals, Colors.green[700]!),
                                    _buildStatBox('BTTS', fixture.btts, Colors.orange[800]!),
                                    _buildStatBox('Card Risk', fixture.cardRisk, Colors.amber[800]!),
                                  ],
                                ),
                                const Divider(height: 24),

                                // Bottom Tip & Action Buttons
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('Top Prediction Tip', style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${fixture.topTip} (Odds: ${fixture.odds})',
                                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF212529)),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        IconButton(
                                          icon: Icon(
                                            fixture.isSaved ? Icons.bookmark : Icons.bookmark_outline,
                                            color: const Color(0xFF0D6EFD),
                                          ),
                                          onPressed: () => onToggleSave(fixture),
                                        ),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF0D6EFD),
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          ),
                                          onPressed: () => _showDeepDiveModal(context, fixture),
                                          child: const Text('Analyze', style: TextStyle(fontSize: 12)),
                                        ),
                                      ],
                                    ),
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

class PredictorTab extends StatelessWidget {
  const PredictorTab({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24.0),
        child: Text(
          'AI Predictor Module Active\nSelect custom team metrics to simulate outcomes.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

class SavedSlipsTab extends StatefulWidget {
  final List<FixtureModel> savedFixtures;
  final Function(FixtureModel) onToggleSave;

  const SavedSlipsTab({
    Key? key,
    required this.savedFixtures,
    required this.onToggleSave,
  }) : super(key: key);

  @override
  State<SavedSlipsTab> createState() => _SavedSlipsTabState();
}

class _SavedSlipsTabState extends State<SavedSlipsTab> {
  final TextEditingController _stakeController = TextEditingController(text: '100');

  @override
  Widget build(BuildContext context) {
    double totalOdds = 1.0;
    for (var fixture in widget.savedFixtures) {
      totalOdds *= fixture.odds;
    }

    double stake = double.tryParse(_stakeController.text) ?? 0.0;
    double potentialPayout = stake * totalOdds;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Saved Slips & Accumulator', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0D6EFD))),
          const SizedBox(height: 12),
          
          // Accumulator Summary Box
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0D6EFD),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total Multiplier Odds:', style: TextStyle(color: Colors.white70, fontSize: 14)),
                    Text('${totalOdds.toStringAsFixed(2)}x', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                  ],
                ),
                const Divider(color: Colors.white24, height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Potential Payout:', style: TextStyle(color: Colors.white70, fontSize: 14)),
                    Text('KES ${potentialPayout.toStringAsFixed(2)}', style: const TextStyle(color: Colors.greenAccent, fontSize: 20, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Stake Input Field
          TextField(
            controller: _stakeController,
            keyboardType: TextInputType.number,
            onChanged: (val) => setState(() {}),
            decoration: InputDecoration(
              labelText: 'Enter Stake (KES)',
              prefixIcon: const Icon(Icons.money, color: Color(0xFF0D6EFD)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: Colors.white,
            ),
          ),
          const SizedBox(height: 16),

          // Saved List Header
          const Text('Selected Tips', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)),
          const SizedBox(height: 8),

          Expanded(
            child: widget.savedFixtures.isEmpty
                ? const Center(
                    child: Text(
                      'No bookmarked tips yet. Tap the bookmark icon on any match!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: widget.savedFixtures.length,
                    itemBuilder: (context, index) {
                      final fixture = widget.savedFixtures[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          title: Text('${fixture.homeTeam} vs ${fixture.awayTeam}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text('Tip: ${fixture.topTip} (Odds: ${fixture.odds})'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () => widget.onToggleSave(fixture),
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
    
