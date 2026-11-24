# game-server

Stateless WebSocket server: rooms, strokes with `seq`, Redis Pub/Sub fan-out, room-owner lease and timer, snapshot enqueueing with coalescing, AI circuit breaker, scoring to PostgreSQL, `/healthz` `/readyz` `/metrics`, graceful shutdown.

Stack: Node.js 24 LTS + TypeScript, `ws`, `ioredis`, `pg`, `prom-client`. Tasks: P1-2, P2-3, P2-4, P2-5.
