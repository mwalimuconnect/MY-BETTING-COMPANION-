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

class FixtureModel {
  final String homeTeam;
  final String awayTeam;
  final String league;
  final String homeForm;
  final String awayForm;
  final int homeWinProbability;
  final int drawProbability;
  final int awayWinProbability;
  final String topTip;

  FixtureModel({
    required this.homeTeam,
    required this.awayTeam,
    required this.league,
    required this.homeForm,
    required this.awayForm,
    required this.homeWinProbability,
    required this.drawProbability,
    required this.awayWinProbability,
    required this.topTip,
  });

  factory FixtureModel.fromJson(Map<String, dynamic> json) {
    return FixtureModel(
      homeTeam: json['home_team'] ?? 'Home',
      awayTeam: json['away_team'] ?? 'Away',
      league: json['league'] ?? 'League',
      homeForm: json['home_form'] ?? 'W-W-D',
      awayForm: json['away_form'] ?? 'W-L-D',
      homeWinProbability: json['home_win_prob'] ?? 50,
      drawProbability: json['draw_prob'] ?? 25,
      awayWinProbability: json['away_win_prob'] ?? 25,
      topTip: json['top_tip'] ?? 'Over 2.5 Goals',
    );
  }
}


class DashboardScreen extends StatefulWidget {

  const DashboardScreen({Key? key}) : super(key: key);

  @override

  State<DashboardScreen> createState() => _DashboardScreenState();

}

class _DashboardScreenState extends State<DashboardScreen> {

  int _selectedIndex = 0;

  String _selectedLeague = 'All Leagues';

  @override

  Widget build(BuildContext context) {

    final List<Widget> pages = [

      MatchesAnalysisTab(

        selectedLeague: _selectedLeague,

        onLeagueChanged: (l) {

          setState(() => _selectedLeague = l);

        },

      ),

      const Center(

        child: Text('Match Predictor & Odds Calculator', style: TextStyle(fontWeight: FontWeight.bold)),

      ),

      const Center(

        child: Text('Saved Bets & Prediction History', style: TextStyle(fontWeight: FontWeight.bold)),

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

class ApiService {
  // Live Render backend endpoint
  static const String apiUrl = 'https://my-betting-companion.onrender.com/api/fixtures';

  static Future<List<FixtureModel>> fetchFixtures() async {
    try {
      final response = await http.get(Uri.parse(apiUrl));
      if (response.statusCode == 200) {
        List<dynamic> body = jsonDecode(response.body);
        return body.map((dynamic item) => FixtureModel.fromJson(item)).toList();
      } else {
        throw Exception('Failed to load fixtures: ${response.statusCode}');
      }
    } catch (e) {
      // Fallback sample match for testing offline/network delays
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
        ),
      ];
    }
  }
}

class MatchesAnalysisTab extends StatelessWidget {
  final String selectedLeague;
  final Function(String) onLeagueChanged;

  const MatchesAnalysisTab({
    Key? key,
    required this.selectedLeague,
    required this.onLeagueChanged,
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

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        // Search Bar
        TextField(
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
                child: const Row(
                  children: [
                    Icon(Icons.flash_on, color: Color(0xFF0D6EFD), size: 18),
                    SizedBox(width: 6),
                    Text('Analyzed: ', style: TextStyle(fontSize: 12, color: Colors.black87)),
                    Text('6 Fixtures', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0D6EFD))),
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
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Main Fixture Match Card
        Card(
          color: Colors.white,
          elevation: 2,
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
                      children: const [
                        Icon(Icons.sports_soccer, size: 14, color: Color(0xFF0D6EFD)),
                        SizedBox(width: 4),
                        Text(
                          'Premier League',
                          style: TextStyle(color: Color(0xFF0D6EFD), fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const Text('21:00 EAT', style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 16),

                // Teams & Form Badges
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        const Text('Chelsea', style: TextStyle(color: Color(0xFF212529), fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            _buildFormBadge('W', Colors.green),
                            _buildFormBadge('W', Colors.green),
                            _buildFormBadge('D', Colors.amber),
                            _buildFormBadge('W', Colors.green),
                            _buildFormBadge('L', Colors.red),
                          ],
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
                        const Text('Aston Villa', style: TextStyle(color: Color(0xFF212529), fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            _buildFormBadge('W', Colors.green),
                            _buildFormBadge('L', Colors.red),
                            _buildFormBadge('D', Colors.amber),
                            _buildFormBadge('W', Colors.green),
                            _buildFormBadge('W', Colors.green),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 3-Color Probability Bar
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: const [
                    Text('Home: 54%', style: TextStyle(fontSize: 11, color: Color(0xFF0D6EFD), fontWeight: FontWeight.bold)),
                    Text('Draw: 26%', style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold)),
                    Text('Away: 20%', style: TextStyle(fontSize: 11, color: Colors.pink, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    height: 8,
                    child: Row(
                      children: [
                        Expanded(flex: 54, child: Container(color: const Color(0xFF0D6EFD))),
                        Expanded(flex: 26, child: Container(color: Colors.grey[400])),
                        Expanded(flex: 20, child: Container(color: Colors.pink)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Probability Stat Tiles
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildStatBox('Over 2.5 Goals', '72%', Colors.green[700]!),
                    _buildStatBox('BTTS', '68%', Colors.orange[800]!),
                    _buildStatBox('Card Risk', 'Medium', Colors.amber[800]!),
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
                              children: const [
                                Icon(Icons.auto_awesome, size: 14, color: Colors.amber),
                                SizedBox(width: 4),
                                Text('Over 2.5 Goals & BTTS - Yes', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF212529))),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {},
                        icon: const Icon(Icons.bookmark_border, color: Color(0xFF0D6EFD), size: 20),
                      ),
                      ElevatedButton(
                        onPressed: () {},
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
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, IconData iconData) {
    bool isSelected = selectedLeague == label || (selectedLeague == 'All Leagues' && label.contains('All'));
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
  

                    
          

        

        
                  
                                              
      

      
