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

      return decoded
          .cast<Map<String, dynamic>>()
          .map((json) => FixtureModel.fromJson(json))
          .toList();
    } catch (e, stackTrace) {
      debugPrint('API ERROR: $e');
      debugPrintStack(stackTrace: stackTrace);

      // Temporary demo fixture
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
        ),
      ];
    }
  }
}
