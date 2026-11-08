const express = require('express');
const app = express();
const PORT = process.env.PORT || 3000;

app.get('/api/fixtures', (req, res) => {
  const fixtures = [
    // --- EUROPE (Premier League) ---
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
    },
    // --- AFRICA (CAF Champions League / Premier League) ---
    {
      league: 'CAF Champions League',
      time: '16:00 EAT',
      home_team: 'Al Ahly',
      away_team: 'Mamelodi Sundowns',
      home_form: ['W', 'W', 'W', 'D', 'W'],
      away_form: ['W', 'D', 'W', 'W', 'L'],
      home_win_prob: 48,
      draw_prob: 30,
      away_win_prob: 22,
      over_25_goals: '55%',
      btts: '50%',
      card_risk: 'High',
      top_tip: 'Under 2.5 Goals'
    },
    // --- SOUTH AMERICA (Copa Libertadores) ---
    {
      league: 'Copa Libertadores',
      time: '03:00 EAT',
      home_team: 'Flamengo',
      away_team: 'River Plate',
      home_form: ['W', 'D', 'W', 'W', 'W'],
      away_form: ['L', 'W', 'W', 'D', 'W'],
      home_win_prob: 52,
      draw_prob: 28,
      away_win_prob: 20,
      over_25_goals: '65%',
      btts: '60%',
      card_risk: 'High',
      top_tip: 'Home Win & Over 1.5'
    },
    // --- NORTH AMERICA (MLS - USA) ---
    {
      league: 'MLS',
      time: '02:30 EAT',
      home_team: 'Inter Miami',
      away_team: 'LA Galaxy',
      home_form: ['W', 'W', 'L', 'W', 'W'],
      away_form: ['D', 'W', 'L', 'W', 'D'],
      home_win_prob: 60,
      draw_prob: 20,
      away_win_prob: 20,
      over_25_goals: '85%',
      btts: '78%',
      card_risk: 'Low',
      top_tip: 'Inter Miami Win & Over 2.5'
    },
    // --- ASIA (AFC Champions League) ---
    {
      league: 'AFC Champions League',
      time: '19:00 EAT',
      home_team: 'Al Hilal',
      away_team: 'Al Nassr',
      home_form: ['W', 'W', 'W', 'W', 'D'],
      away_form: ['W', 'L', 'W', 'W', 'W'],
      home_win_prob: 45,
      draw_prob: 28,
      away_win_prob: 27,
      over_25_goals: '75%',
      btts: '70%',
      card_risk: 'Medium',
      top_tip: 'BTTS - Yes'
    }
  ];
  
  res.json(fixtures);
});

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
