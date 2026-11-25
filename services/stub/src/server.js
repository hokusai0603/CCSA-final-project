// Stub service: behaves like a DrawGuess service from Kubernetes' point of view
// (probes, metrics, WebSocket, graceful shutdown) with no game logic. Used as a
// placeholder image until the real services exist, and as the bad release in demo 8.
// Configuration (env): see services/stub/README.md.
import http from 'node:http';
import os from 'node:os';
import { Worker } from 'node:worker_threads';
import { WebSocketServer } from 'ws';

// /burn spins in a worker thread: blocking the main event loop would starve the
// probes, and Kubernetes would mark the pod unready or restart it (seen in k3d).
const BURN_WORKER = `
  const { workerData, parentPort } = require('node:worker_threads');
  const until = Date.now() + workerData;
  while (Date.now() < until);
  parentPort.postMessage(workerData);
`;
const MAX_CONCURRENT_BURNS = 4;
let activeBurns = 0;

const env = process.env;
const int = (v, d) => (v === undefined || v === '' ? d : Number.parseInt(v, 10));

const cfg = {
  port: int(env.PORT, 8080),
  component: env.COMPONENT ?? 'generic',
  version: env.VERSION ?? 'dev',
  readyDelayMs: int(env.READY_DELAY_MS, 0),
  failReady: env.FAIL_READY === '1',
  crashAfterMs: int(env.CRASH_AFTER_MS, 0),
  shutdownDelayMs: int(env.SHUTDOWN_DELAY_MS, 2000),
};
const pod = os.hostname();
const startedAt = Date.now();
let shuttingDown = false;
const clients = new Set();
const requests = new Map(); // path -> count

// AGENTS.md rule 9: one JSON object per line on stdout.
function log(level, msg, fields = {}) {
  const line = { ts: new Date().toISOString(), level, msg, pod, component: cfg.component, version: cfg.version, ...fields };
  process.stdout.write(`${JSON.stringify(line)}\n`);
}

function readiness() {
  if (shuttingDown) return { ready: false, reason: 'shutting down' };
  if (cfg.failReady) return { ready: false, reason: 'FAIL_READY=1' };
  const left = cfg.readyDelayMs - (Date.now() - startedAt);
  if (left > 0) return { ready: false, reason: `starting, ready in ${left} ms` };
  return { ready: true };
}

// Placeholder series with the names from docs/architecture.md §8, so dashboards,
// ServiceMonitors and alert rules can be built before the real services exist.
const histogram = (name, help) =>
  [`# HELP ${name} ${help}`, `# TYPE ${name} histogram`, `${name}_bucket{le="+Inf"} 0`, `${name}_sum 0`, `${name}_count 0`];
const gauge = (name, help, value = 0) => [`# HELP ${name} ${help}`, `# TYPE ${name} gauge`, `${name} ${value}`];
const counter = (name, help, value = 0) => [`# HELP ${name} ${help}`, `# TYPE ${name} counter`, `${name} ${value}`];

function metrics() {
  const lines = [
    '# HELP drawguess_stub_info Stub service identity (value is always 1).',
    '# TYPE drawguess_stub_info gauge',
    `drawguess_stub_info{component="${cfg.component}",version="${cfg.version}"} 1`,
    '# HELP drawguess_stub_http_requests_total HTTP requests served by path.',
    '# TYPE drawguess_stub_http_requests_total counter',
    ...[...requests].map(([path, n]) => `drawguess_stub_http_requests_total{path="${path}"} ${n}`),
  ];
  if (cfg.component === 'game-server') {
    lines.push(
      ...gauge('drawguess_ws_connections', 'Open WebSocket connections.', clients.size),
      ...gauge('drawguess_rooms_active', 'Active rooms (stub: always 0).'),
      ...histogram('drawguess_stroke_fanout_seconds', 'Stroke receive-to-forward latency (stub: empty).'),
      ...counter('drawguess_reconnects_total', 'Client reconnects (stub: always 0).'),
      ...counter('drawguess_rounds_interrupted_total', 'Interrupted rounds (stub: always 0).'),
      ...gauge('drawguess_ai_circuit_open', 'AI circuit breaker open (stub: always 0).'),
    );
  } else if (cfg.component === 'ai-inference') {
    lines.push(
      ...histogram('drawguess_ai_inference_seconds', 'Inference latency (stub: empty).'),
      ...counter('drawguess_ai_snapshots_processed_total', 'Snapshots processed (stub: always 0).'),
      ...gauge('drawguess_ai_queue_pending', 'AI queue backlog (stub: always 0).'),
    );
  }
  return `${lines.join('\n')}\n`;
}

function send(res, status, body, type = 'application/json') {
  res.writeHead(status, { 'content-type': type });
  res.end(type === 'application/json' ? JSON.stringify(body) : body);
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://stub');
  requests.set(url.pathname, (requests.get(url.pathname) ?? 0) + 1);
  switch (url.pathname) {
    case '/healthz':
      return send(res, 200, 'ok\n', 'text/plain');
    case '/readyz': {
      const r = readiness();
      return send(res, r.ready ? 200 : 503, r);
    }
    case '/metrics':
      return send(res, 200, metrics(), 'text/plain; version=0.0.4');
    case '/burn': {
      // Burn CPU to drive HPA without a load test. Capped at 5 s and 4 at a time.
      const ms = Math.min(Math.max(int(url.searchParams.get('ms') ?? undefined, 100), 0), 5000);
      if (activeBurns >= MAX_CONCURRENT_BURNS) return send(res, 429, { error: 'too many concurrent burns', pod });
      activeBurns += 1;
      const worker = new Worker(BURN_WORKER, { eval: true, workerData: ms });
      worker.once('message', () => send(res, 200, { burnedMs: ms, pod }));
      worker.once('error', (err) => send(res, 500, { error: String(err) }));
      worker.once('exit', () => { activeBurns -= 1; });
      return undefined;
    }
    case '/':
      return send(res, 200, { component: cfg.component, version: cfg.version, pod, ...readiness() });
    default:
      return send(res, 404, { error: 'not found' });
  }
});

// WebSocket echo on /ws: first message is {"type":"hello"}, then every message is echoed.
const wss = new WebSocketServer({ noServer: true });
server.on('upgrade', (req, socket, head) => {
  const { pathname } = new URL(req.url, 'http://stub');
  if (pathname !== '/ws' || shuttingDown) {
    socket.end('HTTP/1.1 503 Service Unavailable\r\n\r\n');
    return;
  }
  wss.handleUpgrade(req, socket, head, (ws) => {
    clients.add(ws);
    ws.on('close', () => clients.delete(ws));
    ws.on('message', (data, isBinary) => ws.send(data, { binary: isBinary }));
    ws.send(JSON.stringify({ type: 'hello', pod, version: cfg.version }));
  });
});

// AGENTS.md rule 3: on SIGTERM stop being ready, tell clients to reconnect, keep
// serving probes for SHUTDOWN_DELAY_MS (so the endpoint is removed first), then exit.
function shutdown(signal) {
  if (shuttingDown) return;
  shuttingDown = true;
  log('info', 'shutdown started', { signal, clients: clients.size, drainMs: cfg.shutdownDelayMs });
  for (const ws of clients) {
    ws.send(JSON.stringify({ type: 'reconnect', reason: 'shutdown' }));
    ws.close(1012, 'service restart');
  }
  setTimeout(() => {
    server.close(() => {
      log('info', 'shutdown complete');
      process.exit(0);
    });
    server.closeAllConnections();
  }, cfg.shutdownDelayMs).unref();
  // Hard stop well before terminationGracePeriodSeconds (30 s).
  setTimeout(() => process.exit(0), 25_000).unref();
}
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

if (cfg.crashAfterMs > 0) {
  setTimeout(() => {
    log('error', 'crashing on purpose', { crashAfterMs: cfg.crashAfterMs });
    process.exit(1);
  }, cfg.crashAfterMs);
}

server.listen(cfg.port, () => {
  // Actual port last: with PORT=0 the OS picks one, and cfg.port would say 0.
  log('info', 'listening', { ...cfg, port: server.address().port });
});
