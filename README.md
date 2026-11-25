# DrawGuess — CCSA Final Project

[![CI](https://github.com/hokusai0603/CCSA-final-project/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/hokusai0603/CCSA-final-project/actions/workflows/ci.yml)

A multiplayer collaborative drawing game where a small AI model guesses what the players are drawing. Built on **Docker + Kubernetes** to demonstrate **stability, availability, and accessibility** for the *Cloud Computing and System Architecture* term project.

多人協作畫圖遊戲：玩家一起作畫，由小型 AI 模型猜畫的內容，猜中即得分。本專案的重點不在遊戲規模，而是展示我們能**管理 Kubernetes 並維運一個遊戲服務**：自我修復、零停機更新、自動擴展、可觀測性與優雅降級，每一項都能現場示範並有實測數據。

## Architecture at a glance

```
Players (browser / mobile)
        │  HTTPS / WSS
        ▼
Ingress (Traefik) ── TLS · WebSocket · rate limiting
        │
        ├──► frontend (nginx, static files)
        │
        └──► game-server × N  (Node.js, WebSocket, stateless, HPA)
                 │
     ┌───────────┼──────────────────────┐
     ▼           ▼                      ▼
  Redis       PostgreSQL         Redis Stream "ai:snapshots"
  state ·     players ·                 │
  Pub/Sub     scores                    ▼
     ▲                           ai-inference × N  (Python, ONNX CNN, KEDA)
     └──────── guesses published back to the room ┘
```

Full design: [`docs/architecture.md`](docs/architecture.md)

## Project goals

| # | Goal | Example target |
|---|---|---|
| 1 | Cluster management | One-command deploy; rollback < 1 min |
| 2 | Self-healing | Killed pod recovers < 30 s; players reconnect < 5 s with no lost strokes |
| 3 | Zero-downtime operations | Rolling update and node drain during play: 0 dropped games |
| 4 | Elasticity | 200 simulated players trigger HPA scale-out and scale-in; KEDA scales AI from queue length |
| 5 | Observability | Live Grafana dashboard; alert fires < 1 min after a failure |

Details: [`docs/goals.md`](docs/goals.md) · Demo script (10 scenarios): [`docs/demo-scenarios.md`](docs/demo-scenarios.md)

## For AI coding agents

Start with [`AGENTS.md`](AGENTS.md), then take the next task in your lane from [`docs/roadmap.md`](docs/roadmap.md). Lanes, ownership and how the team works in parallel: [`docs/team-plan.md`](docs/team-plan.md).

## Quick start (once Phase 1–2 tasks are implemented)

```bash
make help              # list all targets
make preflight         # host checks (docs/host-environment.md); fix any FAIL first
make cluster-up        # 4-node local k3d cluster with simulated zones
make keda monitoring   # KEDA + Prometheus/Grafana
make build deploy ENV=dev
```

Setup for Linux and Windows (WSL2): [`docs/dev-setup.md`](docs/dev-setup.md) (`make tools` installs the pinned toolchain). Prerequisites: Docker, k3d ≥ 5.9, kubectl 1.36–1.38 (the cluster runs k3s 1.37), Helm 3, k6, Node.js 24 (`nvm use` reads `.nvmrc`), Python 3.12. None needs root; on a shared host, read [`docs/host-environment.md`](docs/host-environment.md) first.

## Repository layout

```
services/   frontend · game-server · ai-inference (+ training)
deploy/     k3d cluster · Helm chart · monitoring
loadtest/   k6 scripts
docs/       architecture · goals · demo scenarios · roadmap · decisions · runbook
```
