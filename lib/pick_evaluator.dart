//=====================================================
// pick_evaluator.dart
// One place that decides whether a pick won, used by
// slip_generator.dart (slips) and prediction_log.dart (tips).
//=====================================================

/// Parses "2-1", "2 - 1", "2:1" or "2-1 FT" into [home, away].
List<int>? parseScore(String score) {
  final cleaned = score
      .replaceAll(RegExp(r'\s*ft\s*', caseSensitive: false), '')
      .trim();
  final parts = cleaned.split(RegExp(r'\s*[-:]\s*'));
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0].trim());
  final a = int.tryParse(parts[1].trim());
  if (h == null || a == null) return null;
  return [h, a];
}

/// Which team does [pick] refer to? 1 = home, 2 = away, 0 = unknown/ambiguous.
///
/// Exact full-name matches win first. Fuzzy word matching is only used when
/// it points at exactly one team, so "Manchester City win" is never credited
/// to "Manchester United".
int _teamSide(String pick, String home, String away) {
  bool exact(String name) =>
      name.isNotEmpty &&
      (pick == name || pick == '$name win' || pick.startsWith('$name '));

  if (exact(home) && !exact(away)) return 1;
  if (exact(away) && !exact(home)) return 2;

  bool fuzzy(String name) {
    if (name.isEmpty) return false;
    return name
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 4)
        .any((w) => RegExp('\\b${RegExp.escape(w)}\\b').hasMatch(pick));
  }

  final bool h = fuzzy(home);
  final bool a = fuzzy(away);
  if (h && !a) return 1;
  if (a && !h) return 2;
  return 0;
}

/// Goal lines supported, mapped to the minimum total goals for "over".
const Map<String, int> _goalLines = {'1.5': 2, '2.5': 3, '3.5': 4};

/// Returns true if the pick won, false if it lost, or null if it cannot be
/// judged from the final score alone (callers decide how to treat void).
bool? evaluatePick({
  required String pick,
  required String home,
  required String away,
  required String score,
}) {
  final goals = parseScore(score);
  if (goals == null) return null;
  final int h = goals[0];
  final int a = goals[1];
  final int total = h + a;

  final String p = pick.trim().toLowerCase();
  if (p.isEmpty) return null;
  final String compact = p.replaceAll(RegExp(r'\s+'), '');
  final String homeName = home.trim().toLowerCase();
  final String awayName = away.trim().toLowerCase();

  // Markets that can't be judged from the final score.
  // (\bcards?\b so teams like "Cardiff" are not mistaken for a card market)
  if (RegExp(r'most goals|\bcards?\b|scorer').hasMatch(p)) return null;

  final int side = _teamSide(p, homeName, awayName);

  // ---- Double Chance (before 1X2 so "(1X)" / "(12)" match properly) ----
  if (p.contains('(12)') ||
      p == '12' ||
      p.startsWith('12 ') ||
      p.contains('home or away') ||
      p.contains('away or home')) {
    return h != a;
  }
  if (p.contains('(1x)') ||
      RegExp(r'^1x\b').hasMatch(p) ||
      p.contains('home or draw') ||
      p.contains('draw or home')) {
    return h >= a;
  }
  if (p.contains('(x2)') ||
      RegExp(r'^x2\b').hasMatch(p) ||
      p.contains('away or draw') ||
      p.contains('draw or away')) {
    return a >= h;
  }
  if ((p.contains('or draw') || p.contains('draw or')) && side != 0) {
    return side == 1 ? h >= a : a >= h;
  }

  // ---- Goals: over/under 1.5, 2.5, 3.5 ----
  for (final entry in _goalLines.entries) {
    final String line = entry.key;
    final int minForOver = entry.value;
    if (compact.contains('over$line') || compact.contains('ov$line')) {
      return total >= minForOver;
    }
    if (compact.contains('under$line') || compact.contains('un$line')) {
      return total < minForOver;
    }
  }

  // ---- BTTS ("no" variants first) ----
  if (p == 'ng' ||
      p.contains('btts no') ||
      p == 'no gg' ||
      p.contains('btts: no') ||
      p.contains('both teams to score: no')) {
    return h == 0 || a == 0;
  }
  if (p == 'gg' ||
      p == 'btts' ||
      p.contains('btts yes') ||
      p.contains('btts: yes') ||
      p.contains('both teams to score: yes')) {
    return h > 0 && a > 0;
  }

  // ---- 1X2 ----
  if (p == 'x' || p == 'draw' || p.startsWith('draw (')) return h == a;
  if (p == '1' || p == 'home' || p.startsWith('home win')) return h > a;
  if (p == '2' || p == 'away' || p.startsWith('away win')) return a > h;
  if (side == 1) return h > a;
  if (side == 2) return a > h;

  // ---- Correct score, e.g. "Correct Score 2-1" ----
  final RegExpMatch? scoreTip =
      RegExp(r'\b(\d+)\s*-\s*(\d+)\b').firstMatch(p);
  if (scoreTip != null) {
    final int? tipH = int.tryParse(scoreTip.group(1)!);
    final int? tipA = int.tryParse(scoreTip.group(2)!);
    if (tipH != null && tipA != null) return h == tipH && a == tipA;
  }

  return null;
}
