// backend/services/apiFootballClient.js
const BASE_URL = 'https://v3.football.api-sports.io';

function resolveApiKey() {
  return (
    process.env.API_FOOTBALL_KEY ||
    process.env.API_FOOTBALL ||
    process.env.APIFOOTBALL_KEY ||
    process.env.APISPORTS_KEY ||
    process.env.API_SPORTS_KEY ||
    ''
  );
}

async function apiFootballGet(endpoint, params = {}, timeoutMs = 10000) {
  const apiKey = resolveApiKey();
  if (!apiKey) {
    const err = new Error('Missing API-Football key environment variable');
    err.statusCode = 500;
    throw err;
  }

  const normalizedEndpoint = endpoint.startsWith('/') ? endpoint : `/${endpoint}`;
  const url = new URL(`${BASE_URL}${normalizedEndpoint}`);

  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined && value !== null && value !== '') {
      url.searchParams.set(key, String(value));
    }
  }

  const res = await fetch(url.toString(), {
    method: 'GET',
    headers: {
      'x-apisports-key': apiKey,
      'Accept': 'application/json',
    },
    signal: AbortSignal.timeout(timeoutMs),
  });

  const text = await res.text();
  let json;
  try {
    json = JSON.parse(text);
  } catch {
    const err = new Error(`Invalid JSON from API-Football (HTTP ${res.status})`);
    err.statusCode = 502;
    throw err;
  }

  if (!res.ok) {
    const err = new Error(`API-Football HTTP ${res.status}: ${text}`);
    err.statusCode = res.status === 429 ? 429 : 502;
    throw err;
  }

  if (json.errors && !Array.isArray(json.errors) && Object.keys(json.errors).length > 0) {
    const err = new Error(`API-Football error: ${JSON.stringify(json.errors)}`);
    err.statusCode = 502;
    throw err;
  }

  return json.response ?? [];
}

module.exports = { apiFootballGet };
