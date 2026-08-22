import { createServer } from 'node:http';

import { closeServerResources, initializeServer, requestHandler } from './server.js';

const port = Number.parseInt(process.env.PORT ?? '8080', 10);
await initializeServer();

const server = createServer(requestHandler);
server.requestTimeout = 15_000;
server.headersTimeout = 20_000;
server.keepAliveTimeout = 5_000;
server.listen(port, '0.0.0.0', () => {
  console.log(`TIVUQIPTV license server listening on :${port}`);
});

async function shutdown() {
  server.close();
  await closeServerResources();
  process.exit(0);
}

process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
