# Team plan

Three people, three lanes. Each lane owns a component **and** its operation on Kubernetes, including the live demos that show it, so every member presents part of the K8s story. The roadmap tags every task with its lane (`Owner: A/B/C`).

| Lane | Owns | Demos |
|---|---|---|
| **A — game-server** | `services/game-server/`, `tools/fake-ai/`, leads `contracts/` | 2 kill a pod · 4 rolling update · 8 bad release + rollback |
| **B — AI + frontend** | `services/ai-inference/` (+ `training/`), `services/frontend/`, `tools/mock-ws/`, dummy model | 3 AI outage · 6 AI from zero · 9 alerting |
| **C — platform** | `deploy/`, `loadtest/`, `scripts/`, `Makefile`, `.github/`, `services/stub/` | 1 one-command deploy · 5 load test · 7 node drain · 10 node failure |

Why this split: A is the critical path (P1-2, P2-3) and does nothing else. B's training mostly waits on compute, which leaves time for the frontend. C's work (stateful services, chart, KEDA install, monitoring, k6) does not need application code thanks to the stub image.

## Working in parallel

Nobody waits for another lane. Phase 0.5 produces the contracts and a fake for every cross-lane dependency; each lane develops against them and swaps in the real component later.

| Instead of waiting for… | develop against | owner of the fake |
|---|---|---|
| the game-server (frontend, k6) | `tools/mock-ws` | B |
| the AI worker (game-server) | `tools/fake-ai` | A |
| the trained model (AI worker) | dummy `model.onnx` | B |
| real images (chart, HPA, PDB, monitoring, demos) | `services/stub` | C (done) |

Contract tests keep the fakes honest: every service validates its inputs and outputs against `contracts/` in `make test`, so swapping a fake for the real component rarely breaks.

**Integration checkpoints** (weekly, never blocking: whatever is not real yet stays faked):

- **IC1**: Compose runs the real services; a full round is playable.
- **IC2**: real images on k3d; all pods Ready; playable through the Ingress.
- **IC3**: all 10 demos pass on a fresh cluster on the measurement machine.

## Rules

- **Directories**: change your own lane's directories freely. `contracts/` and `docs/` are shared: changes need the other two lanes' approval. A contract change updates the schema, the fixtures and the affected fakes together.
- **Git**: one short-lived branch per task and a pull request into `main`, so CI runs **before** the merge. Merge when CI is green; contract or docs changes also need the two approvals. Commit messages follow `AGENTS.md` §7 (`phase-N: <task id> <summary>`).
- **Machines**: develop on your own machine: Linux, or Windows through WSL2 (`docs/dev-setup.md`). Each machine has its own Docker, so cluster names and ports never clash.
- **Measurement machine**: every number in `goals.md` is recorded on **one** machine (the Linux lab host), and the live demo runs there. Run `make preflight-measure` first (`docs/host-environment.md` R4).
- **Definition of done**: `AGENTS.md` §8, plus your task's acceptance criteria verified by running them.
