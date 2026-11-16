const express = require('express');
const axios = require('axios');

const app = express();
const PORT = process.env.PORT || 10000;

const FOOTBALL_DATA_TOKEN = process.env.FOOTBALL_DATA_TOKEN;
const API_FOOTBALL_KEY = process.env.API_FOOTBALL_KEY;
const TIMEZONE = 'Africa/Nairobi';
const CACHE_TTL_MS = 60 * 1000;
const TABLE_TTL_MS = 10 * 60 * 1000; // football-data.org standings cache
const EXTRA_FIXTURES_TTL_MS = 30 * 60 * 1000; // 30 mins for API-Football fixtures
const EXTRA_TABLE_TTL_MS = 6 * 60 * 60 * 1000; // 6 hours for API-Football tables
const DAYS_BACK = 7;
const DAYS_AHEAD = 8;
const MAX_UPCOMING = 50;
const MAX_FINISHED = 50;

// ---------- 12 Core Competitions (football-data.org free tier) ----------
const CORE_COMPETITIONS = ['PL', 'ELC', 'BL1', 'SA', 'PD', 'FL1', 'DED', 'PPL', 'BSA', 'CL', 'WC', 'EC'];

// ---------- 9 Global Leagues (API-Football v3) ----------
const EXTRA_LEAGUES = {
  KPL: { id: 276, name: 'Kenyan Premier League', season: 2026 },
  MLS: { id: 253, name: 'Major League Soccer', season: 2026 },
  ALE: { id: 188, name: 'A-League Men', season: 2026 },
  SPL: { id: 307, name: 'Saudi Pro League', season: 2026 },
  J1:  { id: 98,  name: 'J1 League', season: 2026 },
  KL1: { id: 292, name: 'K League 1', season: 2026 },
  ACN: { id: 6,   name: 'Africa Cup of Nations', season: 2025 },
  CAF: { id: 12,  name: 'CAF Champions League', season: 2026 },
  ARG: { id: 128, name: 'Liga Profesional Argentina', season: 2026 },
};

const ALL_COMPETITIONS = [...CORE_COMPETITIONS, ...Object.keys(EXTRA_LEAGUES)];

// ---------- Model settings ----------
const RATINGS_TTL_MS = 6 * 60 * 60 * 1000;
const RATINGS_GAP_MS = 8000;
const MIN_LEAGUE_MATCHES = 20;
const MIN_GAMES = 5;
const SHRINK_GAMES = 4;
const MIN_TIP_PROB = 45;
const MAX_GOALS = 8;

const PROLIFIC_TEAMS = [
  'Angola', 'South Sudan', 'Uganda', 'Botswana', 'Algeria', 'Togo',
  'Manchester City', 'Arsenal', 'Liverpool', 'Chelsea', 'Real Madrid',
  'Barcelona', 'Atletico', 'Bayern', 'Leverkusen', 'Inter', 'Juventus',
  'PSG', 'France', 'Brazil', 'Argentina', 'Spain', 'Germany', 'England',
  'Portugal', 'Belgium', 'Netherlands', 'Turkiye', 'Al Hilal', 'Al Nassr',
  'Inter Miami', 'LAFC', 'Al Ahly', 'Mamelodi Sundowns', 'River Plate', 'Boca Juniors'
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
  res.send('My Betting Companion API (20 Global Leagues) is live!');
});

app.get('/health', (req, res) => {
  res.json({
    ok: true,
    totalLeagues: ALL_COMPETITIONS.length,
    hasApiKey: Boolean(FOOTBALL_DATA_TOKEN),
    hasApiFootballKey: Boolean(API_FOOTBALL_KEY),
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

// ---------- Prediction model (for 12 core competitions) ----------
let ratings = {};
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
  const h2h = {};
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

async function refreshRatings() {
  if (ratingsLoading || !FOOTBALL_DATA_TOKEN) return;
  ratingsLoading = true;
  console.log('Rebuilding team ratings...');

  for (const code of CORE_COMPETITIONS) {
    for (let attempt = 1; attempt <= 2; attempt++) {
      try {
        const matches = await fetchCompetitionMatches(code);
        const built = buildRatings(matches);
        if (built) {
          ratings[code] = built;
          console.log(`Ratings ${code}: ${Object.keys(built.teams).length} teams from ${matches.length} matches`);
        } else {
          delete ratings[code];
        }
        break;
      } catch (err) {
        const status = err.response && err.response.status;
        console.error(`Ratings ${code} failed:`, status || '', err.message);
        if (status === 429 && attempt === 1) {
          await sleep(65000);
          continue;
        }
        break;
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
    odds: null,
    isLive,
    isFinished,
    actualScore: isFinished ? `${homeGoals}-${awayGoals}` : 'Pending',
    predictionCorrect: null,
    isProlific: prolific,
    isSample: false,
    isEstimate: false,
  };
}

// ---------- Extra 8 Global Leagues via API-Football ----------
let extraFixturesCache = { data: [], fetchedAt: 0 };

function mapApiFootballStatus(short) {
  if (['1H', 'HT', '2H', 'ET', 'BT', 'P', 'LIVE'].includes(short)) return 'IN_PLAY';
  if (['FT', 'AET', 'PEN'].includes(short)) return 'FINISHED';
  return 'SCHEDULED';
}

async function fetchExtraLeagueFixtures() {
  if (!API_FOOTBALL_KEY) return [];
  const now = Date.now();
  if (extraFixturesCache.data.length > 0 && now - extraFixturesCache.fetchedAt < EXTRA_FIXTURES_TTL_MS) {
    return extraFixturesCache.data;
  }

  const targetLeagueIds = new Set(Object.values(EXTRA_LEAGUES).map((l) => l.id));
  const idToCode = Object.fromEntries(
    Object.entries(EXTRA_LEAGUES).map(([code, info]) => [info.id, code])
  );

  const dates = [utcDateOffset(0), utcDateOffset(1)];
  const results = [];

  try {
    for (const dateStr of dates) {
      const res = await axios.get('https://v3.football.api-sports.io/fixtures', {
        headers: { 'x-apisports-key': API_FOOTBALL_KEY },
        params: { date: dateStr },
        timeout: 15000,
      });

      if (res.data.errors && Object.keys(res.data.errors).length > 0) {
        console.error('API-Football API error:', JSON.stringify(res.data.errors));
      }

      const list = res.data.response || [];
      for (const item of list) {
        const leagueId = item.league && item.league.id;
        if (!targetLeagueIds.has(leagueId)) continue;

        const code = idToCode[leagueId];
        const status = mapApiFootballStatus(item.fixture?.status?.short);
        results.push({
          id: `af-${item.fixture.id}`,
          utcDate: item.fixture.date,
          status,
          competition: {
            code,
            name: EXTRA_LEAGUES[code].name,
          },
          homeTeam: {
            id: item.teams?.home?.id,
            name: item.teams?.home?.name,
            shortName: item.teams?.home?.name,
          },
          awayTeam: {
            id: item.teams?.away?.id,
            name: item.teams?.away?.name,
            shortName: item.teams?.away?.name,
          },
          score: {
            fullTime: {
              home: item.goals?.home,
              away: item.goals?.away,
            },
          },
        });
      }
    }

    extraFixturesCache = { data: results, fetchedAt: now };
    console.log(`API-Football: ${results.length} fixtures fetched across global leagues`);
    return results;
  } catch (err) {
    console.error('API-Football fixtures failed:', err.message);
    return extraFixturesCache.data || [];
  }
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

  const [past, future, extra] = await Promise.all([
    requestMatches(utcDateOffset(-DAYS_BACK), utcDateOffset(0)),
    requestMatches(utcDateOffset(1), utcDateOffset(DAYS_AHEAD)),
    fetchExtraLeagueFixtures(),
  ]);

  const byId = new Map();
  [...(past.data.matches || []), ...(future.data.matches || []), ...extra].forEach((m) => {
    byId.set(m.id, m);
  });
  const matches = Array.from(byId.values());

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

  return [
    ...todays.map((m) => formatFixture(m, false)),
    ...upcoming.map((m) => formatFixture(m, true)),
    ...finished.map((m) => formatFixture(m, true)),
  ];
}

// ---------- Standings & Scorers (Hybrid Router) ----------
const tableCache = {};

async function cachedFootballData(cacheKey, url, params, mapper, ttl = TABLE_TTL_MS) {
  const now = Date.now();
  const cached = tableCache[cacheKey];
  if (cached && now - cached.at < ttl) return cached.data;

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
    if (cached) return cached.data;
    throw err;
  }
}

async function cachedApiFootballTable(cacheKey, endpoint, params, mapper) {
  const now = Date.now();
  const cached = tableCache[cacheKey];
  if (cached && now - cached.at < EXTRA_TABLE_TTL_MS) return cached.data;

  try {
    const res = await axios.get(`https://v3.football.api-sports.io/${endpoint}`, {
      headers: { 'x-apisports-key': API_FOOTBALL_KEY },
      params,
      timeout: 20000,
    });
    const data = mapper(res.data);
    tableCache[cacheKey] = { data, at: now };
    return data;
  } catch (err) {
    if (cached) return cached.data;
    throw err;
  }
}

function sendTableError(res, label, err) {
  const status = err.response && err.response.status;
  const detail = err.response && err.response.data && err.response.data.message;
  console.error(`${label} failed:`, status || '', detail || err.message);
  if (status === 429) return res.status(503).json({ error: 'Rate limited, try again in a minute' });
  if (status === 403) return res.status(403).json({ error: 'Not available on current API plan' });
  return res.status(502).json({ error: 'Could not load data' });
}


  // 1. Global Leagues via API-Football
  if (EXTRA_LEAGUES[code]) {
    if (!API_FOOTBALL_KEY) return res.status(503).json({ error: 'API-Football key not set' });
    const meta = EXTRA_LEAGUES[code];
    try {
      const data = await cachedApiFootballTable(
        `scorers:${code}`,
        'players/topscorers',
        { league: meta.id, season: meta.season },
        (d) => ({
          competition: meta.name,
          scorers: (d.response || []).slice(0, 20).map((item) => ({
            player: item.player?.name || 'Unknown',
            team: item.statistics?.[0]?.team?.name || '',
            goals: item.statistics?.[0]?.goals?.total || 0,
            assists: item.statistics?.[0]?.goals?.assists || 0,
          })),
        })
      );
      return res.json(data);
    } catch (err) {
      return sendTableError(res, `API-Football Scorers ${code}`, err);
    }
  }

  // 2. Core Competitions via football-data.org (Exact original working structure)
  if (!FOOTBALL_DATA_TOKEN) return res.status(503).json({ error: 'Server token not set' });
  try {
    const data = await cachedFootballData(
      `scorers:${code}`,
      `https://api.football-data.org/v4/competitions/${code}/scorers`,
      {},
      (d) => ({
        competition: (d.competition && d.competition.name) || code,
        scorers: (d.scorers || []).map((s) => ({
          player: s.player?.name || 'Unknown',
          team: s.team?.shortName || s.team?.name || '',
          goals: s.goals || 0,
          assists: s.assists ?? 0,
        })),
      })
    );
    return res.json(data);
  } catch (err) {
    return sendTableError(res, `Scorers ${code}`, err);
  }
});
 
// ---------- Top Scorers (Hybrid Router) ----------
app.get('/api/scorers/:code', async (req, res) => {
  const code = String(req.params.code || '').toUpperCase();
  if (!ALL_COMPETITIONS.includes(code)) return res.status(400).json({ error: 'Unknown competition' });

  // Route 1: Global Leagues via API-Football
  if (EXTRA_LEAGUES[code]) {
    if (!API_FOOTBALL_KEY) return res.status(503).json({ error: 'API-Football key not set' });
    const meta = EXTRA_LEAGUES[code];
    try {
      const data = await cachedApiFootballTable(
        `scorers:${code}`,
        'players/topscorers',
        { league: meta.id, season: meta.season },
        (d) => ({
          competition: meta.name,
          scorers: (d.response || []).slice(0, 20).map((item) => ({
            player: item.player?.name || 'Unknown',
            team: item.statistics?.[0]?.team?.name || '',
            goals: item.statistics?.[0]?.goals?.total || 0,
            assists: item.statistics?.[0]?.goals?.assists || 0,
          })),
        })
      );
      return res.json(data);
    } catch (err) {
      return sendTableError(res, `API-Football Scorers ${code}`, err);
    }
  }

  // Route 2: 12 Core Competitions via football-data.org (Original Working State)
  if (!FOOTBALL_DATA_TOKEN) return res.status(503).json({ error: 'Server token not set' });
  try {
    const data = await cachedFootballData(
      `scorers:${code}`,
      `https://api.football-data.org/v4/competitions/${code}/scorers`,
      {},
      (d) => ({
        competition: (d.competition && d.competition.name) || code,
        scorers: (d.scorers || []).map((s) => ({
          player: s.player?.name || '',
          team: (s.team && (s.team.shortName || s.team.name)) || '',
          goals: s.goals || 0,
          assists: s.assists ?? 0,
        })),
      })
    );
    return res.json(data);
  } catch (err) {
    return sendTableError(res, `Scorers ${code}`, err);
  }
});

// ---------- Standings (Hybrid Router) ----------
app.get('/api/standings/:code', async (req, res) => {
  const code = String(req.params.code || '').toUpperCase();

  if (!ALL_COMPETITIONS.includes(code)) {
    return res.status(400).json({
      error: 'Unknown competition',
    });
  }

  // Extra leagues from API-Football
  if (EXTRA_LEAGUES[code]) {
    if (!API_FOOTBALL_KEY) {
      return res.status(503).json({
        error: 'API-Football key not set',
      });
    }

    const meta = EXTRA_LEAGUES[code];

    try {
      const data = await cachedApiFootballTable(
        `standings:${code}`,
        'standings',
        {
          league: meta.id,
          season: meta.season,
        },
        (d) => {
          const standings =
            d.response?.[0]?.league?.standings?.[0] || [];

          return {
            competition: meta.name,
            standings: standings.map((row) => ({
              position: row.rank,
              team: row.team?.name || '',
              played: row.all?.played || 0,
              won: row.all?.win || 0,
              draw: row.all?.draw || 0,
              lost: row.all?.lose || 0,
              goalsFor: row.all?.goals?.for || 0,
              goalsAgainst: row.all?.goals?.against || 0,
              goalDifference: row.goalsDiff || 0,
              points: row.points || 0,
            })),
          };
        }
      );

      return res.json(data);
    } catch (err) {
      return sendTableError(
        res,
        `Standings ${code}`,
        err
      );
    }
  }

  // Core football-data.org competitions
  if (!FOOTBALL_DATA_TOKEN) {
    return res.status(503).json({
      error: 'Server token not set',
    });
  }

  try {
    const data = await cachedFootballData(
      `standings:${code}`,
      `https://api.football-data.org/v4/competitions/${code}/standings`,
      {},
      (d) => {
        const table =
          d.standings?.find((s) => s.type === 'TOTAL')?.table ||
          d.standings?.[0]?.table ||
          [];

        return {
          competition: d.competition?.name || code,
          standings: table.map((row) => ({
            position: row.position,
            team:
              row.team?.shortName ||
              row.team?.name ||
              '',
            played: row.playedGames,
            won: row.won,
            draw: row.draw,
            lost: row.lost,
            goalsFor: row.goalsFor,
            goalsAgainst: row.goalsAgainst,
            goalDifference: row.goalDifference,
            points: row.points,
          })),
        };
      }
    );

    return res.json(data);
  } catch (err) {
    return sendTableError(
      res,
      `Standings ${code}`,
      err
    );
  }
});


// ---------- Team Insights Route ----------
const teamInsightsCache = new Map();
const CACHE_DURATION_MS = 6 * 60 * 60 * 1000;

app.get('/api/team-insights', async (req, res) => {
  const teamName = req.query.team;
  if (!teamName) {
    return res.status(400).json({ error: 'Team name is required' });
  }

  const cacheKey = teamName.toLowerCase().trim();
  const cached = teamInsightsCache.get(cacheKey);
  if (cached && Date.now() - cached.timestamp < CACHE_DURATION_MS) {
    return res.json(cached.data);
  }

  try {
    const teamRes = await axios.get(`https://v3.football.api-sports.io/teams`, {
      headers: { 'x-apisports-key': API_FOOTBALL_KEY },
      params: { search: teamName },
      timeout: 15000,
    });
    const teamId = teamRes.data.response?.[0]?.team?.id;

    if (!teamId) {
      return res.json({ response: [] });
    }

    const injuriesRes = await axios.get(`https://v3.football.api-sports.io/injuries`, {
      headers: { 'x-apisports-key': API_FOOTBALL_KEY },
      params: { team: teamId, season: 2026 },
      timeout: 15000,
    });
    const injuriesData = injuriesRes.data;

    teamInsightsCache.set(cacheKey, {
      timestamp: Date.now(),
      data: injuriesData,
    });

    res.json(injuriesData);
  } catch (error) {
    console.error('Error fetching team insights:', error.message);
    res.status(500).json({ error: 'Failed to fetch team insights' });
  }
});

app.get('/debug-fixtures', async (req, res) => {
  try {
    const response = await axios.get(
      'https://v3.football.api-sports.io/fixtures',
      {
        headers: {
          'x-apisports-key': API_FOOTBALL_KEY,
        },
        params: {
          date: utcDateOffset(0),
        },
      }
    );

    const sample = response.data.response.map(f => ({
      leagueId: f.league?.id,
      leagueName: f.league?.name,
      country: f.league?.country,
      home: f.teams?.home?.name,
      away: f.teams?.away?.name,
    }));

    res.json(sample);
  } catch (e) {
    res.status(500).json({
      error: e.message,
    });
  }
});


// ---------- Fixtures Route ----------
app.get('/api/fixtures', async (req, res) => {
  ensureRatings();

  let matches = [];
  if (FOOTBALL_DATA_TOKEN || API_FOOTBALL_KEY) {
    try {
      matches = await fetchMatchWindow();
    } catch (err) {
      console.error('Match window fetch failed:', err.message);
      if (cache.data) matches = cache.data;
    }
  }

  const fixtures = pickFixtures(matches);
  return res.json(fixtures);
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Server active on port ${PORT} covering ${ALL_COMPETITIONS.length} leagues`);
  ensureRatings();
});
           
