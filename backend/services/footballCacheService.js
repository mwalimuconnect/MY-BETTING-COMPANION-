// backend/services/footballCacheService.js
const FootballCache = require('../models/FootballCache');

const inflightRequests = new Map();

/**
 * Fetches data using persistent MongoDB caching, concurrent request deduplication,
 * and automatic stale-cache fallback if the upstream fetcher fails.
 *
 * @param {object} opts
 * @param {string} opts.cacheKey - Unique cache identifier (e.g., "stats:12345:false")
 * @param {string} opts.endpoint - Upstream endpoint name (e.g., "/fixtures/statistics")
 * @param {number} opts.freshTtlMs - Milliseconds before cached data is considered stale
 * @param {number} [opts.staleRetentionMs] - Milliseconds to retain stale fallback data (default 7 days)
 * @param {() => Promise<any>} opts.fetcher - Async function returning fresh, normalized data
 */
async function getWithCache({
  cacheKey,
  endpoint,
  freshTtlMs,
  staleRetentionMs = 7 * 24 * 60 * 60 * 1000,
  fetcher,
}) {
  const now = new Date();
  let existing = null;

  try {
    existing = await FootballCache.findOne({ cacheKey }).lean();
    if (existing && new Date(existing.freshUntil) > now) {
      return {
        data: existing.payload,
        meta: {
          source: 'cache',
          stale: false,
          fetchedAt: existing.fetchedAt,
        },
      };
    }
  } catch (dbReadErr) {
    console.warn(`[footballCacheService] Cache read failed for ${cacheKey}:`, dbReadErr.message);
  }

  // Deduplicate simultaneous calls for the same cacheKey
  if (inflightRequests.has(cacheKey)) {
    return inflightRequests.get(cacheKey);
  }

  const task = (async () => {
    try {
      const freshData = await fetcher();
      const fetchedAt = new Date();
      const freshUntil = new Date(fetchedAt.getTime() + freshTtlMs);
      const expiresAt = new Date(fetchedAt.getTime() + staleRetentionMs);

      try {
        await FootballCache.findOneAndUpdate(
          { cacheKey },
          {
            $set: {
              endpoint,
              payload: freshData,
              fetchedAt,
              freshUntil,
              expiresAt,
            },
          },
          { upsert: true, new: true }
        );
      } catch (dbWriteErr) {
        console.warn(`[footballCacheService] Cache write failed for ${cacheKey}:`, dbWriteErr.message);
      }

      return {
        data: freshData,
        meta: {
          source: 'api-football',
          stale: false,
          fetchedAt,
        },
      };
    } catch (fetchErr) {
      if (existing && existing.payload !== undefined) {
        return {
          data: existing.payload,
          meta: {
            source: 'stale-cache',
            stale: true,
            fetchedAt: existing.fetchedAt,
            warning: fetchErr.message,
          },
        };
      }
      throw fetchErr;
    } finally {
      inflightRequests.delete(cacheKey);
    }
  })();

  inflightRequests.set(cacheKey, task);
  return task;
}

module.exports = { getWithCache };
