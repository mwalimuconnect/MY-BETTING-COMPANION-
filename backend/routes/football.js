// backend/routes/football.js
const express = require('express');
const rateLimit = require('express-rate-limit');
const { apiFootballGet } = require('../services/apiFootballClient');
const { normalizeMatchStatistics } = require('../services/statsNormalizer');
const { getWithCache } = require('../services/footballCacheService');

const router = express.Router();

const footballLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  limit: 30, // max 30 requests per minute per client IP
  standardHeaders: 'draft-8',
  legacyHeaders: false,
  message: {
    ok: false,
    error: 'Too many requests. Please wait a moment and try again.',
  },
});

router.use(footballLimiter);

const FINISHED_STATUSES = new Set(['FT', 'AET', 'PEN']);
const LIVE_STATUSES = new Set(['1H', 'HT', '2H', 'ET', 'BT', 'P', 'LIVE']);

function getFixtureListTtl(fixtures = []) {
  if (!Array.isArray(fixtures) || fixtures.length === 0) {
    return 15 * 60 * 1000;
  }
  const hasLive = fixtures.some((f) => LIVE_STATUSES.has(f?.fixture?.status?.short));
  if (hasLive) return 2 * 60 * 1000; // 2 minutes during live matches

  const allFinished = fixtures.every((f) =>
    FINISHED_STATUSES.has(f?.fixture?.status?.short)
  );
  if (allFinished) return 24 * 60 * 60 * 1000; // 24 hours once all fixtures on that date are FT

  return 30 * 60 * 1000; // 30 minutes for upcoming fixtures
}

function getFixtureDetailTtl(statusShort) {
  if (FINISHED_STATUSES.has(statusShort)) {
    return 7 * 24 * 60 * 60 * 1000; // 7 days for finished matches
  }
  if (LIVE_STATUSES.has(statusShort)) {
    return 2 * 60 * 1000; // 2 minutes during live play
  }
  return 30 * 60 * 1000; // 30 minutes pre-match
}

// GET /api/football/fixtures?date=2026-11-23&league=39&season=2026
router.get('/fixtures', async (req, res) => {
  try {
    const { date, league, season, status } = req.query;
    const cacheKey = `fixtures:${date || 'all'}:${league || 'all'}:${season || 'all'}:${status || 'all'}`;

    const result = await getWithCache({
      cacheKey,
      endpoint: '/fixtures',
      freshTtlMs: 15 * 60 * 1000,
      fetcher: async () => {
        const rows = await apiFootballGet('/fixtures', { date, league, season, status });
        return {
          fixtures: rows,
          suggestedTtlMs: getFixtureListTtl(rows),
        };
      },
    });

    res.json({
      ok: true,
      data: Array.isArray(result.data) ? result.data : result.data.fixtures,
      meta: result.meta,
    });
  } catch (err) {
    res.status(err.statusCode || 502).json({ ok: false, error: err.message });
  }
});

// GET /api/football/fixtures/:id/stats?half=false&status=FT&includeTrends=false
router.get('/fixtures/:id/stats', async (req, res) => {
  try {
    const fixtureId = String(req.params.id).trim();
    const half = req.query.half === 'true' ? 'true' : 'false';
    const includeTrends = req.query.includeTrends === 'true';
    const statusShort = String(req.query.status || '').toUpperCase();
    const cacheKey = `stats:${fixtureId}:${half}:${includeTrends ? 'trends' : 'base'}`;

    const result = await getWithCache({
      cacheKey,
      endpoint: '/fixtures/statistics',
      freshTtlMs: getFixtureDetailTtl(statusShort),
      fetcher: async () => {
        const raw = await apiFootballGet('/fixtures/statistics', {
          fixture: fixtureId,
          ...(half === 'true' ? { half: 'true' } : {}),
        });

        let firstHalfStatsResponse = null;
        let eventsResponse = null;

        if (includeTrends && half === 'false') {
          firstHalfStatsResponse = await apiFootballGet('/fixtures/statistics', {
            fixture: fixtureId,
            half: 'true',
          });
          eventsResponse = await apiFootballGet('/fixtures/events', {
            fixture: fixtureId,
          });
        }

        return normalizeMatchStatistics(raw, {
          firstHalfStatsResponse,
          eventsResponse,
        });
      },
    });

    res.json({ ok: true, data: result.data, meta: result.meta });
  } catch (err) {
    res.status(err.statusCode || 502).json({ ok: false, error: err.message });
  }
});

// GET /api/football/fixtures/:id/events?status=FT
router.get('/fixtures/:id/events', async (req, res) => {
  try {
    const fixtureId = String(req.params.id).trim();
    const statusShort = String(req.query.status || '').toUpperCase();
    const cacheKey = `events:${fixtureId}`;

    const result = await getWithCache({
      cacheKey,
      endpoint: '/fixtures/events',
      freshTtlMs: getFixtureDetailTtl(statusShort),
      fetcher: () => apiFootballGet('/fixtures/events', { fixture: fixtureId }),
    });

    res.json({ ok: true, data: result.data, meta: result.meta });
  } catch (err) {
    res.status(err.statusCode || 502).json({ ok: false, error: err.message });
  }
});

// GET /api/football/fixtures/:id/lineups?status=FT
router.get('/fixtures/:id/lineups', async (req, res) => {
  try {
    const fixtureId = String(req.params.id).trim();
    const statusShort = String(req.query.status || '').toUpperCase();
    const cacheKey = `lineups:${fixtureId}`;

    const result = await getWithCache({
      cacheKey,
      endpoint: '/fixtures/lineups',
      freshTtlMs: getFixtureDetailTtl(statusShort),
      fetcher: () => apiFootballGet('/fixtures/lineups', { fixture: fixtureId }),
    });

    res.json({ ok: true, data: result.data, meta: result.meta });
  } catch (err) {
    res.status(err.statusCode || 502).json({ ok: false, error: err.message });
  }
});

module.exports = router;
