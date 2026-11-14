import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart';
import 'slip_generator.dart';
import 'notification_service.dart';

class FixtureModel {
  final String? key;
  final String homeTeam;
  final String awayTeam;
  final DateTime? kickoff;
  final DateTime? time; // Alias for kickoff required by UI
  final bool isLive;
  final bool isFinished;
  final double odds;
  final String prediction;
  final String league;
  
  // UI Properties and Getters
  final bool hasPrediction;
  final String topTip;
  final double tipProb;
  final double homeWinProb;
  final double drawProb;
  final double awayWinProb;

  const FixtureModel({
    required this.key,
    required this.homeTeam,
    required this.awayTeam,
    required this.kickoff,
    required this.time,
    required this.isLive,
    required this.isFinished,
    required this.odds,
    required this.prediction,
    required this.league,
    required this.hasPrediction,
    required this.topTip,
    required this.tipProb,
    required this.homeWinProb,
    required this.drawProb,
    required this.awayWinProb,
  });

  factory FixtureModel.fromJson(Map<String, dynamic> j) {
    DateTime? parsedTime;
    try {
      if (j['kickoff'] != null) {
        parsedTime = DateTime.parse(j['kickoff'].toString());
      } else if (j['time'] != null) {
        parsedTime = DateTime.parse(j['time'].toString());
      }
    } catch (_) {}

    String tip = j['topTip']?.toString() ?? 
                 j['toptip']?.toString() ?? 
                 j['prediction']?.toString() ?? '1X';

    return FixtureModel(
      key: j['key']?.toString() ?? j['id']?.toString(),
      homeTeam: j['homeTeam']?.toString() ?? 'Home',
      awayTeam: j['awayTeam']?.toString() ?? 'Away',
      kickoff: parsedTime,
      time: parsedTime,
      isLive: j['isLive'] == true,
      isFinished: j['isFinished'] == true,
      odds: j['odds'] is num ? (j['odds'] as num).toDouble() : 1.65,
      prediction: j['prediction']?.toString() ?? '1X',
      league: j['league']?.toString() ?? 'General League',
      hasPrediction: j['hasPrediction'] == true || j['prediction'] != null,
      topTip: tip,
      tipProb: j['tipProb'] is num ? (j['tipProb'] as num).toDouble() : 75.0,
      homeWinProb: j['homeWinProb'] is num ? (j['homeWinProb'] as num).toDouble() : 45.0,
      drawProb: j['drawProb'] is num ? (j['drawProb'] as num).toDouble() : 25.0,
      awayWinProb: j['awayWinProb'] is num ? (j['awayWinProb'] as num).toDouble() : 30.0,
    );
  }
}

class FixtureApi {
  static Future<List<FixtureModel>> fetchFixtures() async {
    try {
      final res = await http
          .get(Uri.parse('$kApiBase/api/fixtures'))
          .timeout(const Duration(seconds: 30));

      if (res.statusCode != 200) {
        throw Exception('Failed to load fixtures: ${res.statusCode}');
      }

      final decoded = jsonDecode(res.body);
      List list = [];
      if (decoded is List) {
        list = decoded;
      } else if (decoded is Map && decoded['fixtures'] is List) {
        list = decoded['fixtures'];
      }

      final fixtures = list
          .map((e) => FixtureModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      _processAutoSlipCheck(fixtures);

      return fixtures;
    } on SocketException {
      throw Exception('No internet connection.');
    } on TimeoutException {
      throw Exception('Request timed out.');
    } catch (e) {
      throw Exception('Error loading fixtures: $e');
    }
  }

  static void _processAutoSlipCheck(List<FixtureModel> fixtures) {
    try {
      final generatedSlip = SlipGenerator.generateTargetSlip(fixtures);

      if (generatedSlip != null) {
        NotificationService.showNow(
          generatedSlip.title,
          'Target odds reached (${generatedSlip.totalOdds}x)! Tap to view selections.',
        );
      }
    } catch (e) {
      debugPrint('Auto slip generation error: $e');
    }
  }
}
