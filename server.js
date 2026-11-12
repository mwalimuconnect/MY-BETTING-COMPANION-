const express = require('express');
const axios = require('axios');

const app = express();
const PORT = process.env.PORT || 10000;

const FOOTBALL_DATA_TOKEN = process.env.FOOTBALL_DATA_TOKEN;
const TIMEZONE = 'Africa/Nairobi';
const CACHE_TTL_MS = 60 * 1000;
const DAYS_BACK = 7;
const DAYS_AHEAD = 8;
const MAX_UPCOMING = 40;
const MAX_FINISHED = 40;

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
  res.json({ ok: true, hasApiKey: Boolean(FOOTBALL_DATA_TOKEN) });
});

// ---------- Helpers ----------
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

  const homeProlific = isProlificTeam(homeTeam);
  const awayProlific = isProlificTeam(awayTeam);
  const prolific = homeProlific || awayProlific;

  const fullTime = (item.score && item.score.fullTime) || {};
  const homeGoals = fullTime.home ?? 0;
  const awayGoals = fullTime.away ?? 0;

  // Smart tip & outcome evaluation based on which team is in the Prolific Basket
  let topTip = `${homeTeam} Win or Draw`;
  let homeWinProb = 50;
  let drawProb = 28;
  let awayWinProb = 22;
  let odds = 1.65;
  let tipIsCorrect = homeGoals >= awayGoals;

  if (awayProlific && !homeProlific) {
    topTip = `${awayTeam} Win or Draw`;
    homeWinProb = 24;
    drawProb = 26;
    awayWinProb = 50;
    odds = 1.72;
    tipIsCorrect = awayGoals >= homeGoals;
  } else if (homeProlific && awayProlific) {
    topTip = 'Both Teams to Score';
    homeWinProb = 38;
    drawProb = 27;
    awayWinProb = 35;
    odds = 1.80;
    tipIsCorrect = homeGoals > 0 && awayGoals > 0;
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
    league: (item.competition && item.competition.name) || 'Global Competition',
    time,
    homeTeam,
    awayTeam,
    homeForm: ['W', 'D', 'W', 'W', 'L'],
    awayForm: ['L', 'W', 'D', 'W', 'W'],
    homeWinProb,
    drawProb,
    awayWinProb,
    over25Goals: prolific ? '72%' : '58%',
    btts: homeProlific && awayProlific ? '68%' : '52%',
    cardRisk: 'Medium',
    topTip,
    odds,
    isLive,
    isFinished,
    actualScore: isFinished ? `${homeGoals}-${awayGoals}` : 'Pending',
    predictionCorrect: isFinished ? tipIsCorrect : null,
    isProlific: prolific,
    isSample: false,
    isEstimate: true,
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

// ---------- Route ----------
app.get('/api/fixtures', async (req, res) => {
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
});
