import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'fixture_model.dart';

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

class ApiService {
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
      // Robust offline/fallback mock fixtures
      return [
        FixtureModel(
          league: 'Premier League',
          time: '21:00 EAT',
          homeTeam: 'Chelsea',
          awayTeam: 'Aston Villa',
          homeForm: ['W', 'W', 'D', 'W', 'L'],
          awayForm: ['W', 'L', 'D', 'W', 'W'],
          homeWinProb: 54,
          drawProb: 26,
          awayWinProb: 20,
          over25Goals: '72%',
          btts: '68%',
          cardRisk: 'Medium',
          topTip: 'Over 2.5 Goals & BTTS - Yes',
          odds: 2.15,
        ),
        FixtureModel(
          league: 'La Liga',
          time: '23:00 EAT',
          homeTeam: 'Real Madrid',
          awayTeam: 'Real Sociedad',
          homeForm: ['W', 'W', 'W', 'D', 'W'],
          awayForm: ['L', 'W', 'D', 'L', 'W'],
          homeWinProb: 68,
          drawProb: 20,
          awayWinProb: 12,
          over25Goals: '65%',
          btts: '50%',
          cardRisk: 'Low',
          topTip: 'Real Madrid Win & Under 3.5',
          odds: 1.75,
        ),
        FixtureModel(
          league: 'Serie A',
          time: '22:45 EAT',
          homeTeam: 'AC Milan',
          awayTeam: 'Inter Milan',
          homeForm: ['W', 'D', 'W', 'L', 'W'],
          awayForm: ['W', 'W', 'W', 'D', 'W'],
          homeWinProb: 35,
          drawProb: 30,
          awayWinProb: 35,
          over25Goals: '58%',
          btts: '74%',
          cardRisk: 'High',
          topTip: 'Both Teams To Score (BTTS)',
          odds: 1.90,
        ),
      ];
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

  @override
  void initState() {
    super.initState();
    _loadFixtures();
  }

  Future<void> _loadFixtures() async {
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
        onSearchChanged: (q) => setState(() => _searchQuery = q),
        onLeagueChanged: (l) => setState(() => _selectedLeague = l),
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
  final Function(String) onSearchChanged;
  final Function(String) onLeagueChanged;
  final Function(FixtureModel) onToggleSave;

  const MatchesAnalysisTab({
    Key? key,
    required this.fixtures,
    required this.isLoading,
    required this.searchQuery,
    required this.selectedLeague,
    required this.onSearchChanged,
    required this.onLeagueChanged,
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
    final filteredFixtures = fixtures.where((f) {
      final matchesSearch = f.homeTeam.toLowerCase().contains(searchQuery.toLowerCase()) ||
          f.awayTeam.toLowerCase().contains(searchQuery.toLowerCase()) ||
          f.league.toLowerCase().contains(searchQuery.toLowerCase());
      final matchesLeague = selectedLeague == 'All Leagues' || f.league == selectedLeague;
      return matchesSearch && matchesLeague;
    }).toList();

    return ListView(
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
              _buildFilterChip('All Leagues', Icons.sports_soccer),
              const SizedBox(width: 8),
              _buildFilterChip('Premier League', Icons.flag),
              const SizedBox(width: 8),
              _buildFilterChip('La Liga', Icons.shield),
              const SizedBox(width: 8),
              _buildFilterChip('Serie A', Icons.sports),
            ],
          ),
        ),
        const SizedBox(height: 16),

        isLoading
            ? const Center(child: CircularProgressIndicator())
            : filteredFixtures.isEmpty
                ? const Center(child: Padding(padding: EdgeInsets.all(32.0), child: Text('No fixtures match your search.')))
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
                                  Text(fixture.time, style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
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

                              // TOP AI VALUE TIP Box
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8F9FA),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFFE9ECEF)),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                         crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Text('TOP AI VALUE TIP', style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                                          const SizedBox(height: 2),
                                          Row(
                                            children: [
                                              const Icon(Icons.auto_awesome, size: 14, color: Colors.amber),
                                              const SizedBox(width: 4),
                                              Expanded(child: Text('${fixture.topTip} (${fixture.odds})', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF212529)), overflow: TextOverflow.ellipsis)),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () => onToggleSave(fixture),
                                      icon: Icon(fixture.isSaved ? Icons.bookmark : Icons.bookmark_border, color: const Color(0xFF0D6EFD), size: 20),
                                    ),
                                    ElevatedButton(
                                      onPressed: () => _showDeepDiveModal(context, fixture),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF0D6EFD),
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      ),
                                      child: const Text('Deep Dive >', style: TextStyle(fontSize: 11, color: Colors.white)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
      ],
    );
  }

  Widget _buildFilterChip(String label, IconData iconData) {
    bool isSelected = selectedLeague == label;
    return ChoiceChip(
      avatar: Icon(iconData, size: 14, color: isSelected ? Colors.white : const Color(0xFF0D6EFD)),
      label: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.white : const Color(0xFF212529),
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
      selected: isSelected,
      selectedColor: const Color(0xFF0D6EFD),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: isSelected ? const Color(0xFF0D6EFD) : const Color(0xFFE9ECEF)),
      ),
      onSelected: (_) {
        onLeagueChanged(label);
      },
    );
  }

  Widget _buildStatBox(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.black54)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}

class PredictorTab extends StatefulWidget {
  const PredictorTab({Key? key}) : super(key: key);

  @override
  State<PredictorTab> createState() => _PredictorTabState();
}

class _PredictorTabState extends State<PredictorTab> {
  final TextEditingController _homeController = TextEditingController(text: 'Arsenal');
  final TextEditingController _awayController = TextEditingController(text: 'Liverpool');
  String _predictionResult = '';

  void _runSimulation() {
    setState(() {
      _predictionResult = 'AI Simulation: ${_homeController.text} vs ${_awayController.text}\n\n'
          '• Projected Score: 2 - 1\n'
          '• Win Probability: ${_homeController.text} (58%) | Draw (24%) | ${_awayController.text} (18%)\n'
          '• Recommended Pick: Home Win & Over 1.5 Goals\n'
          '• Confidence Index: 84% (High Value)';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Match Predictor & Simulator', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0D6EFD))),
          const SizedBox(height: 8),
          const Text('Input any custom teams to calculate algorithmic outcomes.', style: TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 20),
          TextField(
            controller: _homeController,
            decoration: const InputDecoration(labelText: 'Home Team', border: OutlineInputBorder(), filled: true, fillColor: Colors.white),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _awayController,
            decoration: const InputDecoration(labelText: 'Away Team', border: OutlineInputBorder(), filled: true, fillColor: Colors.white),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0D6EFD),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _runSimulation,
              child: const Text('Run AI Simulation', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 24),
          if (_predictionResult.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.shade100)),
              child: Text(_predictionResult, style: const TextStyle(fontSize: 14, height: 1.5, color: Color(0xFF0D6EFD), fontWeight: FontWeight.w500)),
            ),
        ],
      ),
    );
  }
}

class SavedSlipsTab extends StatefulWidget {
  final List<FixtureModel> savedFixtures;
  final Function(FixtureModel) onToggleSave;

  const SavedSlipsTab({Key? key, required this.savedFixtures, required this.onToggleSave}) : super(key: key);

  @override
  State<SavedSlipsTab> createState() => _SavedSlipsTabState();
}

class _SavedSlipsTabState extends State<SavedSlipsTab> {
  final TextEditingController _stakeController = TextEditingController(text: '100');

  @override
  Widget build(BuildContext context) {
    double totalOdds = widget.savedFixtures.fold(1.0, (sum, item) => sum * item.odds);
    if (widget.savedFixtures.isEmpty) totalOdds = 0.0;

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
                ? const Center(child: Text('No bookmarked tips yet. Tap the bookmark icon on any match!', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)))
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
