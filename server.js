const express = require('express');
const axios = require('axios');

const app = express();
const PORT = process.env.PORT || 10000;

const FOOTBALL_DATA_TOKEN = process.env.FOOTBALL_DATA_TOKEN;
const TIMEZONE = 'Africa/Nairobi';
const CACHE_TTL_MS = 60 * 1000;
const TABLE_TTL_MS = 10 * 60 * 1000; // standings / scorers cache
const DAYS_BACK = 7;
const DAYS_AHEAD = 8;
const MAX_UPCOMING = 40;
const MAX_FINISHED = 40;

// ---------- Model settings ----------
const COMPETITIONS = ['PL', 'ELC', 'BL1', 'SA', 'PD', 'FL1', 'DED', 'PPL', 'BSA', 'CL', 'WC', 'EC'];
const RATINGS_TTL_MS = 6 * 60 * 60 * 1000; // rebuild ratings every 6 hours
const RATINGS_GAP_MS = 8000; // free plan allows 10 requests/minute
const MIN_LEAGUE_MATCHES = 20; // need this many finished matches in a competition
const MIN_GAMES = 5; // each team needs this many games
const SHRINK_GAMES = 4; // pulls small samples toward the league average
const MIN_TIP_PROB = 45; // no tip unless a side has at least this % to win
const MAX_GOALS = 8;

const PROLIFIC_TEAMS = [
  'Angola', 'South Sudan', 'Uganda', 'Botswana', 'Algeria', 'Togo',
  'Manchester City', 'Arsenal', 'Liverpool', 'Chelsea', 'Real Madrid',
  'Barcelona', 'Atletico', 'Bayern', 'Leverkusen', 'Inter', 'Juventus',
  'PSG', 'France', 'Brazil', 'Argentina', 'Spain', 'Germany', 'England',
  'Portugal', 'Belgium', 'Netherlands', 'Turkiye'
];

// ---------- CORS ----------
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept');
  res.header('Access-Control-Allow-Methods', 'GET, OPTIONS');
  if (req.method === 'OPTIONS') return res.sendStatus(204);
  next();
});

// ---------- Health ----------
app.get('/', (req, res) => {
  res.send('My Betting Companion API is live!');
});

app.get('/health', (req, res) => {
  res.json({
    ok: true,
    hasApiKey: Boolean(FOOTBALL_DATA_TOKEN),
    ratingsLoading,
    ratingsCompetitions: Object.keys(ratings),
  });
});

// ---------- Helpers ----------
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function dateInNairobi(date) {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: TIMEZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(date);
}

function todayInNairobi() {
  return dateInNairobi(new Date());
}

function utcDateOffset(days) {
  return new Date(Date.now() + days * 86400000).toISOString().slice(0, 10);
}

function formatEatTime(isoDate) {
  return (
    new Date(isoDate).toLocaleTimeString('en-GB', {
      hour: '2-digit',
      minute: '2-digit',
      timeZone: TIMEZONE,
    }) + ' EAT'
  );
}

function formatEatDateTime(isoDate) {
  const day = new Date(isoDate).toLocaleDateString('en-GB', {
    weekday: 'short',
    day: 'numeric',
    month: 'short',
    timeZone: TIMEZONE,
  });
  return `${day}, ${formatEatTime(isoDate)}`;
}

function formatEatDate(isoDate) {
  return new Date(isoDate).toLocaleDateString('en-GB', {
    weekday: 'short',
    day: 'numeric',
    month: 'short',
    timeZone: TIMEZONE,
  });
}

function isProlificTeam(teamName) {
  const name = teamName.toLowerCase();
  return PROLIFIC_TEAMS.some((t) => name.includes(t.toLowerCase()));
}

// ---------- Prediction model ----------
let ratings = {}; // competition code -> { teams, avgHome, avgAway, avgTeam, h2h }
let ratingsBuiltAt = 0;
let ratingsLoading = false;

function poisson(k, lambda) {
  let p = Math.exp(-lambda);
  for (let i = 1; i <= k; i++) p *= lambda / i;
  return p;
}

function pairKey(a, b) {
  return a < b ? `${a}-${b}` : `${b}-${a}`;
}

function buildRatings(matches) {
  const finished = matches
    .filter(
      (m) =>
        m.score &&
        m.score.fullTime &&
        m.score.fullTime.home !== null &&
        m.score.fullTime.home !== undefined &&
        m.score.fullTime.away !== null &&
        m.score.fullTime.away !== undefined &&
        m.homeTeam && m.homeTeam.id &&
        m.awayTeam && m.awayTeam.id
    )
    .sort((a, b) => new Date(a.utcDate) - new Date(b.utcDate));

  if (finished.length < MIN_LEAGUE_MATCHES) return null;

  const teams = {};
  const h2h = {}; // pair of team ids -> list of meetings this season
  let homeGoals = 0;
  let awayGoals = 0;

  const team = (id) => {
    if (!teams[id]) teams[id] = { gf: 0, ga: 0, n: 0, form: [] };
    return teams[id];
  };

  for (const m of finished) {
    const gh = m.score.fullTime.home;
    const ga = m.score.fullTime.away;
    homeGoals += gh;
    awayGoals += ga;

    const h = team(m.homeTeam.id);
    const a = team(m.awayTeam.id);
    h.gf += gh; h.ga += ga; h.n += 1;
    a.gf += ga; a.ga += gh; a.n += 1;
    h.form.push(gh > ga ? 'W' : gh === ga ? 'D' : 'L');
    a.form.push(ga > gh ? 'W' : ga === gh ? 'D' : 'L');

    const pk = pairKey(m.homeTeam.id, m.awayTeam.id);
    if (!h2h[pk]) h2h[pk] = [];
    h2h[pk].push({
      utcDate: m.utcDate,
      home: m.homeTeam.shortName || m.homeTeam.name,
      away: m.awayTeam.shortName || m.awayTeam.name,
      hg: gh,
      ag: ga,
    });
  }

  const n = finished.length;
  const avgHome = homeGoals / n;
  const avgAway = awayGoals / n;
  const avgTeam = (avgHome + avgAway) / 2;
  if (avgTeam <= 0) return null;

  return { teams, avgHome, avgAway, avgTeam, h2h };
}

function predictMatch(code, homeId, awayId, homeName, awayName) {
  const r = ratings[code];
  if (!r || !homeId || !awayId) return null;
  const h = r.teams[homeId];
  const a = r.teams[awayId];
  if (!h || !a || h.n < MIN_GAMES || a.n < MIN_GAMES) return null;

  const K = SHRINK_GAMES;
  const atk = (t) => (t.gf + K * r.avgTeam) / (t.n + K) / r.avgTeam;
  const def = (t) => (t.ga + K * r.avgTeam) / (t.n + K) / r.avgTeam;

  const lambdaHome = r.avgHome * atk(h) * def(a);
  const lambdaAway = r.avgAway * atk(a) * def(h);

  let pH = 0, pD = 0, pA = 0, pOver = 0, pBtts = 0, total = 0;
  for (let i = 0; i <= MAX_GOALS; i++) {
    for (let j = 0; j <= MAX_GOALS; j++) {
      const p = poisson(i, lambdaHome) * poisson(j, lambdaAway);
      total += p;
      if (i > j) pH += p;
      else if (i === j) pD += p;
      else pA += p;
      if (i + j >= 3) pOver += p;
      if (i > 0 && j > 0) pBtts += p;
    }
  }

  const homeWinProb = Math.round((pH / total) * 100);
  const awayWinProb = Math.round((pA / total) * 100);
  const drawProb = 100 - homeWinProb - awayWinProb;

  let topTip = '';
  let tipProb = null;
  const homeFav = homeWinProb >= awayWinProb;
  const favProb = homeFav ? homeWinProb : awayWinProb;
  if (favProb >= MIN_TIP_PROB) {
    topTip = `${homeFav ? homeName : awayName} Win`;
    tipProb = favProb;
  }

  // Head-to-head: previous meetings this season in the same competition.
  const meetings = (r.h2h && r.h2h[pairKey(homeId, awayId)]) || [];
  const h2h = meetings
    .slice(-5)
    .reverse()
    .map((x) => ({
      date: formatEatDate(x.utcDate),
      home: x.home,
      away: x.away,
      score: `${x.hg}-${x.ag}`,
    }));

  return {
    homeWinProb,
    drawProb,
    awayWinProb,
    over25Goals: `${Math.round((pOver / total) * 100)}%`,
    btts: `${Math.round((pBtts / total) * 100)}%`,
    topTip,
    tipProb,
    homeForm: h.form.slice(-5),
    awayForm: a.form.slice(-5),
    h2h,
  };
}

async function fetchCompetitionMatches(code) {
  const res = await axios.get(
    `https://api.football-data.org/v4/competitions/${code}/matches`,
    {
      headers: { 'X-Auth-Token': FOOTBALL_DATA_TOKEN },
      params: { status: 'FINISHED' },
      timeout: 20000,
    }
  );
  return res.data.matches || [];
}

// Runs in the background, one competition at a time, to stay under the rate limit.
async function refreshRatings() {
  if (ratingsLoading || !FOOTBALL_DATA_TOKEN) return;
  ratingsLoading = true;
  console.log('Rebuilding team ratings...');

  for (const code of COMPETITIONS) {
    for (let attempt = 1; attempt <= 2; attempt++) {
      try {
        const matches = await fetchCompetitionMatches(code);
        const built = buildRatings(matches);
        if (built) {
          ratings[code] = built;
          console.log(`Ratings ${code}: ${Object.keys(built.teams).length} teams from ${matches.length} matches`);
        } else {
          delete ratings[code];
          console.log(`Ratings ${code}: not enough finished matches yet`);
        }
        break;
      } catch (err) {
        const status = err.response && err.response.status;
        console.error(`Ratings ${code} failed:`, status || '', err.message);
        if (status === 429 && attempt === 1) {
          await sleep(65000); // rate limited: wait a minute, then retry once
          continue;
        }
        break; // 403 (not in plan) or other error: skip this competition
      }
    }
    await sleep(RATINGS_GAP_MS);
  }

  ratingsBuiltAt = Date.now();
  ratingsLoading = false;
  console.log(`Ratings ready for: ${Object.keys(ratings).join(', ') || 'none'}`);
}

function ensureRatings() {
  if (!ratingsLoading && Date.now() - ratingsBuiltAt > RATINGS_TTL_MS) {
    refreshRatings().catch((e) => {
      ratingsLoading = false;
      console.error('refreshRatings crashed:', e.message);
    });
  }
}

// ---------- Live data mapping (football-data.org v4) ----------
const LIVE_STATUSES = ['IN_PLAY', 'PAUSED', 'LIVE'];
const FINISHED_STATUSES = ['FINISHED', 'AWARDED'];
const UPCOMING_STATUSES = ['SCHEDULED', 'TIMED'];

function formatFixture(item, showDate = false) {
  const status = item.status;
  const isLive = LIVE_STATUSES.includes(status);
  const isFinished = FINISHED_STATUSES.includes(status);

  const homeTeam = (item.homeTeam && (item.homeTeam.name || item.homeTeam.shortName)) || 'Home Team';
  const awayTeam = (item.awayTeam && (item.awayTeam.name || item.awayTeam.shortName)) || 'Away Team';

  const prolific = isProlificTeam(homeTeam) || isProlificTeam(awayTeam);

  const fullTime = (item.score && item.score.fullTime) || {};
  const homeGoals = fullTime.home ?? 0;
  const awayGoals = fullTime.away ?? 0;

  // Predictions only for matches that have not finished (no hindsight).
  const code = item.competition && item.competition.code;
  const pred = isFinished
    ? null
    : predictMatch(
        code,
        item.homeTeam && item.homeTeam.id,
        item.awayTeam && item.awayTeam.id,
        homeTeam,
        awayTeam
      );

  let time;
  if (isLive) {
    time = `${homeGoals} - ${awayGoals}`;
  } else if (isFinished) {
    time = showDate ? formatEatDate(item.utcDate) : `${homeGoals} - ${awayGoals}`;
  } else {
    time = showDate ? formatEatDateTime(item.utcDate) : formatEatTime(item.utcDate);
  }

  return {
    key: String(item.id),
    utcDate: item.utcDate,
    competitionCode: code || '',
    dateLabel: formatEatDate(item.utcDate),
    kickoffTime: formatEatTime(item.utcDate),
    league: (item.competition && item.competition.name) || 'Global Competition',
    time,
    homeTeam,
    awayTeam,
    homeForm: pred ? pred.homeForm : [],
    awayForm: pred ? pred.awayForm : [],
    h2h: pred ? pred.h2h : [],
    homeWinProb: pred ? pred.homeWinProb : 0,
    drawProb: pred ? pred.drawProb : 0,
    awayWinProb: pred ? pred.awayWinProb : 0,
    over25Goals: pred ? pred.over25Goals : 'N/A',
    btts: pred ? pred.btts : 'N/A',
    cardRisk: 'N/A',
    topTip: pred ? pred.topTip : '',
    tipProb: pred ? pred.tipProb : null,
    odds: null, // no real bookmaker odds available
    isLive,
    isFinished,
    actualScore: isFinished ? `${homeGoals}-${awayGoals}` : 'Pending',
    predictionCorrect: null,
    isProlific: prolific,
    isSample: false,
    isEstimate: false,
  };
}

// ---------- Fetching + cache ----------
let cache = { data: null, fetchedAt: 0 };

function requestMatches(dateFrom, dateTo) {
  return axios.get('https://api.football-data.org/v4/matches', {
    headers: { 'X-Auth-Token': FOOTBALL_DATA_TOKEN },
    params: { dateFrom, dateTo },
    timeout: 15000,
  });
}

async function fetchMatchWindow() {
  const now = Date.now();
  if (cache.data && now - cache.fetchedAt < CACHE_TTL_MS) {
    return cache.data;
  }

  const [past, future] = await Promise.all([
    requestMatches(utcDateOffset(-DAYS_BACK), utcDateOffset(0)),
    requestMatches(utcDateOffset(1), utcDateOffset(DAYS_AHEAD)),
  ]);

  const byId = new Map();
  [...(past.data.matches || []), ...(future.data.matches || [])].forEach((m) => {
    byId.set(m.id, m);
  });
  const matches = Array.from(byId.values());

  const available = future.headers['x-requests-available-minute'];
  console.log(
    `football-data.org: ${matches.length} matches fetched` +
      (available !== undefined ? ` (requests left this minute: ${available})` : '')
  );

  cache = { data: matches, fetchedAt: now };
  return matches;
}

function pickFixtures(allMatches) {
  const today = todayInNairobi();
  const now = new Date();
  const sevenDaysAgo = new Date(Date.now() - DAYS_BACK * 86400000);

  const isToday = (m) => dateInNairobi(new Date(m.utcDate)) === today;

  const todays = allMatches
    .filter((m) => isToday(m) || LIVE_STATUSES.includes(m.status))
    .sort((a, b) => new Date(a.utcDate) - new Date(b.utcDate));

  const upcoming = allMatches
    .filter(
      (m) =>
        !isToday(m) &&
        UPCOMING_STATUSES.includes(m.status) &&
        new Date(m.utcDate) > now
    )
    .sort((a, b) => new Date(a.utcDate) - new Date(b.utcDate))
    .slice(0, MAX_UPCOMING);

  const finished = allMatches
    .filter(
      (m) =>
        !isToday(m) &&
        !LIVE_STATUSES.includes(m.status) &&
        FINISHED_STATUSES.includes(m.status) &&
        new Date(m.utcDate) >= sevenDaysAgo
    )
    .sort((a, b) => new Date(b.utcDate) - new Date(a.utcDate))
    .slice(0, MAX_FINISHED);

  console.log(
    `Fixtures for ${today}: ${todays.length} today, ${upcoming.length} upcoming, ${finished.length} finished`
  );

  return [
    ...todays.map((m) => formatFixture(m, false)),
    ...upcoming.map((m) => formatFixture(m, true)),
    ...finished.map((m) => formatFixture(m, true)),
  ];
}

// ---------- Standings and top scorers ----------
const tableCache = {}; // cacheKey -> { data, at }

async function cachedFootballData(cacheKey, url, params, mapper) {
  const now = Date.now();
  const cached = tableCache[cacheKey];
  if (cached && now - cached.at < TABLE_TTL_MS) return cached.data;

  try {
    const res = await axios.get(url, {
      headers: { 'X-Auth-Token': FOOTBALL_DATA_TOKEN },
      params,
      timeout: 20000,
    });
    const data = mapper(res.data);
    tableCache[cacheKey] = { data, at: now };
    return data;
  } catch (err) {
    if (cached) return cached.data; // serve stale data rather than failing
    throw err;
  }
}

function sendTableError(res, label, err) {
  const status = err.response && err.response.status;
  const detail = err.response && err.response.data && err.response.data.message;
  console.error(`${label} failed:`, status || '', detail || err.message);
  if (status === 429) return res.status(503).json({ error: 'Rate limited, try again in a minute' });
  if (status === 403) return res.status(403).json({ error: 'Not available on the free plan' });
  return res.status(502).json({ error: 'Could not load data' });
}

app.get('/api/standings/:code', async (req, res) => {
  const code = String(req.params.code || '').toUpperCase();
  if (!COMPETITIONS.includes(code)) return res.status(400).json({ error: 'Unknown competition' });
  if (!FOOTBALL_DATA_TOKEN) return res.status(503).json({ error: 'Server token not set' });

  try {
    const data = await cachedFootballData(
      `standings:${code}`,
      `https://api.football-data.org/v4/competitions/${code}/standings`,
      {},
      (d) => ({
        competition: (d.competition && d.competition.name) || code,
        groups: (d.standings || [])
          .filter((s) => !s.type || s.type === 'TOTAL')
          .map((s) => ({
            name: s.group ? String(s.group).replace(/_/g, ' ') : '',
            table: (s.table || []).map((r) => ({
              position: r.position,
              team: (r.team && (r.team.shortName || r.team.name)) || '',
              played: r.playedGames,
              won: r.won,
              draw: r.draw,
              lost: r.lost,
              goalsFor: r.goalsFor,
              goalsAgainst: r.goalsAgainst,
              goalDifference: r.goalDifference,
              points: r.points,
              form: r.form || '',
            })),
          })),
      })
    );
    return res.json(data);
  } catch (err) {
    return sendTableError(res, `Standings ${code}`, err);
  }
});

app.get('/api/scorers/:code', async (req, res) => {
  const code = String(req.params.code || '').toUpperCase();
  if (!COMPETITIONS.includes(code)) return res.status(400).json({ error: 'Unknown competition' });
  if (!FOOTBALL_DATA_TOKEN) return res.status(503).json({ error: 'Server token not set' });

  try {
    const data = await cachedFootballData(
      `scorers:${code}`,
      `https://api.football-data.org/v4/competitions/${code}/scorers`,
      { limit: 20 },
      (d) => ({
        competition: (d.competition && d.competition.name) || code,
        scorers: (d.scorers || []).map((s) => ({
          name: (s.player && s.player.name) || '',
          team: (s.team && (s.team.shortName || s.team.name)) || '',
          goals: s.goals || 0,
          assists: s.assists || 0,
          penalties: s.penalties || 0,
          played: s.playedMatches || 0,
        })),
      })
    );
    return res.json(data);
  } catch (err) {
    return sendTableError(res, `Scorers ${code}`, err);
  }
});

// ---------- Route ----------
app.get('/api/fixtures', async (req, res) => {
  ensureRatings(); // starts in the background, never blocks the response

  let matches = [];

  if (FOOTBALL_DATA_TOKEN) {
    try {
      matches = await fetchMatchWindow();
    } catch (err) {
      const status = err.response && err.response.status;
      const detail = err.response && err.response.data && err.response.data.message;
      console.error('football-data.org request failed:', status || '', detail || err.message);
      if (cache.data) matches = cache.data;
    }
  } else {
    console.warn('FOOTBALL_DATA_TOKEN is not set.');
  }

  const fixtures = pickFixtures(matches);
  return res.json(fixtures);
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Server active on port ${PORT}`);
  ensureRatings();
});
