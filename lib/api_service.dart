import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'fixture_model.dart';

class ApiService {
  static const String apiUrl =
      'https://my-betting-companion.onrender.com/api/fixtures';

  /// Fetches fixtures from the backend with built-in network fallback.
  static Future<List<FixtureModel>> fetchFixtures() async {
    debugPrint('Fetching fixtures from: $apiUrl');

    try {
      final response = await http
          .get(Uri.parse(apiUrl))
          .timeout(const Duration(seconds: 45));

      debugPrint('Status Code: ${response.statusCode}');

      if (response.statusCode != 200) {
        throw Exception('Server returned ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! List) {
        throw Exception('Expected JSON array but got ${decoded.runtimeType}');
      }

      return decoded
          .map((json) => FixtureModel.fromJson(json as Map<String, dynamic>))
          .toList();
          
    } on SocketException catch (e) {
      debugPrint('DNS/Socket Exception caught: $e. Returning offline fallback fixtures.');
      return _getFallbackFixtures();
    } catch (e) {
      debugPrint('Error fetching fixtures: $e');
      rethrow;
    }
  }

  /// Offline fallback sample data including finished Prolific matches for the Results table
  static List<FixtureModel> _getFallbackFixtures() {
    return [
      // Upcoming Standard Match (Analyzer tab)
      FixtureModel.fromJson({
        "league": "Campeonato Brasileiro Série A",
        "time": "Sun 15 Nov, 00:30 EAT",
        "homeTeam": "Mirassol FC",
        "awayTeam": "Chapecoense AF",
        "homeForm": ["W", "D", "W", "W", "L"],
        "awayForm": ["L", "W", "D", "W", "L"],
        "homeWinProb": 50,
        "drawProb": 28,
        "awayWinProb": 22,
        "over25Goals": "60%",
        "btts": "55%",
        "cardRisk": "Medium",
        "topTip": "Mirassol FC Win or Draw",
        "odds": 1.75,
        "isLive": false,
        "isFinished": false,
        "actualScore": "Pending",
        "predictionCorrect": null,
        "isProlific": false,
        "isSample": true,
        "isEstimate": true
      }),
      // Upcoming Prolific Match (Analyzer tab)
      FixtureModel.fromJson({
        "league": "UEFA Nations League",
        "time": "Today, 20:00 EAT",
        "homeTeam": "Turkiye",
        "awayTeam": "Belgium",
        "homeForm": ["W", "W", "D", "L", "W"],
        "awayForm": ["W", "D", "W", "W", "W"],
        "homeWinProb": 35,
        "drawProb": 30,
        "awayWinProb": 35,
        "over25Goals": "52%",
        "btts": "60%",
        "cardRisk": "High",
        "topTip": "Both Teams to Score",
        "odds": 1.85,
        "isLive": false,
        "isFinished": false,
        "actualScore": "Pending",
        "predictionCorrect": null,
        "isProlific": true,
        "isSample": true,
        "isEstimate": true
      }),
      // Finished Prolific Match 1 (Results & Accuracy table - WON)
      FixtureModel.fromJson({
        "league": "Primera Division",
        "time": "Sun 8 Nov, 20:00 EAT",
        "homeTeam": "Club Atlético de Madrid",
        "awayTeam": "FC Barcelona",
        "homeForm": ["W", "D", "W", "W", "L"],
        "awayForm": ["W", "W", "W", "W", "W"],
        "homeWinProb": 30,
        "drawProb": 25,
        "awayWinProb": 45,
        "over25Goals": "75%",
        "btts": "65%",
        "cardRisk": "High",
        "topTip": "FC Barcelona Win or Draw",
        "odds": 1.73,
        "isLive": false,
        "isFinished": true,
        "actualScore": "1-2",
        "predictionCorrect": true,
        "isProlific": true,
        "isSample": true,
        "isEstimate": true
      }),
      // Finished Prolific Match 2 (Results & Accuracy table - LOST)
      FixtureModel.fromJson({
        "league": "Serie A",
        "time": "Sun 8 Nov, 22:45 EAT",
        "homeTeam": "ACF Fiorentina",
        "awayTeam": "Juventus FC",
        "homeForm": ["W", "D", "W", "W", "L"],
        "awayForm": ["W", "D", "W", "W", "W"],
        "homeWinProb": 35,
        "drawProb": 30,
        "awayWinProb": 35,
        "over25Goals": "55%",
        "btts": "50%",
        "cardRisk": "Medium",
        "topTip": "ACF Fiorentina Win or Draw",
        "odds": 1.95,
        "isLive": false,
        "isFinished": true,
        "actualScore": "0-2",
        "predictionCorrect": false,
        "isProlific": true,
        "isSample": true,
        "isEstimate": true
      })
    ];
  }
}
