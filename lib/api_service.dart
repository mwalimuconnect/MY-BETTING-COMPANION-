import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'fixture_model.dart';

class ApiService {
  static const String apiUrl =
      'https://my-betting-companion.onrender.com/api/fixtures';

  /// Fetches fixtures from the backend.
  /// Throws on any failure so the UI (main.dart) can retry and show
  /// the "Couldn't load fixtures" screen instead of a fake fixture.
  static Future<List<FixtureModel>> fetchFixtures() async {
    debugPrint('Fetching fixtures from: $apiUrl');

    // Long timeout: Render's free tier can take 30-60s to wake up.
    final response = await http
        .get(Uri.parse(apiUrl))
        .timeout(const Duration(seconds: 60));

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
  }
}
