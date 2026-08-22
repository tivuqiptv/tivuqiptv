import { requestHandler } from './server/src/server.js';

function nodeRequest(request, body) {
  return {
    method: request.method,
    url: new URL(request.url).pathname + new URL(request.url).search,
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
  if (res && typeof res.setHeader === 'function') {
    return requestHandler(req, res);
  }
  const request = req;
  const body = ['GET', 'HEAD'].includes(request.method)
    ? null
    : Buffer.from(await request.arrayBuffer());
  return invokeHandler(request, body);
}
