const express = require('express');
const app = express();
const PORT = process.env.PORT || 3000;

app.get('/api/fixtures', (req, res) => {
  const fixtures = [
    {
      league: 'Premier League',
      time: '21:00 EAT',
      home_team: 'Chelsea',
      away_team: 'Aston Villa',
      home_form: ['W', 'W', 'D', 'W', 'L'],
      away_form: ['W', 'L', 'D', 'W', 'W'],
      home_win_prob: 54,
      draw_prob: 26,
      away_win_prob: 20,
      over_25_goals: '72%',
      btts: '68%',
      card_risk: 'Medium',
      top_tip: 'Over 2.5 Goals & BTTS - Yes'
    }
  ];
  res.json(fixtures);
});

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
