import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_service.dart';
import 'app_settings.dart';
import 'notification_service.dart';
import 'slip_generator.dart';

class H2HEntry {
  final String date;
  final String home;
  final String away;
  final String score;

  const H2HEntry({
    required this.date,
    required this.home,
    required this.away,
    required this.score,
  });

  factory H2HEntry.fromJson(Map<String, dynamic> json) {
    return H2HEntry(
      date: json['date']?.toString() ?? '',
      home: json['home']?.toString() ?? '',
      away: json['away']?.toString() ?? '',
      score: json['score']?.toString() ?? '',
    );
  }
}

class FixtureModel {
  final String? key;
  final String homeTeam;
  final String awayTeam;
  final DateTime? kickoff;
  final DateTime? time; // Alias for kickoff required by UI
  final bool isLive;
  final bool isFinished;
  final double odds; // 0 = no real bookmaker odds available
  final String prediction; // same as topTip
  final String league;

  // UI properties
  final bool hasPrediction;
  final String topTip; // empty when the model has no clear tip
  final double tipProb; // 0 when there is no tip
  final double homeWinProb;
  final double drawProb;
  final double awayWinProb;

  // Extra data from the server (all optional)
  final String utcDate; // ISO kickoff time (UTC)
  final String competitionCode;
  final String dateLabel; // e.g. "Thu 19 Nov"
  final String kickoffTime; // e.g. "01:30 EAT"
  final String actualScore; // e.g. "2-1", or "Pending"
  final List<String> homeForm;
  final List<String> awayForm;
  final List<H2HEntry> h2h;
  final String over25Goals;
  final String btts;
  final String cardRisk;
  final bool isProlific;
  final bool isSample;
  final bool isEstimate;
  final bool? predictionCorrect;
  bool isSaved;

  FixtureModel({
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
    this.utcDate = '',
    this.competitionCode = '',
    this.dateLabel = '',
    this.kickoffTime = '',
    this.actualScore = 'Pending',
    this.homeForm = const [],
    this.awayForm = const [],
    this.h2h = const [],
    this.over25Goals = 'N/A',
    this.btts = 'N/A',
    this.cardRisk = 'N/A',
    this.isProlific = false,
    this.isSample = false,
    this.isEstimate = false,
    this.predictionCorrect,
    this.isSaved = false,
  });

  /// Text such as "Thu 19 Nov, 01:30 EAT" (empty if the server sent no date).
  String get timeLabel {
    if (dateLabel.isEmpty) return kickoffTime;
    if (kickoffTime.isEmpty) return dateLabel;
    return '$dateLabel, $kickoffTime';
  }

  /// Tip confidence as a whole number, or null when there is no tip.
  int? get tipProbInt => tipProb > 0 ? tipProb.round() : null;

  static double _d(dynamic v, double fallback) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    return fallback;
  }

  static List<String> _list(dynamic v) {
    if (v is List) return v.map((e) => e.toString()).toList();
    return <String>[];
  }

  static List<H2HEntry> _h2h(dynamic v) {
    if (v is! List) return const [];
    final out = <H2HEntry>[];
    for (final e in v) {
      if (e is Map) out.add(H2HEntry.fromJson(Map<String, dynamic>.from(e)));
    }
    return out;
  }

  factory FixtureModel.fromJson(Map<String, dynamic> j) {
    final String utc = j['utcDate']?.toString() ?? '';

    DateTime? parsedTime = DateTime.tryParse(utc);
    parsedTime ??= j['kickoff'] != null ? DateTime.tryParse(j['kickoff'].toString()) : null;

    // No invented predictions: if the server has no tip, these stay empty/zero.
    final String tip = j['topTip']?.toString() ?? j['prediction']?.toString() ?? '';
    final double home = _d(j['homeWinProb'], 0);
    final double draw = _d(j['drawProb'], 0);
    final double away = _d(j['awayWinProb'], 0);

    return FixtureModel(
      key: j['key']?.toString() ?? j['id']?.toString(),
      homeTeam: j['homeTeam']?.toString() ?? 'Home',
      awayTeam: j['awayTeam']?.toString() ?? 'Away',
      kickoff: parsedTime,
      time: parsedTime,
      isLive: j['isLive'] == true,
      isFinished: j['isFinished'] == true,
      odds: _d(j['odds'], 0),
      prediction: tip,
      league: j['league']?.toString() ?? 'General League',
      hasPrediction: (home + draw + away) > 0,
      topTip: tip,
      tipProb: _d(j['tipProb'], 0),
      homeWinProb: home,
      drawProb: draw,
      awayWinProb: away,
      utcDate: utc,
      competitionCode: j['competitionCode']?.toString() ?? '',
      dateLabel: j['dateLabel']?.toString() ?? '',
      kickoffTime: j['kickoffTime']?.toString() ?? '',
      actualScore: j['actualScore']?.toString() ?? 'Pending',
      homeForm: _list(j['homeForm']),
      awayForm: _list(j['awayForm']),
      h2h: _h2h(j['h2h']),
      over25Goals: j['over25Goals']?.toString() ?? 'N/A',
      btts: j['btts']?.toString() ?? 'N/A',
      cardRisk: j['cardRisk']?.toString() ?? 'N/A',
      isProlific: j['isProlific'] == true,
      isSample: j['isSample'] == true,
      isEstimate: j['isEstimate'] == true,
      predictionCorrect:
          j['predictionCorrect'] is bool ? j['predictionCorrect'] as bool : null,
    );
  }
}

class FixtureApi {
  static String _lastSlipSignature = '';

  static Future<List<FixtureModel>> fetchFixtures() async {
    try {
      final res = await http
          .get(Uri.parse('$kApiBase/api/fixtures'))
          .timeout(const Duration(seconds: 45));

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

  /// Tells the user about a suggested slip, but only if notifications are on
  /// and only once per distinct slip (not on every refresh).
  static void _processAutoSlipCheck(List<FixtureModel> fixtures) {
    try {
      if (!AppSettings.notificationsOn.value) return;

      final generatedSlip = SlipGenerator.generateTargetSlip(fixtures);
      if (generatedSlip == null) return;

      final signature =
          generatedSlip.selections.map((s) => s['match'].toString()).join('|');
      if (signature == _lastSlipSignature) return;
      _lastSlipSignature = signature;

      NotificationService.showNow(
        generatedSlip.title,
        'Suggested slip: ${generatedSlip.totalOdds}x (model odds). Open the app to view selections.',
      );
    } catch (e) {
      debugPrint('Auto slip generation error: $e');
    }
  }
}
