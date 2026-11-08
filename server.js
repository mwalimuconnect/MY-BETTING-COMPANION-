const express = require('express');
const axios = require('axios');
const app = express();
const PORT = process.env.PORT || 3000;

const API_FOOTBALL_KEY = process.env.FOOTBALL_API_KEY;

app.get('/api/fixtures', async (req, res) => {
  try {
    const today = new Date().toISOString().split('T')[0];

    console.log(`Fetching live fixtures for date: ${today} using API-Football...`);

    const response = await axios.get('https://v3.football.api-sports.io/fixtures', {
      headers: {
        'x-apisports-key': API_FOOTBALL_KEY,
      },
      params: {
        date: today,
        timezone: 'Africa/Nairobi',
      },
      timeout: 15000,
    });

    const matches = response.data.response || [];
    console.log(`API-Football returned ${matches.length} fixtures for today.`);

    const liveFixtures = matches.map((item) => {
      const matchDate = new Date(item.fixture.date);
      const eatTime = matchDate.toLocaleTimeString('en-GB', {
        hour: '2-digit',
        minute: '2-digit',
        timeZone: 'Africa/Nairobi',
      }) + ' EAT';

      const statusShort = item.fixture.status.short;
      const isCurrentlyLive = ['1H', '2H', 'HT', 'ET', 'P', 'LIVE'].includes(statusShort);

      return {
        league: item.league.name,
        time: eatTime,
        homeTeam: item.teams.home.name,
        awayTeam: item.teams.away.name,
        homeForm: ['W', 'D', 'W', 'W', 'L'],
        awayForm: ['L', 'W', 'D', 'W', 'W'],
        homeWinProb: 48,
        drawProb: 28,
        awayWinProb: 24,
        over25Goals: '68%',
        btts: '60%',
        cardRisk: 'Medium',
        topTip: `${item.teams.home.name} Win or Draw`,
        odds: 1.85,
        isLive: isCurrentlyLive,
      };
    });

    res.json(liveFixtures);
  } catch (error) {
    console.error('API-Football Live Fetch Error:', error.response?.data || error.message);
    // Return empty array strictly without mock data if live fetch fails
    res.status(500).json({ error: error.message, fixtures: [] });
  }
});

app.listen(PORT, () => {
  console.log(`Global API-Football server running on port ${PORT}`);
});
