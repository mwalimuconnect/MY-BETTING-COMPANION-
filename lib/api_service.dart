import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'fixture_model.dart';

/// Base address of your Render server.
const String kApiBase = 'https://my-betting-companion.onrender.com';

class ApiService {
  static const String apiUrl = '$kApiBase/api/fixtures';

  /// Fetches fixtures from the backend.
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
      debugPrint('Socket error: $e');
      throw Exception(
          'Cannot reach server (${e.message}). Check internet, VPN or private DNS.');
    } on TimeoutException {
      debugPrint('Request timed out');
      throw Exception('Server took too long to respond. Tap Retry.');
    } on FormatException catch (e) {
      debugPrint('Bad JSON: $e');
      throw Exception('Server sent invalid data: ${e.message}');
    } catch (e) {
      debugPrint('Error fetching fixtures: $e');
      rethrow;
    }
  }

  /// Fetches real-time team insights, injuries, and squad news from your Render backend
  static Future> fetchTeamInsights(String teamName) async {
    final url = '$kApiBase/api/team-insights?team=${Uri.encodeComponent(teamName)}';
    debugPrint('Fetching team insights from: $url');

    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 25));

      if (response.statusCode != 200) {
        throw Exception('Server returned ${response.statusCode} for team insights');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      throw Exception('Invalid data format received from server');
    } on SocketException catch (e) {
      debugPrint('Socket error: $e');
      throw Exception('Cannot reach server for team insights: ${e.message}');
    } on TimeoutException {
      debugPrint('Team insights request timed out');
      throw Exception('Server took too long to respond with team insights.');
    } catch (e) {
      debugPrint('Error fetching team insights: $e');
      rethrow;
    }
  }
}
