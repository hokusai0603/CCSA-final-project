# training (offline, not deployed)

Download QuickDraw simplified drawings for the categories in `../categories.txt`, train a small CNN on 28×28 rasters, export `model.onnx` (< 5 MB, top-1 ≥ 80 %). Use the **same rasterization code** as the inference worker. Task: P1-1.
