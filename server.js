const express = require('express');
const axios = require('axios');

const app = express();
const PORT = process.env.PORT || 10000;
const API_FOOTBALL_KEY = process.env.FOOTBALL_API_KEY;

const TIMEZONE = 'Africa/Nairobi';
const CACHE_TTL_MS = 60 * 1000; // reuse API-Football results for 60s

const PROLIFIC_TEAMS = [
  'Angola', 'South Sudan', 'Uganda', 'Botswana', 'Algeria', 'Togo',
  'Manchester City', 'Arsenal', 'Real Madrid', 'Barcelona', 'France', 'Brazil',
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
  res.json({ ok: true, hasApiKey: Boolean(API_FOOTBALL_KEY) });
});

// ---------- Helpers ----------
// Today's date in Nairobi time (YYYY-MM-DD), not UTC.
function todayInNairobi() {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: TIMEZONE,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date());
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

function isProlific(homeTeam, awayTeam) {
  const h = homeTeam.toLowerCase();
  const a = awayTeam.toLowerCase();
  return PROLIFIC_TEAMS.some((t) => {
    const team = t.toLowerCase();
    return h.includes(team) || a.includes(team);
  });
}

// ---------- Sample data (used only when the live API gives nothing) ----------
// Every item is flagged isSample: true so the app can label it.
function getSampleFixtures() {
  const base = {
    isLive: false,
    isFinished: false,
    actualScore: 'Pending',
    predictionCorrect: null,
    isSample: true,
    isEstimate: false,
  };

  return [
    {
      ...base,
      league: 'Africa Cup of Nations Qualification',
      time: '20:00 EAT',
      homeTeam: 'Angola',
      awayTeam: 'South Sudan',
      homeForm: ['W', 'D', 'W', 'W', 'L'],
      awayForm: ['L', 'D', 'L', 'W', 'D'],
      homeWinProb: 65,
      drawProb: 22,
      awayWinProb: 13,
      over25Goals: '70%',
      btts: '50%',
      cardRisk: 'Medium',
      topTip: 'Angola Win',
      odds: 1.55,
      isProlific: true,
    },
    {
      ...base,
      league: 'Africa Cup of Nations Qualification',
      time: '20:00 EAT',
      homeTeam: 'Uganda',
      awayTeam: 'Botswana',
      homeForm: ['W', 'W', 'D', 'L', 'W'],
      awayForm: ['D', 'L', 'W', 'L', 'D'],
      homeWinProb: 58,
      drawProb: 26,
      awayWinProb: 16,
      over25Goals: '60%',
      btts: '45%',
      cardRisk: 'Medium',
      topTip: 'Uganda Win or Draw',
      odds: 1.4,
      isProlific: true,
    },
    {
      ...base,
      league: 'Africa Cup of Nations Qualification',
      time: '20:00 EAT',
      homeTeam: 'Algeria',
      awayTeam: 'Togo',
      homeForm: ['W', 'W', 'W', 'D', 'W'],
      awayForm: ['L', 'W', 'D', 'L', 'W'],
      homeWinProb: 72,
      drawProb: 18,
      awayWinProb: 10,
      over25Goals: '78%',
      btts: '55%',
      cardRisk: 'High',
      topTip: 'Algeria Win & Over 1.5',
      odds: 1.72,
      isProlific: true,
    },
    {
      ...base,
      league: 'International Friendlies',
      time: '15:00 EAT',
      homeTeam: 'Vietnam',
      awayTeam: 'Chinese Taipei',
      homeForm: ['W', 'D', 'L', 'W', 'L'],
      awayForm: ['L', 'L', 'D', 'L', 'W'],
      homeWinProb: 60,
      drawProb: 25,
      awayWinProb: 15,
      over25Goals: '65%',
      btts: '50%',
      cardRisk: 'Low',
      topTip: 'Vietnam Win',
      odds: 1.65,
      isProlific: false,
    },
  ];
}

// ---------- Live data mapping ----------
function formatFixture(item) {
  const statusShort = item.fixture.status.short;
  const isLive = ['1H', '2H', 'HT', 'ET', 'BT', 'P', 'LIVE', 'INT'].includes(statusShort);
  const isFinished = ['FT', 'AET', 'PEN'].includes(statusShort);

  const homeTeam = item.teams.home.name || 'Home Team';
  const awayTeam = item.teams.away.name || 'Away Team';
  const prolific = isProlific(homeTeam, awayTeam);

  const homeGoals = item.goals.home ?? 0;
  const awayGoals = item.goals.away ?? 0;

  // The tip below is "Home Win or Draw", so it is correct when home >= away.
  const tipIsCorrect = homeGoals >= awayGoals;

  return {
    league: item.league.name || 'Global Competition',
    time: isFinished || isLive ? `${homeGoals} - ${awayGoals}` : formatEatTime(item.fixture.date),
    homeTeam,
    awayTeam,
    // NOTE: the fields below are placeholder estimates, not real predictions.
    homeForm: ['W', 'D', 'W', 'W', 'L'],
    awayForm: ['L', 'W', 'D', 'W', 'W'],
    homeWinProb: 50,
    drawProb: 28,
    awayWinProb: 22,
    over25Goals: prolific ? '75%' : '60%',
    btts: '55%',
    cardRisk: 'Medium',
    topTip: `${homeTeam} Win or Draw`,
    odds: 1.75,
    isLive,
    isFinished,
    actualScore: isFinished ? `${homeGoals}-${awayGoals}` : 'Pending',
    predictionCorrect: isFinished ? tipIsCorrect : null,
    isProlific: prolific,
    isSample: false,
    isEstimate: true, // stats/odds are placeholders until real endpoints are wired in
  };
}

// ---------- Cache ----------
let cache = { date: null, data: null, fetchedAt: 0 };

async function fetchLiveFixtures(dateStr) {
  const now = Date.now();
  if (cache.date === dateStr && cache.data && now - cache.fetchedAt < CACHE_TTL_MS) {
    return cache.data;
  }

  const response = await axios.get('https://v3.football.api-sports.io/fixtures', {
    headers: { 'x-apisports-key': API_FOOTBALL_KEY },
    params: { date: dateStr, timezone: TIMEZONE },
    timeout: 15000,
  });

  // API-Football often answers HTTP 200 with an "errors" field (bad key,
  // quota used up, plan limits) and an empty "response". Log it.
  const errors = response.data.errors;
  const hasErrors =
    errors && (Array.isArray(errors) ? errors.length > 0 : Object.keys(errors).length > 0);
  if (hasErrors) {
    console.error('API-Football errors:', JSON.stringify(errors));
  }
  console.log('API-Football results:', response.data.results, 'for', dateStr);

  const matches = response.data.response || [];
  cache = { date: dateStr, data: matches, fetchedAt: now };
  return matches;
}

// ---------- Route ----------
app.get('/api/fixtures', async (req, res) => {
  let matches = [];

  if (API_FOOTBALL_KEY) {
    try {
      matches = await fetchLiveFixtures(todayInNairobi());
    } catch (err) {
      console.error('API-Football request failed:', err.message);
      // Serve stale cache rather than nothing, if we have it.
      if (cache.data) matches = cache.data;
    }
  } else {
    console.warn('FOOTBALL_API_KEY is not set; serving sample fixtures.');
  }

  if (matches.length === 0) {
    console.warn('No live fixtures available; serving sample fixtures.');
    return res.json(getSampleFixtures());
  }

  try {
    return res.json(matches.map(formatFixture));
  } catch (err) {
    console.error('Formatting error:', err.message);
    return res.json(getSampleFixtures());
  }
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Server active on port ${PORT}`);
});
