// backend/services/statsNormalizer.js

function toNullableNumber(val) {
  if (val === null || val === undefined || val === '') return null;
  if (typeof val === 'number') return Number.isFinite(val) ? val : null;
  const cleaned = String(val).replace('%', '').trim();
  if (!cleaned) return null;
  const num = Number(cleaned);
  return Number.isFinite(num) ? num : null;
}

function extractStatMap(statisticsArray = []) {
  const map = new Map();
  if (!Array.isArray(statisticsArray)) return map;
  for (const item of statisticsArray) {
    if (item && typeof item.type === 'string') {
      map.set(item.type.toLowerCase().trim(), item.value);
    }
  }
  return map;
}

function getStat(statMap, candidateTypes = []) {
  for (const type of candidateTypes) {
    const key = type.toLowerCase().trim();
    if (statMap.has(key)) {
      return toNullableNumber(statMap.get(key));
    }
  }
  return null;
}

function resolveHalfWithMost({ firstHalfTotal, secondHalfTotal }) {
  if (
    typeof firstHalfTotal !== 'number' ||
    !Number.isFinite(firstHalfTotal) ||
    typeof secondHalfTotal !== 'number' ||
    !Number.isFinite(secondHalfTotal)
  ) {
    return null;
  }

  if (firstHalfTotal > secondHalfTotal) {
    return {
      half: '1H',
      firstHalf: firstHalfTotal,
      secondHalf: secondHalfTotal,
      tied: false,
    };
  }

  if (secondHalfTotal > firstHalfTotal) {
    return {
      half: '2H',
      firstHalf: firstHalfTotal,
      secondHalf: secondHalfTotal,
      tied: false,
    };
  }

  return {
    half: 'TIE',
    firstHalf: firstHalfTotal,
    secondHalf: secondHalfTotal,
    tied: true,
  };
}

function sumEventsByHalf(events = [], predicate) {
  if (!Array.isArray(events) || events.length === 0) {
    return { firstHalf: null, secondHalf: null };
  }

  let firstHalf = 0;
  let secondHalf = 0;
  let countedAny = false;

  for (const ev of events) {
    if (!predicate(ev)) continue;
    const elapsed = Number(ev?.time?.elapsed);
    const extra = Number(ev?.time?.extra) || 0;
    if (!Number.isFinite(elapsed)) continue;

    countedAny = true;
    // First-half stoppage time can appear with elapsed = 45 and extra > 0
    const isFirstHalf = elapsed < 45 || (elapsed === 45 && extra >= 0);
    if (isFirstHalf) {
      firstHalf += 1;
    } else {
      secondHalf += 1;
    }
  }

  if (!countedAny) {
    return { firstHalf: null, secondHalf: null };
  }

  return { firstHalf, secondHalf };
}

function normalizeTeamStats(teamBlock = {}) {
  const map = extractStatMap(teamBlock.statistics);

  return {
    teamId: teamBlock?.team?.id ?? null,
    teamName: teamBlock?.team?.name ?? null,
    teamLogo: teamBlock?.team?.logo ?? null,
    expectedGoals: getStat(map, ['expected_goals', 'xg']),
    totalShots: getStat(map, ['total shots']),
    shotsOnTarget: getStat(map, ['shots on goal', 'shots on target']),
    shotsOffTarget: getStat(map, ['shots off goal', 'shots off target']),
    blockedShots: getStat(map, ['blocked shots']),
    shotsInsideBox: getStat(map, ['shots insidebox', 'shots inside box']),
    shotsOutsideBox: getStat(map, ['shots outsidebox', 'shots outside box']),
    possessionPct: getStat(map, ['ball possession']),
    corners: getStat(map, ['corner kicks']),
    fouls: getStat(map, ['fouls']),
    offsides: getStat(map, ['offsides']),
    yellowCards: getStat(map, ['yellow cards']),
    redCards: getStat(map, ['red cards']),
    totalPasses: getStat(map, ['total passes']),
    passesAccurate: getStat(map, ['passes accurate']),
    passesPct: getStat(map, ['passes %']),
    goalkeeperSaves: getStat(map, ['goalkeeper saves']),
  };
}

/**
 * Normalizes API-Football /fixtures/statistics response and optional halftime/events data.
 *
 * @param {Array} rawStatsResponse - Response array from /fixtures/statistics (full-time or half-time)
 * @param {object} [options]
 * @param {Array} [options.firstHalfStatsResponse] - Optional /fixtures/statistics?half=true response
 * @param {Array} [options.eventsResponse] - Optional /fixtures/events response for goal-by-half fallback
 */
function normalizeMatchStatistics(rawStatsResponse = [], options = {}) {
  const teams = Array.isArray(rawStatsResponse)
    ? rawStatsResponse.map(normalizeTeamStats)
    : [];

  const home = teams[0] || null;
  const away = teams[1] || null;

  // 1) Half with most corners (using full-time corners minus 1H corners if 1H stats are provided)
  let cornerHalfSummary = null;
  if (Array.isArray(options.firstHalfStatsResponse) && options.firstHalfStatsResponse.length >= 2) {
    const h1Home = normalizeTeamStats(options.firstHalfStatsResponse[0]);
    const h1Away = normalizeTeamStats(options.firstHalfStatsResponse[1]);

    if (
      home?.corners !== null &&
      away?.corners !== null &&
      h1Home.corners !== null &&
      h1Away.corners !== null
    ) {
      const firstHalfCorners = h1Home.corners + h1Away.corners;
      const fullTimeCorners = home.corners + away.corners;
      const secondHalfCorners = Math.max(0, fullTimeCorners - firstHalfCorners);
      cornerHalfSummary = resolveHalfWithMost({
        firstHalfTotal: firstHalfCorners,
        secondHalfTotal: secondHalfCorners,
      });
    }
  }

  // 2) Half with most fouls (using full-time fouls minus 1H fouls if 1H stats are provided)
  let foulHalfSummary = null;
  if (Array.isArray(options.firstHalfStatsResponse) && options.firstHalfStatsResponse.length >= 2) {
    const h1Home = normalizeTeamStats(options.firstHalfStatsResponse[0]);
    const h1Away = normalizeTeamStats(options.firstHalfStatsResponse[1]);

    if (
      home?.fouls !== null &&
      away?.fouls !== null &&
      h1Home.fouls !== null &&
      h1Away.fouls !== null
    ) {
      const firstHalfFouls = h1Home.fouls + h1Away.fouls;
      const fullTimeFouls = home.fouls + away.fouls;
      const secondHalfFouls = Math.max(0, fullTimeFouls - firstHalfFouls);
      foulHalfSummary = resolveHalfWithMost({
        firstHalfTotal: firstHalfFouls,
        secondHalfTotal: secondHalfFouls,
      });
    }
  }

  // 3) Half with most goals (from /fixtures/events if provided)
  let goalHalfSummary = null;
  if (Array.isArray(options.eventsResponse) && options.eventsResponse.length > 0) {
    const goalTotals = sumEventsByHalf(options.eventsResponse, (ev) => {
      if (String(ev?.type || '').toLowerCase() !== 'goal') return false;
      const detail = String(ev?.detail || '').toLowerCase();
      return !detail.includes('missed penalty');
    });

    goalHalfSummary = resolveHalfWithMost({
      firstHalfTotal: goalTotals.firstHalf,
      secondHalfTotal: goalTotals.secondHalf,
    });
  }

  return {
    home,
    away,
    halfTrends: {
      mostGoalsHalf: goalHalfSummary,
      mostFoulsHalf: foulHalfSummary,
      mostCornersHalf: cornerHalfSummary,
    },
  };
}

module.exports = { normalizeMatchStatistics };
