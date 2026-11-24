# frontend

Static web client: HTML5 canvas (mouse + touch), WebSocket client implementing the protocol in `docs/architecture.md` §3, auto-reconnect with `lastSeq` replay, AI guesses panel, timer, scores, and the "AI busy — timer paused" banner.

Stack: TypeScript + Vite, built to static files and served by nginx (non-root). Tasks: P1-4, P1-5.
