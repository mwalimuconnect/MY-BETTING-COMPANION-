const express = require('express');
const axios = require('axios');
const app = express();
const PORT = process.env.PORT || 3000;

const API_FOOTBALL_KEY = process.env.FOOTBALL_API_KEY;

app.get('/api/fixtures', async (req, res) => {
  try {
    const today = new Date().toISOString().split('T')[0];

    console.log(`Fetching live & upcoming fixtures from API-Football...`);

    // Fetch today's fixtures with EAT timezone
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

    let matches = response.data.response || [];

    // If today's specific date is empty, fallback to fetching upcoming live/scheduled games globally
    if (matches.length === 0) {
      console.log('Today list empty, fetching next 20 upcoming global fixtures...');
      const fallbackResponse = await axios.get('https://v3.football.api-sports.io/fixtures', {
        headers: {
          'x-apisports-key': API_FOOTBALL_KEY,
        },
        params: {
          next: 20,
          timezone: 'Africa/Nairobi',
        },
        timeout: 15000,
      });
      matches = fallbackResponse.data.response || [];
    }

    console.log(`Successfully retrieved ${matches.length} matches from API-Football.`);

    const formattedFixtures = matches.map((item) => {
      const matchDate = new Date(item.fixture.date);
      const eatTime = matchDate.toLocaleTimeString('en-GB', {
        hour: '2-digit',
        minute: '2-digit',
        timeZone: 'Africa/Nairobi',
      }) + ' EAT';

      const statusShort = item.fixture.status.short;
      const isCurrentlyLive = ['1H', '2H', 'HT', 'ET', 'P', 'LIVE', 'INPLAY'].includes(statusShort);
      const isFinished = ['FT', 'AET', 'PEN'].includes(statusShort);

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
        homeWinProb: 50,
        drawProb: 28,
        awayWinProb: 22,
        over25Goals: '65%',
        btts: '58%',
        cardRisk: 'Medium',
        topTip: `${item.teams.home.name} Win or Draw`,
        odds: 1.80,
        isLive: isCurrentlyLive,
        isFinished: isFinished,
        actualScore: isFinished ? `${homeGoals}-${awayGoals}` : 'Pending',
        predictionCorrect: isFinished ? (homeGoals >= awayGoals) : null,
      };
    });

    res.json(formattedFixtures);
  } catch (error) {
    console.error('API-Football Fetch Error:', error.response?.data || error.message);
    res.status(500).json({ error: error.message, fixtures: [] });
  }
});

app.listen(PORT, () => {
  console.log(`Global API-Football server running on port ${PORT}`);
});
