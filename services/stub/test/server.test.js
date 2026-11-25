import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { WebSocket } from 'ws';

const SERVER = new URL('../src/server.js', import.meta.url).pathname;

// Start the stub on a random port; resolves once it logs "listening".
async function start(env = {}) {
  const proc = spawn(process.execPath, [SERVER], {
    env: { ...process.env, PORT: '0', SHUTDOWN_DELAY_MS: '300', ...env },
    stdio: ['ignore', 'pipe', 'inherit'],
  });
  const logs = [];
  let buf = '';
  const port = await new Promise((resolve, reject) => {
    proc.stdout.on('data', (chunk) => {
      buf += chunk;
      let i;
      while ((i = buf.indexOf('\n')) >= 0) {
        const line = JSON.parse(buf.slice(0, i)); // every line must be JSON
        buf = buf.slice(i + 1);
        logs.push(line);
        if (line.msg === 'listening') resolve(line.port);
      }
    });
    proc.on('exit', (code) => reject(new Error(`exited early with ${code}`)));
  });
  const base = `http://127.0.0.1:${port}`;
  return { proc, logs, port, base, get: (p) => fetch(base + p) };
}

const stop = async (s) => {
  if (s.proc.exitCode === null) {
    s.proc.kill('SIGTERM');
    await once(s.proc, 'exit');
  }
};
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function openWs(port) {
  const ws = new WebSocket(`ws://127.0.0.1:${port}/ws`);
  const messages = [];
  ws.on('message', (d) => messages.push(JSON.parse(d.toString())));
  return { ws, messages, opened: once(ws, 'open') };
}

test('probes and identity', async (t) => {
  const s = await start({ COMPONENT: 'game-server', VERSION: 'v7' });
  t.after(() => stop(s));
  assert.equal((await s.get('/healthz')).status, 200);
  assert.equal((await s.get('/readyz')).status, 200);
  const id = await (await s.get('/')).json();
  assert.equal(id.component, 'game-server');
  assert.equal(id.version, 'v7');
  assert.equal((await s.get('/nope')).status, 404);
});

test('READY_DELAY_MS delays readiness but not liveness', async (t) => {
  const s = await start({ READY_DELAY_MS: '600' });
  t.after(() => stop(s));
  assert.equal((await s.get('/readyz')).status, 503);
  assert.equal((await s.get('/healthz')).status, 200);
  await sleep(700);
  assert.equal((await s.get('/readyz')).status, 200);
});

test('FAIL_READY=1 never becomes ready (bad release, demo 8)', async (t) => {
  const s = await start({ FAIL_READY: '1' });
  t.after(() => stop(s));
  const r = await s.get('/readyz');
  assert.equal(r.status, 503);
  assert.equal((await r.json()).reason, 'FAIL_READY=1');
  assert.equal((await s.get('/healthz')).status, 200);
});

test('metrics expose the architecture §8 names per component', async (t) => {
  const gs = await start({ COMPONENT: 'game-server' });
  const ai = await start({ COMPONENT: 'ai-inference' });
  t.after(() => Promise.all([stop(gs), stop(ai)]));
  const gsText = await (await gs.get('/metrics')).text();
  for (const name of [
    'drawguess_ws_connections',
    'drawguess_rooms_active',
    'drawguess_stroke_fanout_seconds_bucket',
    'drawguess_reconnects_total',
    'drawguess_rounds_interrupted_total',
    'drawguess_ai_circuit_open',
  ]) assert.match(gsText, new RegExp(`^${name}`, 'm'), name);
  assert.match(gsText, /drawguess_stub_info\{component="game-server",version="dev"\} 1/);
  const aiText = await (await ai.get('/metrics')).text();
  for (const name of ['drawguess_ai_inference_seconds_bucket', 'drawguess_ai_snapshots_processed_total', 'drawguess_ai_queue_pending'])
    assert.match(aiText, new RegExp(`^${name}`, 'm'), name);
  assert.doesNotMatch(aiText, /drawguess_ws_connections/);
});

test('WebSocket echo and live connection gauge', async (t) => {
  const s = await start({ COMPONENT: 'game-server' });
  t.after(() => stop(s));
  const c = openWs(s.port);
  await c.opened;
  c.ws.send(JSON.stringify({ type: 'stroke', points: [[0.1, 0.2]] }));
  await sleep(100);
  assert.deepEqual(c.messages[0].type, 'hello');
  assert.deepEqual(c.messages[1], { type: 'stroke', points: [[0.1, 0.2]] });
  assert.match(await (await s.get('/metrics')).text(), /^drawguess_ws_connections 1$/m);
  c.ws.close();
});

test('SIGTERM: readiness drops, clients told to reconnect, clean exit', async () => {
  const s = await start({ SHUTDOWN_DELAY_MS: '500' });
  const c = openWs(s.port);
  await c.opened;
  const t0 = Date.now();
  s.proc.kill('SIGTERM');
  await sleep(100);
  assert.equal((await s.get('/readyz')).status, 503, 'not ready while draining');
  assert.equal((await s.get('/healthz')).status, 200, 'still alive while draining');
  const [code] = await once(s.proc, 'exit');
  assert.equal(code, 0);
  assert.ok(Date.now() - t0 >= 450, 'waited for the drain delay');
  assert.ok(c.messages.some((m) => m.type === 'reconnect' && m.reason === 'shutdown'));
  assert.ok(s.logs.some((l) => l.msg === 'shutdown complete'));
});

test('CRASH_AFTER_MS exits non-zero', async () => {
  const s = await start({ CRASH_AFTER_MS: '200' });
  const [code] = await once(s.proc, 'exit');
  assert.equal(code, 1);
  assert.ok(s.logs.some((l) => l.level === 'error' && l.msg === 'crashing on purpose'));
});

test('/burn busy-loops for the requested time', async (t) => {
  const s = await start();
  t.after(() => stop(s));
  const t0 = Date.now();
  const body = await (await s.get('/burn?ms=150')).json();
  assert.equal(body.burnedMs, 150);
  assert.ok(Date.now() - t0 >= 150);
});

test('/burn does not starve probes, and is capped at 4 concurrent', async (t) => {
  const s = await start();
  t.after(() => stop(s));
  const burns = [1, 2, 3, 4].map(() => s.get('/burn?ms=1000'));
  await sleep(100);
  const t0 = Date.now();
  assert.equal((await s.get('/healthz')).status, 200);
  assert.equal((await s.get('/readyz')).status, 200);
  assert.ok(Date.now() - t0 < 200, `probes answered in ${Date.now() - t0} ms while burning`);
  assert.equal((await s.get('/burn?ms=10')).status, 429, 'fifth concurrent burn rejected');
  for (const r of await Promise.all(burns)) assert.equal(r.status, 200);
});
