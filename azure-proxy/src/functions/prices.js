// ─────────────────────────────────────────────────────────────────────────────
// Azure Retail Prices — CORS proxy (Azure Functions, Node.js v4 model)
//
// WHY: prices.azure.com returns no Access-Control-Allow-Origin header, so the
// browser blocks the static estimator (GitHub Pages) from calling it directly.
// This HTTP-triggered Function fetches the pricing API server-side and re-serves
// it WITH CORS headers. It is locked to the Azure pricing host only, so it cannot
// be abused as an open proxy.
//
// Endpoint after deploy:  https://<appName>.azurewebsites.net/api/prices
// Usage from the app:     /api/prices?url=<encodeURIComponent(azure-pricing-url)>
//
// IMPORTANT: leave the Function App's platform CORS list EMPTY. If you configure
// allowed origins there, Azure handles CORS itself and ignores these code-level
// headers, which causes duplicate/blocked-header conflicts.
// ─────────────────────────────────────────────────────────────────────────────

const { app } = require('@azure/functions');

const ALLOWED_HOST = 'prices.azure.com';
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type'
};

app.http('prices', {
  methods: ['GET', 'OPTIONS'],
  authLevel: 'anonymous',
  route: 'prices',
  handler: async (request) => {
    // CORS preflight
    if (request.method === 'OPTIONS') {
      return { status: 204, headers: CORS };
    }

    const target = request.query.get('url');
    if (!target) return json({ error: "Missing 'url' query parameter" }, 400);

    let targetUrl;
    try {
      targetUrl = new URL(target);
    } catch {
      return json({ error: 'Invalid url' }, 400);
    }
    if (targetUrl.hostname !== ALLOWED_HOST) {
      return json({ error: 'Host not allowed: ' + targetUrl.hostname }, 403);
    }

    const upstream = await fetch(targetUrl.toString(), { headers: { Accept: 'application/json' } });
    const body = await upstream.text();
    return {
      status: upstream.status,
      body,
      headers: {
        ...CORS,
        'Content-Type': upstream.headers.get('Content-Type') || 'application/json',
        'Cache-Control': 'public, max-age=3600' // prices change slowly; cache 1h
      }
    };
  }
});

function json(obj, status) {
  return { status, body: JSON.stringify(obj), headers: { ...CORS, 'Content-Type': 'application/json' } };
}
