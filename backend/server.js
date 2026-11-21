const express = require('express');
const axios = require('axios');
const mongoose = require('mongoose');

const app = express();
const PORT = process.env.PORT || 10000;

// ---------- Environment Variables & Core Configuration ----------
// .trim() protects against stray spaces / line breaks pasted into Render
const FOOTBALL_DATA_TOKEN = (process.env.FOOTBALL_DATA_TOKEN || '').trim();
const API_FOOTBALL_KEY = (process.env.API_FOOTBALL_KEY || '').trim();
const ODDS_API_KEY = (process.env.ODDS_API_KEY || '').trim();
const MONGO_URI = (process.env.MONGO_URI || process.env.MONGODB_URI || '').trim();

if (!MONGO_URI) {
  console.error('MongoDB connection error: MONGO_URI / MONGODB_URI is not set');
} else {
  mongoose
    .connect(MONGO_URI)
    .then(() => console.log('Connected to MongoDB Atlas'))
    .catch((err) => console.error('MongoDB connection error:', err.message));
}

const TIMEZONE = 'Africa/Nairobi';
const CACHE_TTL_MS = 60 * 1000;
const TABLE_TTL_MS = 10 * 60 * 1000; // football-data.org standings/scorers cache
const EXTRA_FIXTURES_TTL_MS = 2 * 60 * 60 * 1000; // 2 hours for API-Football fixtures
const EXTRA_RETRY_AFTER_FAIL_MS = 5 * 60 * 1000; // wait 5 mins after a failed API-Football call
const EXTRA_TABLE_TTL_MS = 6 * 60 * 60 * 1000; // 6 hours for API-Football tables (protects 100/day limit)
const EXTRA_DAYS_BACK = 1; // Free plan only allows yesterday, today and tomorrow
const EXTRA_DAYS_AHEAD = 1; // = 3 API-Football calls per refresh
const DAYS_BACK = 7;
const DAYS_AHEAD = 8;
const MAX_UPCOMING = 50;
const MAX_FINISHED = 50;
const ODDS_CACHE_TTL_MS = 45 * 60 * 1000; // 45 minutes
const responseCache = new Map();

async function getCached(cacheKey, ttlMs, fetcher) {
  const now = Date.now();
  const existing = responseCache.get(cacheKey);

  if (existing && existing.expiresAt > now) {
    return existing.data;
  }

  const freshData = await fetcher();
  responseCache.set(cacheKey, {
    data: freshData,
    expiresAt: now + ttlMs,
  });
  return freshData;
}

// ---------- 12 Core Competitions (football-data.org free tier) ----------
const CORE_COMPETITIONS = ['PL', 'ELC', 'BL1', 'SA', 'PD', 'FL1', 'DED', 'PPL', 'BSA', 'CL', 'WC', 'EC'];

// ---------- Extra Global Leagues (API-Football v3) ----------
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

app.use(express.json());

// ---------- Health ----------
app.get('/', (req, res) => {
  res.send('My Betting Companion API (' + ALL_COMPETITIONS.length + ' Global Leagues) is live!');
});

app.get('/health', (req, res) => {
  res.json({
    ok: true,
    totalLeagues: ALL_COMPETITIONS.length,
    hasApiKey: Boolean(FOOTBALL_DATA_TOKEN),
    hasApiFootballKey: Boolean(API_FOOTBALL_KEY),
    hasOddsApiKey: Boolean(ODDS_API_KEY),
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

  let pH = 0, pD = 0, pA = 0, pOver15 = 0, pOver = 0, pUnder35 = 0, pBtts = 0, total = 0;
for (let i = 0; i <= MAX_GOALS; i++) {
  for (let j = 0; j <= MAX_GOALS; j++) {
    const p = poisson(i, lambdaHome) * poisson(j, lambdaAway);
    total += p;
    if (i > j) pH += p;
    else if (i === j) pD += p;
    else pA += p;
    if (i + j >= 2) pOver15 += p;
    if (i + j >= 3) pOver += p;
    if (i + j <= 3) pUnder35 += p;
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
    over15Goals: `${Math.round((pOver15 / total) * 100)}%`,
    over25Goals: `${Math.round((pOver / total) * 100)}%`,
    under35Goals: `${Math.round((pUnder35 / total) * 100)}%`,
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

// ---------- Live data mapping ----------
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
  let pred = null;
try {
  pred = predictMatch(
    code,
    item.homeTeam && item.homeTeam.id,
    item.awayTeam && item.awayTeam.id,
    homeTeam,
    awayTeam
  );
} catch (e) {
  pred = null;
}

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
    league: (item.competition && item.competition.name) || 'League',
    time,
    homeTeam,
    awayTeam,
    homeForm: pred ? pred.homeForm : [],
    awayForm: pred ? pred.awayForm : [],
    h2h: pred ? pred.h2h : [],
    homeWinProb: pred ? pred.homeWinProb : 0,
    drawProb: pred ? pred.drawProb : 0,
    awayWinProb: pred ? pred.awayWinProb : 0,
    over15Goals: pred && pred.over15Goals != null ? pred.over15Goals : 'N/A',
    over25Goals: pred && pred.over25Goals != null ? pred.over25Goals : 'N/A',
    under35Goals: pred && pred.under35Goals != null ? pred.under35Goals : 'N/A',
    btts: pred && pred.btts != null ? pred.btts : 'N/A',
    cardRisk: pred && pred.cardRisk != null ? pred.cardRisk : 'N/A',
    firstHalfGoalsProb: pred ? pred.firstHalfGoalsProb ?? null : null,
    secondHalfGoalsProb: pred ? pred.secondHalfGoalsProb ?? null : null,
    homeCardsProb: pred ? pred.homeCardsProb ?? null : null,
    drawCardsProb: pred ? pred.drawCardsProb ?? null : null,
    awayCardsProb: pred ? pred.awayCardsProb ?? null : null,
    firstHalfCardsProb: pred ? pred.firstHalfCardsProb ?? null : null,
    secondHalfCardsProb: pred ? pred.secondHalfCardsProb ?? null : null,
    anytimeScorers: pred && Array.isArray(pred.anytimeScorers) ? pred.anytimeScorers : [],
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
app.get('/api/fixtures', async (req, res) => {
  try {
    await ensureRatings();
    const allMatches = await fetchMatchWindow();
    const fixtures = pickFixtures(allMatches);
    return res.json(fixtures);
  } catch (err) {
    console.error('Error serving /api/fixtures:', err.message);
    return res.status(500).json({ error: 'Failed to load fixtures' });
  }
});

// ---------- Extra Global Leagues via API-Football ----------
let extraFixturesCache = { data: [], fetchedAt: 0 };
let extraLastFailAt = 0;

function mapApiFootballStatus(short) {
  if (['1H', 'HT', '2H', 'ET', 'BT', 'P', 'LIVE'].includes(short)) return 'IN_PLAY';
  if (['FT', 'AET', 'PEN', 'AWD', 'WO'].includes(short)) return 'FINISHED';
  if (['PST', 'CANC', 'ABD', 'SUSP', 'INT'].includes(short)) return 'POSTPONED';
  return 'SCHEDULED';
}

function hasApiErrors(body) {
  const errs = body && body.errors;
  return Boolean(errs && Object.keys(errs).length > 0);
}

async function fetchExtraLeagueFixtures() {
  if (!API_FOOTBALL_KEY) return [];
  const now = Date.now();

  if (extraFixturesCache.fetchedAt && now - extraFixturesCache.fetchedAt < EXTRA_FIXTURES_TTL_MS) {
    return extraFixturesCache.data;
  }
  if (extraLastFailAt && now - extraLastFailAt < EXTRA_RETRY_AFTER_FAIL_MS) {
    return extraFixturesCache.data;
  }

  const targetLeagueIds = new Set(Object.values(EXTRA_LEAGUES).map((l) => l.id));
  const idToCode = Object.fromEntries(
    Object.entries(EXTRA_LEAGUES).map(([code, info]) => [info.id, code])
  );

  const dates = [];
  for (let i = -EXTRA_DAYS_BACK; i <= EXTRA_DAYS_AHEAD; i++) dates.push(utcDateOffset(i));

  const results = [];
  let okDates = 0;

  for (const dateStr of dates) {
    try {
      const res = await axios.get('https://v3.football.api-sports.io/fixtures', {
        headers: { 'x-apisports-key': API_FOOTBALL_KEY },
        params: { date: dateStr },
        timeout: 15000,
      });

      if (hasApiErrors(res.data)) {
        console.error('API-Football API error:', JSON.stringify(res.data.errors));
        continue;
      }

      okDates += 1;
      const list = res.data.response || [];
      let matched = 0;

      for (const item of list) {
        const leagueId = item.league && item.league.id;
        if (!targetLeagueIds.has(leagueId)) continue;

        const code = idToCode[leagueId];
        const status = mapApiFootballStatus(item.fixture && item.fixture.status && item.fixture.status.short);
        matched += 1;
        results.push({
          id: `af-${item.fixture.id}`,
          utcDate: item.fixture.date,
          status,
          competition: {
            code,
            name: EXTRA_LEAGUES[code].name,
          },
          homeTeam: {
            id: item.teams && item.teams.home && item.teams.home.id,
            name: item.teams && item.teams.home && item.teams.home.name,
            shortName: item.teams && item.teams.home && item.teams.home.name,
          },
          awayTeam: {
            id: item.teams && item.teams.away && item.teams.away.id,
            name: item.teams && item.teams.away && item.teams.away.name,
            shortName: item.teams && item.teams.away && item.teams.away.name,
          },
          score: {
            fullTime: {
              home: item.goals ? item.goals.home : null,
              away: item.goals ? item.goals.away : null,
            },
          },
        });
      }

      console.log(`API-Football ${dateStr}: ${list.length} total fixtures, ${matched} in your leagues`);
    } catch (err) {
      const status = err.response && err.response.status;
      console.error(`API-Football fixtures ${dateStr} failed:`, status || '', err.message);
    }
  }

  if (okDates === 0) {
    extraLastFailAt = now;
    return extraFixturesCache.data;
  }

  extraLastFailAt = 0;
  extraFixturesCache = { data: results, fetchedAt: now };
  console.log(`API-Football: ${results.length} fixtures fetched across ${Object.keys(EXTRA_LEAGUES).length} global leagues`);
  return results;
}

// ---------- Fetching + cache (football-data.org + API-Football) ----------
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

  const [pastR, futureR, extraR] = await Promise.allSettled([
    FOOTBALL_DATA_TOKEN ? requestMatches(utcDateOffset(-DAYS_BACK), utcDateOffset(0)) : Promise.reject(new Error('no football-data token')),
    FOOTBALL_DATA_TOKEN ? requestMatches(utcDateOffset(1), utcDateOffset(DAYS_AHEAD)) : Promise.reject(new Error('no football-data token')),
    fetchExtraLeagueFixtures(),
  ]);

  if (pastR.status === 'rejected') console.error('football-data (past) failed:', pastR.reason && pastR.reason.message);
  if (futureR.status === 'rejected') console.error('football-data (future) failed:', futureR.reason && futureR.reason.message);
  if (extraR.status === 'rejected') console.error('API-Football failed:', extraR.reason && extraR.reason.message);

  const past = pastR.status === 'fulfilled' ? pastR.value.data.matches || [] : [];
  const future = futureR.status === 'fulfilled' ? futureR.value.data.matches || [] : [];
  const extra = extraR.status === 'fulfilled' ? extraR.value || [] : [];

  const byId = new Map();
  [...past, ...future, ...extra].forEach((m) => {
    byId.set(m.id, m);
  });
  const matches = Array.from(byId.values());

  const anyOk =
  pastR.status === 'fulfilled' ||
  futureR.status === 'fulfilled' ||
  extraR.status === 'fulfilled';

if ((!anyOk || matches.length === 0) && cache.data && cache.data.length > 0) {
  return cache.data;
}

if (anyOk) {
  cache = { data: matches, fetchedAt: now };
}
return matches;
  
function pickFixtures(allMatches) {
  const today = todayInNairobi();
  const now = new Date();
  const sevenDaysAgo = new Date(Date.now() - DAYS_BACK * 86400000);

  const isToday = (m) => dateInNairobi(new Date(m.utcDate)) === today;

  const todays = allMatches
    .filter((m) => isToday(m) || LIVE_STATUSES.includes(m.status))
    .filter((m) => m.status !== 'POSTPONED')
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

// ---------- Standings and top scorers (Hybrid Router) ----------
const tableCache = {};

function isEmptyPayload(data) {
  if (!data) return true;
  if (data.groups) return data.groups.every((g) => !g.table || g.table.length === 0);
  if (data.scorers) return data.scorers.length === 0;
  return true;
}

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

  const blockedAt = tableCache[cacheKey + ':blocked'];
  if (blockedAt && now - blockedAt < EXTRA_TABLE_TTL_MS) {
    const be = new Error('API-Football plan does not include this season (cached)');
    be.planBlocked = true;
    throw be;
  }

  try {
    const res = await axios.get(`https://v3.football.api-sports.io/${endpoint}`, {
      headers: { 'x-apisports-key': API_FOOTBALL_KEY },
      params,
      timeout: 20000,
    });

    if (hasApiErrors(res.data)) {
      const e = new Error('API-Football: ' + JSON.stringify(res.data.errors));
      e.planBlocked = Boolean(res.data.errors.plan);
      if (e.planBlocked) tableCache[cacheKey + ':blocked'] = now;
      throw e;
    }

    const data = mapper(res.data);
    if (!isEmptyPayload(data)) tableCache[cacheKey] = { data, at: now };
    return data;
  } catch (err) {
    if (cached) return cached.data;
    throw err;
  }
}

function sendTableError(res, label, err) {
  if (err.planBlocked) {
    console.error(`${label}: blocked by API-Football free plan`);
    return res.status(403).json({ error: 'Tables and scorers for this league need a paid API-Football plan' });
  }
  const status = err.response && err.response.status;
  const detail = err.response && err.response.data && err.response.data.message;
  console.error(`${label} failed:`, status || '', detail || err.message);
  if (status === 429) return res.status(503).json({ error: 'Rate limited, try again in a minute' });
  if (status === 403) return res.status(403).json({ error: 'Not available on current API plan' });
  return res.status(502).json({ error: 'Could not load data' });
}

app.get('/api/standings/:code', async (req, res) => {
  const code = String(req.params.code || '').toUpperCase();
  if (!ALL_COMPETITIONS.includes(code)) return res.status(400).json({ error: 'Unknown competition' });

  if (EXTRA_LEAGUES[code]) {
    if (!API_FOOTBALL_KEY) return res.status(503).json({ error: 'API-Football key not set' });
    const meta = EXTRA_LEAGUES[code];
    try {
      const data = await cachedApiFootballTable(
        `standings:${code}`,
        'standings',
        { league: meta.id, season: meta.season },
        (d) => {
          const standingsArrays =
            (d.response && d.response[0] && d.response[0].league && d.response[0].league.standings) || [];
          return {
            competition: meta.name,
            groups: standingsArrays.map((groupRows) => ({
              name: (groupRows[0] && groupRows[0].group) || '',
              table: groupRows.map((r) => ({
                position: r.rank,
                team: (r.team && r.team.name) || '',
                played: (r.all && r.all.played) || 0,
                won: (r.all && r.all.win) || 0,
                draw: (r.all && r.all.draw) || 0,
                lost: (r.all && r.all.lose) || 0,
                goalsFor: (r.all && r.all.goals && r.all.goals.for) || 0,
                goalsAgainst: (r.all && r.all.goals && r.all.goals.against) || 0,
                goalDifference: r.goalsDiff || 0,
                points: r.points || 0,
                form: r.form ? r.form.split('').join(',') : '',
              })),
            })),
          };
        }
      );
      return res.json(data);
    } catch (err) {
      return sendTableError(res, `API-Football Standings ${code}`, err);
    }
  }

  if (!FOOTBALL_DATA_TOKEN) return res.status(503).json({ error: 'Server token not set' });
  try {
    const data = await cachedFootballData(
      `standings:${code}`,
      `https://api.football-data.org/v4/competitions/${code}/standings`,
      {},
      (d) => ({
        competition: (d.competition && d.competition.name) || code,
        groups: (d.standings || []).map((st) => ({
          name: st.group ? st.group.replace(/_/g, ' ') : '',
          table: (st.table || []).map((row) => ({
            position: row.position,
            team: (row.team && (row.team.shortName || row.team.name)) || '',
            played: row.playedGames,
            won: row.won,
            draw: row.draw,
            lost: row.lost,
            goalsFor: row.goalsFor,
            goalsAgainst: row.goalsAgainst,
            goalDifference: row.goalDifference,
            points: row.points,
            form: row.form ? row.form.split('').join(',') : '',
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
  if (!ALL_COMPETITIONS.includes(code)) return res.status(400).json({ error: 'Unknown competition' });

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
          scorers: (d.response || []).slice(0, 20).map((item) => {
            const st = (item.statistics && item.statistics[0]) || {};
            return {
              player: (item.player && item.player.name) || '',
              name: (item.player && item.player.name) || '',
              team: (st.team && st.team.name) || '',
              goals: (st.goals && st.goals.total) || 0,
              assists: (st.goals && st.goals.assists) || 0,
              penalties: (st.penalty && st.penalty.scored) || 0,
              played: (st.games && st.games.appearences) || 0,
            };
          }),
        })
      );
      return res.json(data);
    } catch (err) {
      return sendTableError(res, `API-Football Scorers ${code}`, err);
    }
  }

  if (!FOOTBALL_DATA_TOKEN) return res.status(503).json({ error: 'Server token not set' });
  try {
    const data = await cachedFootballData(
      `scorers:${code}`,
      `https://api.football-data.org/v4/competitions/${code}/scorers`,
      { limit: 20 },
      (d) => ({
        competition: (d.competition && d.competition.name) || code,
        scorers: (d.scorers || []).map((s) => ({
          player: (s.player && s.player.name) || '',
          name: (s.player && s.player.name) || '',
          team: (s.team && (s.team.shortName || s.team.name)) || '',
          goals: s.goals || 0,
          assists: s.assists ?? 0,
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

app.get('/api/odds/:sport', async (req, res) => {
  const sport = req.params.sport || 'soccer_epl';
  if (!ODDS_API_KEY) {
    return res.status(503).json({ error: 'Odds API key not configured on server' });
  }

  const cacheKey = `odds:${sport}`;

  try {
    const data = await getCached(cacheKey, ODDS_CACHE_TTL_MS, async () => {
      const response = await axios.get(`https://api.the-odds-api.com/v4/sports/${sport}/odds/`, {
        params: {
          apiKey: ODDS_API_KEY,
          regions: 'eu,uk',
          markets: 'h2h',
          oddsFormat: 'decimal',
        },
        timeout: 15000,
      });
      return response.data;
    });

    return res.json(data);
  } catch (err) {
    console.error('Failed to fetch odds:', err.message);
    return res.status(502).json({ error: 'Could not fetch odds from provider' });
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
  if (!API_FOOTBALL_KEY) {
    return res.status(503).json({ error: 'API-Football key not set' });
  }

  const cacheKey = String(teamName).toLowerCase().trim();
  const cached = teamInsightsCache.get(cacheKey);
  if (cached && Date.now() - cached.timestamp < CACHE_DURATION_MS) {
    return res.json(cached.data);
  }

  try {
    const teamRes = await axios.get('https://v3.football.api-sports.io/teams', {
      headers: { 'x-apisports-key': API_FOOTBALL_KEY },
      params: { search: teamName },
      timeout: 15000,
    });
    const teamId =
      teamRes.data.response && teamRes.data.response[0] && teamRes.data.response[0].team
        ? teamRes.data.response[0].team.id
        : null;

    if (!teamId) {
      return res.json({ response: [] });
    }

    const injuriesRes = await axios.get('https://v3.football.api-sports.io/injuries', {
      headers: { 'x-apisports-key': API_FOOTBALL_KEY },
      params: { team: teamId, season: 2026 },
      timeout: 15000,
    });
    const injuriesData = injuriesRes.data;

    if (!hasApiErrors(injuriesData)) {
      teamInsightsCache.set(cacheKey, {
        timestamp: Date.now(),
        data: injuriesData,
      });
    }

    res.json(injuriesData);
  } catch (error) {
    console.error('Error fetching team insights:', error.message);
    res.status(500).json({ error: 'Failed to fetch team insights' });
  }
});

// ---------- User Access & Subscription Schema & Routes ----------
const userAccessSchema = new mongoose.Schema({
  phone: { type: String, required: true, unique: true, trim: true },
  name: { type: String, default: '' },
  pin: { type: String, default: '' },
  role: { type: String, enum: ['user', 'admin'], default: 'user' },
  waiverExpiry: { type: Date, required: true },
  subscriptionExpiry: { type: Date, default: null },
  lastMpesaReceipt: { type: String, default: '' },
}, { timestamps: true });

const UserAccess = mongoose.model('UserAccess', userAccessSchema);

const ADMIN_PHONES = ['254712489816'];

function normalizePhone(phone) {
  let cleaned = String(phone).replace(/\s+/g, '').replace(/^\+/, '');
  if (cleaned.startsWith('0')) cleaned = '254' + cleaned.slice(1);
  return cleaned;
}

// POST /api/access/check - Registers or logs in user, saves/syncs PIN, returns access status
app.post('/api/access/check', async (req, res) => {
  try {
    const rawPhone = req.body.phone;
    const name = req.body.name || '';
    const pin = req.body.pin ? String(req.body.pin).trim() : '';
    if (!rawPhone) return res.status(400).json({ error: 'Phone number required' });

    const phone = normalizePhone(rawPhone);
    const isAdminPhone = ADMIN_PHONES.includes(phone);

    let user = await UserAccess.findOne({ phone });

    if (!user) {
      const waiverExpiry = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000); // 7-day free waiver
      user = await UserAccess.create({
        phone,
        name,
        pin,
        role: isAdminPhone ? 'admin' : 'user',
        waiverExpiry,
      });
    } else {
      let modified = false;
      if (isAdminPhone && user.role !== 'admin') {
        user.role = 'admin';
        modified = true;
      }
      if (name && !user.name) {
        user.name = name;
        modified = true;
      }
      if (pin && !user.pin) {
        user.pin = pin;
        modified = true;
      }
      if (modified) await user.save();
    }

    const now = new Date();
    const isAdmin = user.role === 'admin';
    const inWaiver = now < user.waiverExpiry;
    const inSubscription = user.subscriptionExpiry && now < user.subscriptionExpiry;
    const hasAccess = isAdmin || inWaiver || inSubscription;

    const remainingWaiverDays = inWaiver
      ? Math.ceil((user.waiverExpiry - now) / (24 * 60 * 60 * 1000))
      : 0;

    res.json({
      hasAccess,
      isAdmin,
      inWaiver,
      remainingWaiverDays,
      waiverExpiry: user.waiverExpiry,
      subscriptionExpiry: user.subscriptionExpiry,
      pin: user.pin || '',
      name: user.name || '',
    });
  } catch (err) {
    console.error('Access check error:', err.message);
    res.status(500).json({ error: 'Server error checking access' });
  }
});

// POST /api/access/reset-pin - Verifies registered phone and updates PIN
app.post('/api/access/reset-pin', async (req, res) => {
  try {
    const { phone: rawPhone, newPin } = req.body;
    if (!rawPhone || !newPin || !/^\d{4}$/.test(String(newPin))) {
      return res.status(400).json({ error: 'Valid phone number and 4-digit PIN required' });
    }

    const phone = normalizePhone(rawPhone);
    const user = await UserAccess.findOne({ phone });

    if (!user) {
      return res.status(404).json({ error: 'No Bankroll Account found for this phone number' });
    }

    user.pin = String(newPin);
    await user.save();

    res.json({
      success: true,
      message: 'PIN updated successfully',
    });
  } catch (err) {
    console.error('Reset PIN error:', err.message);
    res.status(500).json({ error: 'Server error resetting PIN' });
  }
});

// POST /api/access/grant - Activates a subscription plan
app.post('/api/access/grant', async (req, res) => {
  try {
    const { phone: rawPhone, planType, mpesaReceipt } = req.body;
    if (!rawPhone) return res.status(400).json({ error: 'Phone number required' });

    const phone = normalizePhone(rawPhone);
    const daysMap = { daily: 1, weekly: 7, monthly: 30 };
    const daysToAdd = daysMap[planType] || 1;

    let user = await UserAccess.findOne({ phone });
    if (!user) {
      user = await UserAccess.create({
        phone,
        waiverExpiry: new Date(Date.now() - 1000),
      });
    }

    const baseTime = (user.subscriptionExpiry && user.subscriptionExpiry > new Date())
      ? user.subscriptionExpiry.getTime()
      : Date.now();

    user.subscriptionExpiry = new Date(baseTime + daysToAdd * 24 * 60 * 60 * 1000);
    if (mpesaReceipt) user.lastMpesaReceipt = mpesaReceipt;
    await user.save();

    res.json({
      success: true,
      hasAccess: true,
      subscriptionExpiry: user.subscriptionExpiry,
    });
  } catch (err) {
    console.error('Grant access error:', err.message);
    res.status(500).json({ error: 'Failed to update subscription' });
  }
});

// POST /api/access/make-admin - Upgrades user to admin via secret key 775067
app.post('/api/access/make-admin', async (req, res) => {
  try {
    const { phone: rawPhone, secretKey } = req.body;
    if (secretKey !== '775067') {
      return res.status(403).json({ error: 'Invalid secret key' });
    }
    if (!rawPhone) {
      return res.status(400).json({ error: 'Phone number required' });
    }

    const phone = normalizePhone(rawPhone);
    let user = await UserAccess.findOne({ phone });

    if (!user) {
      user = await UserAccess.create({
        phone,
        role: 'admin',
        waiverExpiry: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000),
      });
    } else {
      user.role = 'admin';
      await user.save();
    }

    res.json({
      success: true,
      message: 'User successfully upgraded to admin',
      isAdmin: true,
      hasAccess: true,
    });
  } catch (err) {
    console.error('Make admin error:', err.message);
    res.status(500).json({ error: 'Server error upgrading user' });
  }
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Server active on port ${PORT}`);
});
