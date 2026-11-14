import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'fixture_model.dart';
import 'prediction_log.dart';

/// One saved tip. status: pending, won, lost, void, none (saved without a tip).
class SlipLeg {
  final String key;
  final String home;
  final String away;
  final String league;
  final String tip;
  final String kickoff; // label shown in the list
  final String utcDate;
  final int savedAt;
  String status;
  String score;

  SlipLeg({
    required this.key,
    required this.home,
    required this.away,
    required this.league,
    required this.tip,
    required this.kickoff,
    required this.utcDate,
    required this.savedAt,
    this.status = 'pending',
    this.score = '',
  });

  Map<String, dynamic> toJson() => {
        'key': key,
        'home': home,
        'away': away,
        'league': league,
        'tip': tip,
        'kickoff': kickoff,
        'utcDate': utcDate,
        'savedAt': savedAt,
        'status': status,
        'score': score,
      };

  factory SlipLeg.fromJson(Map<String, dynamic> j) {
    return SlipLeg(
      key: j['key']?.toString() ?? '',
      home: j['home']?.toString() ?? '',
      away: j['away']?.toString() ?? '',
      league: j['league']?.toString() ?? '',
      tip: j['tip']?.toString() ?? '',
      kickoff: j['kickoff']?.toString() ?? '',
      utcDate: j['utcDate']?.toString() ?? '',
      savedAt: j['savedAt'] is num ? (j['savedAt'] as num).toInt() : 0,
      status: j['status']?.toString() ?? 'pending',
      score: j['score']?.toString() ?? '',
    );
  }
}

class SlipSummary {
  final int won;
  final int lost;
  final int pending;
  final int voided;
  final int noTip;

  /// Accumulator result: Lost if any leg lost, Pending while legs are open,
  /// Won when every judged leg won, Empty when nothing can be judged.
  final String status;

  const SlipSummary({
    required this.won,
    required this.lost,
    required this.pending,
    required this.voided,
    required this.noTip,
    required this.status,
  });
}

class SlipStore {
  static const String _prefsKey = 'saved_slips_v1';

  static Future<List<SlipLeg>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final out = <SlipLeg>[];
      for (final e in decoded) {
        if (e is Map) out.add(SlipLeg.fromJson(Map<String, dynamic>.from(e)));
      }
      return out;
    } catch (e) {
      debugPrint('Could not load saved slips: $e');
      return [];
    }
  }

  static Future<void> _save(List<SlipLeg> legs) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _prefsKey, jsonEncode(legs.map((l) => l.toJson()).toList()));
    } catch (e) {
      debugPrint('Could not save slips: $e');
    }
  }

  /// Adds the match to saved slips, or removes it if already saved.
  /// Returns true when the match is now saved.
  static Future<bool> toggle(FixtureModel f) async {
    final key = f.key;
    if (key == null) return false;
    final legs = await load();
    final index = legs.indexWhere((l) => l.key == key);
    if (index >= 0) {
      legs.removeAt(index);
      await _save(legs);
      return false;
    }
    legs.add(SlipLeg(
      key: key,
      home: f.homeTeam,
      away: f.awayTeam,
      league: f.league,
      tip: f.topTip,
      kickoff: f.time,
      utcDate: f.utcDate,
      savedAt: DateTime.now().millisecondsSinceEpoch,
      status: f.topTip.isEmpty ? 'none' : 'pending',
    ));
    await _save(legs);
    return true;
  }

  static Future<void> remove(String key) async {
    final legs = await load();
    legs.removeWhere((l) => l.key == key);
    await _save(legs);
  }

  /// Removes every leg that has a final result (won, lost or void).
  static Future<void> clearSettled() async {
    final legs = await load();
    legs.removeWhere(
        (l) => l.status == 'won' || l.status == 'lost' || l.status == 'void');
    await _save(legs);
  }

  /// Settles pending legs using finished matches. Returns the legs that were
  /// newly won or lost (so the app can tell the user).
  static Future<List<SlipLeg>> settle(List<FixtureModel> fixtures) async {
    final legs = await load();
    final byKey = <String, FixtureModel>{};
    for (final f in fixtures) {
      final k = f.key;
      if (k != null) byKey[k] = f;
    }

    final now = DateTime.now().toUtc();
    final newly = <SlipLeg>[];
    var changed = false;

    for (final leg in legs) {
      if (leg.status != 'pending') continue;
      final f = byKey[leg.key];

      if (f != null && f.isFinished) {
        final result = evaluateTip(leg.tip, leg.home, leg.away, f.actualScore);
        leg.score = f.actualScore;
        leg.status = result == null ? 'void' : (result ? 'won' : 'lost');
        if (result != null) newly.add(leg);
        changed = true;
      } else {
        final ko = DateTime.tryParse(leg.utcDate);
        if (ko != null && now.difference(ko).inDays > 14) {
          leg.status = 'void'; // result never arrived
          changed = true;
        }
      }
    }

    if (changed) await _save(legs);
    return newly;
  }

  static SlipSummary summary(List<SlipLeg> legs) {
    var won = 0, lost = 0, pending = 0, voided = 0, noTip = 0;
    for (final l in legs) {
      switch (l.status) {
        case 'won':
          won++;
          break;
        case 'lost':
          lost++;
          break;
        case 'pending':
          pending++;
          break;
        case 'void':
          voided++;
          break;
        default:
          noTip++;
      }
    }
    String status;
    if (lost > 0) {
      status = 'Lost';
    } else if (pending > 0) {
      status = 'Pending';
    } else if (won > 0) {
      status = 'Won';
    } else {
      status = 'Empty';
    }
    return SlipSummary(
      won: won,
      lost: lost,
      pending: pending,
      voided: voided,
      noTip: noTip,
      status: status,
    );
  }
}
