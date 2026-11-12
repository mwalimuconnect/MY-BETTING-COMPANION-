const express = require('express');
const axios = require('axios');

const app = express();
const PORT = process.env.PORT || 10000;

// Set this in Render -> Environment. Never put the token in the code or GitHub.
const FOOTBALL_DATA_TOKEN = process.env.FOOTBALL_DATA_TOKEN;

const TIMEZONE = 'Africa/Nairobi';
// Free tier allows 10 requests/minute; a 60s cache keeps us far below that.
const CACHE_TTL_MS = 60 * 1000;
const DAYS_BACK = 1;   // include yesterday (for late-night Nairobi matches)
const DAYS_AHEAD = 8;  // look this far ahead when today has no matches
const MAX_UPCOMING = 30;

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

// YYYY-MM-DD (UTC) for a date offset by N days from now.
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

// e.g. "Sat 15 Nov, 15:00 EAT" - used when showing matches from another day.
function formatEatDateTime(isoDate) {
  const day = new Date(isoDate).toLocaleDateString('en-GB', {
    weekday: 'short',
    day: 'numeric',
    month: 'short',
    timeZone: TIMEZONE,
  });
  return `${day}, ${formatEatTime(isoDate)}`;
}

function isProlific(homeTeam, awayTeam) {
  const h = homeTeam.toLowerCase();
  const a = awayTeam.toLowerCase();
  return PROLIFIC_TEAMS.some((t) => {
    const team = t.toLowerCase();
    return h.includes(team) || a.includes(team);
  });
}

// ---------- Sample data (last resort, only if the API has nothing at all) ----------
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
  const prolific = isProlific(homeTeam, awayTeam);

  const fullTime = (item.score && item.score.fullTime) || {};
  const homeGoals = fullTime.home ?? 0;
  const awayGoals = fullTime.away ?? 0;

  // The tip below is "Home Win or Draw", so it is correct when home >= away.
  const tipIsCorrect = homeGoals >= awayGoals;

  let time;
  if (isFinished || isLive) {
    time = `${homeGoals} - ${awayGoals}`;
  } else {
    time = showDate ? formatEatDateTime(item.utcDate) : formatEatTime(item.utcDate);
  }

  return {
    league: (item.competition && item.competition.name) || 'Global Competition',
    time,
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
let cache = { data: null, fetchedAt: 0 };

// Returns all matches from yesterday to a week or so ahead (one API call).
async function fetchMatchWindow() {
  const now = Date.now();
  if (cache.data && now - cache.fetchedAt < CACHE_TTL_MS) {
    return cache.data;
  }

  const response = await axios.get('https://api.football-data.org/v4/matches', {
    headers: { 'X-Auth-Token': FOOTBALL_DATA_TOKEN },
    params: {
      dateFrom: utcDateOffset(-DAYS_BACK),
      dateTo: utcDateOffset(DAYS_AHEAD),
    },
    timeout: 15000,
  });

  const available = response.headers['x-requests-available-minute'];
  const matches = response.data.matches || [];

  console.log(
    `football-data.org: ${matches.length} matches fetched` +
      (available !== undefined ? ` (requests left this minute: ${available})` : '')
  );

  cache = { data: matches, fetchedAt: now };
  return matches;
}

// Today's matches (Nairobi time); if there are none, the next upcoming ones.
function pickFixtures(allMatches) {
  const today = todayInNairobi();

  const todays = allMatches.filter((m) => dateInNairobi(new Date(m.utcDate)) === today);
  if (todays.length > 0) {
    console.log(`Showing ${todays.length} matches for ${today}`);
    return todays.map((m) => formatFixture(m, false));
  }

  const upcoming = allMatches
    .filter((m) => UPCOMING_STATUSES.includes(m.status) && new Date(m.utcDate) > new Date())
    .sort((a, b) => new Date(a.utcDate) - new Date(b.utcDate))
    .slice(0, MAX_UPCOMING);

  console.log(`No matches on ${today}; showing ${upcoming.length} upcoming matches`);
  return upcoming.map((m) => formatFixture(m, true));
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
      // Serve stale cache rather than nothing, if we have it.
      if (cache.data) matches = cache.data;
    }
  } else {
    console.warn('FOOTBALL_DATA_TOKEN is not set; serving sample fixtures.');
  }

  try {
    const fixtures = pickFixtures(matches);
    if (fixtures.length > 0) return res.json(fixtures);
  } catch (err) {
    console.error('Formatting error:', err.message);
  }

  console.warn('No fixtures available; serving sample fixtures.');
  return res.json(getSampleFixtures());
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Server active on port ${PORT}`);
});
