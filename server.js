const express = require('express');
const axios = require('axios');

const app = express();
const PORT = process.env.PORT || 10000;

// Manual CORS headers middleware
app.use((req, res, next) => {
  res.header('Access-Control-Allow-Origin', '*');
  res.header('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept');
  next();
});

// Welcome route for base URL
app.get('/', (req, res) => {
  res.send('My Betting Companion API is live! Endpoint: /api/fixtures');
});

const API_FOOTBALL_KEY = process.env.FOOTBALL_API_KEY;

// List of prolific teams for your global basket
const PROLIFIC_TEAMS = [
  'Manchester City', 'Arsenal', 'Real Madrid', 'Barcelona', 'Bayern Munich', 
  'Bayer Leverkusen', 'Inter', 'Atalanta', 'PSG', 'Liverpool', 'Borussia Dortmund'
];

app.get('/api/fixtures', async (req, res) => {
  try {
    if (!API_FOOTBALL_KEY) {
      console.error('CRITICAL: FOOTBALL_API_KEY environment variable is missing on Render.');
      return res.status(500).json({ error: 'API key not configured', fixtures: [] });
    }

    const apiHeaders = {
      'x-apisports-key': API_FOOTBALL_KEY,
      'x-rapidapi-key': API_FOOTBALL_KEY,
      'x-rapidapi-host': 'v3.football.api-sports.io',
    };

    // Get today's date in YYYY-MM-DD format
    const todayStr = new Date().toISOString().split('T')[0];
    console.log(`Fetching fixtures for date: ${todayStr} and live matches from API-Football...`);

    // Fetch today's matches and live matches using valid v3 parameters
    const [dateResponse, liveResponse] = await Promise.all([
      axios.get('https://v3.football.api-sports.io/fixtures', {
        headers: apiHeaders,
        params: { date: todayStr, timezone: 'Africa/Nairobi' },
        timeout: 15000,
      }),
      axios.get('https://v3.football.api-sports.io/fixtures', {
        headers: apiHeaders,
        params: { live: 'all', timezone: 'Africa/Nairobi' },
        timeout: 15000,
      }),
    ]);

    const dateMatches = dateResponse.data.response || [];
    const liveMatches = liveResponse.data.response || [];
    
    // Combine and deduplicate fixtures by ID
    const fixtureMap = new Map();
    [...dateMatches, ...liveMatches].forEach(item => {
      if (item.fixture && item.fixture.id) {
        fixtureMap.set(item.fixture.id, item);
      }
    });
    const allMatches = Array.from(fixtureMap.values());

    console.log(`Successfully retrieved ${allMatches.length} total fixtures.`);

    const formattedFixtures = allMatches.map((item) => {
      const matchDate = new Date(item.fixture.date);
      const eatTime = matchDate.toLocaleTimeString('en-GB', {
        hour: '2-digit',
        minute: '2-digit',
        timeZone: 'Africa/Nairobi',
      }) + ' EAT';

      const statusShort = item.fixture.status.short;
      const isCurrentlyLive = ['1H', '2H', 'HT', 'ET', 'P', 'LIVE', 'INPLAY'].includes(statusShort);
      const isFinished = ['FT', 'AET', 'PEN'].includes(statusShort);

      const homeTeam = item.teams.home.name || 'Home Team';
      const awayTeam = item.teams.away.name || 'Away Team';
      
      const isProlificMatch = PROLIFIC_TEAMS.some(team => 
        homeTeam.toLowerCase().includes(team.toLowerCase()) || 
        awayTeam.toLowerCase().includes(team.toLowerCase())
      );

      const homeGoals = item.goals.home ?? 0;
      const awayGoals = item.goals.away ?? 0;
      const scoreDisplay = isFinished || isCurrentlyLive ? `${homeGoals} - ${awayGoals}` : eatTime;

      return {
        league: item.league.name || 'Global League',
        time: scoreDisplay,
        homeTeam: homeTeam,
        awayTeam: awayTeam,
        homeForm: ['W', 'D', 'W', 'W', 'L'],
        awayForm: ['L', 'W', 'D', 'W', 'W'],
        homeWinProb: 50,
        drawProb: 28,
        awayWinProb: 22,
        over25Goals: isProlificMatch ? '88%' : '65%',
        btts: isProlificMatch ? '79%' : '58%',
        cardRisk: 'Medium',
        topTip: isProlificMatch ? 'Over 2.5 Goals & BTTS' : `${homeTeam} Win or Draw`,
        odds: isProlificMatch ? 2.10 : 1.80,
        isLive: isCurrentlyLive,
        isFinished: isFinished,
        actualScore: isFinished ? `${homeGoals}-${awayGoals}` : 'Pending',
        predictionCorrect: isFinished ? (homeGoals >= awayGoals) : null,
        isProlific: isProlificMatch,
      };
    });

    return res.json(formattedFixtures);
  } catch (error) {
    console.error('API-Football Error:', error.response?.data || error.message);
    return res.status(500).json({
      error: error.response?.data?.errors || error.message,
      fixtures: [],
    });
  }
});

app.listen(PORT, () => {
  console.log(`Server active successfully on port ${PORT}`);
});
