const express = require('express');
const axios = require('axios');

const app = express();
const PORT = process.env.PORT || 10000;

const API_FOOTBALL_KEY = process.env.FOOTBALL_API_KEY;

app.get('/api/fixtures', async (req, res) => {
  try {
    if (!API_FOOTBALL_KEY) {
      console.error('Error: FOOTBALL_API_KEY is missing.');
      return res.status(500).json({ error: 'API key not configured', fixtures: [] });
    }

    const apiHeaders = {
      'x-apisports-key': API_FOOTBALL_KEY,
      'x-rapidapi-key': API_FOOTBALL_KEY,
      'x-rapidapi-host': 'v3.football.api-sports.io',
    };

    console.log('Fetching recent finished matches and upcoming fixtures from API-Football...');

    const [pastResponse, upcomingResponse] = await Promise.all([
      axios.get('https://v3.football.api-sports.io/fixtures', {
        headers: apiHeaders,
        params: { last: 15, timezone: 'Africa/Nairobi' },
        timeout: 15000,
      }),
      axios.get('https://v3.football.api-sports.io/fixtures', {
        headers: apiHeaders,
        params: { next: 15, timezone: 'Africa/Nairobi' },
        timeout: 15000,
      }),
    ]);

    const pastMatches = pastResponse.data.response || [];
    const upcomingMatches = upcomingResponse.data.response || [];
    const allMatches = [...pastMatches, ...upcomingMatches];

    console.log(`Successfully retrieved ${allMatches.length} total fixtures (${pastMatches.length} finished, ${upcomingMatches.length} upcoming).`);

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

      const homeGoals = item.goals.home ?? 0;
      const awayGoals = item.goals.away ?? 0;
      const scoreDisplay = isFinished || isCurrentlyLive ? `${homeGoals} - ${awayGoals}` : eatTime;

      return {
        league: item.league.name || 'Global League',
        time: scoreDisplay,
        homeTeam: item.teams.home.name || 'Home Team',
        awayTeam: item.teams.away.name || 'Away Team',
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
  console.log(`Server active on port ${PORT}`);
});
