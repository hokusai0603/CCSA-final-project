# Demo Scenarios

Each scenario is run with the Grafana dashboard visible and at least two browser windows playing in the same room. Each must have a `make demo-<n>` target (implemented in `scripts/demo-<n>.sh`) that performs the action and prints the measured result.

| # | Scenario | Action | K8s capability shown | What the audience sees | Success criterion | Goal |
|---|---|---|---|---|---|---|
| 1 | One-command deploy | `make deploy ENV=dev` on a fresh cluster | Helm, namespaces, ConfigMap/Secret, StatefulSet + PVC | Pods go Running/Ready in order | All Ready, game playable | G1 |
| 2 | Kill a game-server pod | `kubectl delete pod` on the pod serving the room | Deployment self-healing, probes, stateless design | Brief "reconnecting…", canvas intact | Pod Ready < 30 s, reconnect < 5 s, 0 lost strokes | G2 |
| 3 | AI outage | scale ai-inference to 0 (bypassing KEDA) | Decoupling via queue, graceful degradation | Banner "AI busy — timer paused", drawing continues; AI resumes and guesses latest canvas | No points lost, no errors | G2 |
| 4 | Update during play | `helm upgrade` with a new image tag | Rolling update (`maxUnavailable: 0`), graceful shutdown | Version label in UI changes, round continues | `rounds_interrupted_total` unchanged | G3 |
| 5 | Load test | `make loadtest PLAYERS=200` | HPA | Replica graph rises then falls | fan-out p99 < 150 ms | G4 |
| 6 | AI from zero | `idle` profile, start a round | KEDA scale from 0 | AI pods 0 → 1 → n | Cold start measured and reported | G4 |
| 7 | Node maintenance | `kubectl drain` one agent node | PDB, topology spread | Pods move one by one | Available pods never below PDB | G3 |
| 8 | Bad release + rollback | deploy an image whose `/readyz` fails, then `helm rollback` | Readiness gating, rollback | New pods never receive traffic; rollback restores | Healthy < 60 s, no user-visible errors | G1 |
| 9 | Alerting | run scenario 3 and watch Alertmanager | PrometheusRule | `AIUnavailable` fires | Fires < 60 s | G5 |

Record every run: date, commit SHA, numbers, and a screenshot path, in the results table of `goals.md`.
