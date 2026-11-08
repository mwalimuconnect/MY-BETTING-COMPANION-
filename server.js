const express = require('express');
const axios = require('axios');
const app = express();
const PORT = process.env.PORT || 3000;

const API_FOOTBALL_KEY = process.env.FOOTBALL_API_KEY;

app.get('/api/fixtures', async (req, res) => {
  try {
    const today = new Date().toISOString().split('T')[0];

    console.log(`Fetching fixtures for date: ${today} using API-Football...`);

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
    console.log(`API-Football returned ${matches.length} fixtures.`);

    const formattedFixtures = matches.map((item) => {
      const matchDate = new Date(item.fixture.date);
      const eatTime = matchDate.toLocaleTimeString('en-GB', {
        hour: '2-digit',
        minute: '2-digit',
        timeZone: 'Africa/Nairobi',
      }) + ' EAT';

      const statusShort = item.fixture.status.short;
      const isCurrentlyLive = ['1H', '2H', 'HT', 'ET', 'P', 'LIVE'].includes(statusShort);
      const isFinished = ['FT', 'AET', 'PEN'].includes(statusShort);

      // Extract scores if available
      const homeGoals = item.goals.home ?? 0;
      const awayGoals = item.goals.away ?? 0;
      const scoreDisplay = isFinished || isCurrentlyLive ? `${homeGoals} - ${awayGoals}` : eatTime;

      return {
        league: item.league.name,
        time: scoreDisplay,
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
        isFinished: isFinished,
        actualScore: isFinished ? `${homeGoals}-${awayGoals}` : 'Pending',
        predictionCorrect: isFinished ? (homeGoals >= awayGoals) : null, // Simulated outcome check
      };
    });

    res.json(formattedFixtures);
  } catch (error) {
    console.error('API-Football Error:', error.response?.data || error.message);
    res.status(500).json({ error: error.message, fixtures: [] });
  }
});

app.listen(PORT, () => {
  console.log(`Global API-Football server running on port ${PORT}`);
});
