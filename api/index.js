import { requestHandler } from '../src/server.js';

function nodeRequest(request, body) {
  const urlObj = new URL(request.url, 'http://localhost');
  return {
    method: request.method,
    url: urlObj.pathname + urlObj.search,
    headers: Object.fromEntries(request.headers.entries()),
    body,
    socket: { remoteAddress: null },
  };
}

function invokeHandler(request, body) {
  return new Promise((resolve, reject) => {
    let status = 200;
    const headers = new Headers();
    let ended = false;
    const response = {
      setHeader(name, value) {
        headers.set(name, String(value));
      },
      writeHead(statusCode, values = {}) {
        status = statusCode;
        for (const [name, value] of Object.entries(values)) {
          headers.set(name, String(value));
        }
      },
      end(payload = null) {
        if (ended) return;
        ended = true;
        resolve(new Response(payload, { status, headers }));
      },
    };
    Promise.resolve(requestHandler(nodeRequest(request, body), response)).catch(reject);
  });
}

export default async function handler(req, res) {
  try {
    if (res && typeof res.setHeader === 'function') {
      const originalPath = req.headers['x-matched-path'] || req.headers['x-vercel-matched-path'] || req.headers['x-forwarded-uri'] || req.headers['x-original-uri'];
      if (originalPath) {
        req.url = originalPath;
      }
      return await requestHandler(req, res);
    }
    const request = req;
    const body = ['GET', 'HEAD'].includes(request.method)
      ? null
      : Buffer.from(await request.arrayBuffer());
    return await invokeHandler(request, body);
  } catch (err) {
    console.error('Server error in Vercel handler:', err);
    if (res && typeof res.writeHead === 'function') {
      res.writeHead(500, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ error: err.message || 'Internal Server Error' }));
    } else {
      return new Response(JSON.stringify({ error: err.message || 'Internal Server Error' }), {
        status: 500,
        headers: { 'content-type': 'application/json' }
      });
    }
  }
}
