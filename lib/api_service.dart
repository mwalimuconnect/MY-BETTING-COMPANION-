import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'fixture_model.dart';

/// Base address of your Render server (shared by fixtures, tables and scorers).
const String kApiBase = 'https://my-betting-companion.onrender.com';

class ApiService {
  static const String apiUrl = '$kApiBase/api/fixtures';

  /// Fetches fixtures from the backend. Throws a readable Exception on failure
  /// so the dashboard can show the error and the Retry button.
  static Future<List<FixtureModel>> fetchFixtures() async {
    debugPrint('Fetching fixtures from: $apiUrl');

    try {
      // 45s covers a sleeping Render free-tier server waking up.
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
}
