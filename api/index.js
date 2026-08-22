import { requestHandler } from './server/src/server.js';

export default async function handler(req, res) {
  const originalPath = req.headers['x-matched-path'] || req.headers['x-vercel-matched-path'] || req.headers['x-forwarded-uri'] || req.headers['x-original-uri'];
  if (originalPath) {
    req.url = originalPath;
  }
  return requestHandler(req, res);
}
