# ai-inference

Redis Streams worker (group `ai-workers` on `ai:snapshots`): load room strokes, rasterize to 28×28, run the ONNX CNN, publish top-3 `ai_guess` to `room:{id}`, `XACK`, clear `ai:pending:{room}`, refresh `ai:last_ok`, reclaim stuck entries with `XAUTOCLAIM`.

Stack: Python 3.12, ONNX Runtime (CPU), `redis`, `prometheus-client`. The word list is `categories.txt`. Tasks: P1-1, P1-3, P2-5.
