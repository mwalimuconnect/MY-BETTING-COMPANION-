import 'dart:convert';
import 'package:http/http.dart' as http;
import 'fixture_model.dart';

class ApiService {
  // Live Render backend endpoint
  static const String apiUrl = 'https://my-betting-companion.onrender.com/api/fixtures';

  static Future<List<FixtureModel>> fetchFixtures() async {
    try {
      final response = await http.get(Uri.parse(apiUrl));
      if (response.statusCode == 200) {
        List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => FixtureModel.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load fixtures');
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
