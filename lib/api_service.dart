import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'fixture_model.dart';

class ApiService {
  static const String apiUrl =
      'https://my-betting-companion.onrender.com/api/fixtures';

  static Future<List<FixtureModel>> fetchFixtures() async {
    try {
      debugPrint('Fetching fixtures from: $apiUrl');

      final response = await http
          .get(Uri.parse(apiUrl))
          .timeout(const Duration(seconds: 40));

      debugPrint('Status Code: ${response.statusCode}');

      if (response.statusCode != 200) {
        throw Exception(
          'Server returned ${response.statusCode}',
        );
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! List) {
        throw Exception(
          'Expected JSON array but got ${decoded.runtimeType}',
        );
      }

      final List<dynamic> decodedList = decoded;

      return decodedList
          .map((json) => FixtureModel.fromJson(json as Map<String, dynamic>))
          .toList();

    } catch (e, stackTrace) {
      debugPrint('API Error: $e');
      debugPrintStack(stackTrace: stackTrace);

      // Temporary demo fixture with all required parameters
      return [
        FixtureModel(
          league: 'API Error',
          time: 'Check Logs',
          homeTeam: 'Connection',
          awayTeam: 'Failed',
          homeForm: ['W', 'W', 'W', 'W', 'W'],
          awayForm: ['L', 'L', 'L', 'L', 'L'],
          homeWinProb: 0,
          drawProb: 0,
          awayWinProb: 0,
          over25Goals: '0%',
          btts: '0%',
          cardRisk: 'N/A',
          topTip: e.toString(),
          odds: 0.0,
          isLive: false,
          isFinished: false,
          actualScore: 'Pending',
          predictionCorrect: null,
          isProlific: false,
          isSample: true,
          isEstimate: true,
        ),
      ];
    }
  }
}
