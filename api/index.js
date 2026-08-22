import { requestHandler } from '../src/server.js';

export default async function handler(req, res) {
  try {
    const originalPath = req.headers['x-matched-path'] || req.headers['x-vercel-matched-path'] || req.headers['x-forwarded-uri'] || req.headers['x-original-uri'];
    if (originalPath) {
      req.url = originalPath;
    }
    return await requestHandler(req, res);
  } catch (err) {
    console.error('Server error:', err);
    if (res && typeof res.writeHead === 'function') {
      res.writeHead(500, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ error: err.message, stack: err.stack }));
    }
  }
}
