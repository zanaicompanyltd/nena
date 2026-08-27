import subprocess, os, json, sys

with open("data/labeled_inventory.json") as f:
    manifest = json.load(f)

FRAMES_PER_VIDEO = 12
split_manifest = []

for m in manifest:
    path = os.path.join("data/raw", m["file"])
    token = m["token"]
    out_dir = os.path.join("data/frames", token)
    os.makedirs(out_dir, exist_ok=True)

    duration = m["duration_sec"]
    if duration <= 0:
        continue
    step = duration / (FRAMES_PER_VIDEO + 1)
    timestamps = [round(step * (i + 1), 3) for i in range(FRAMES_PER_VIDEO)]

    saved = []
    for i, ts in enumerate(timestamps):
        fname = f"{token}_{i:02d}.jpg"
        fpath = os.path.join(out_dir, fname)
        if os.path.exists(fpath) and os.path.getsize(fpath) > 0:
            saved.append({"frame_path": fpath, "order": i})
            continue
        cmd = ["ffmpeg", "-y", "-ss", str(ts), "-i", path, "-frames:v", "1", "-q:v", "2", fpath]
        r = subprocess.run(cmd, capture_output=True, timeout=15)
        if os.path.exists(fpath) and os.path.getsize(fpath) > 0:
            saved.append({"frame_path": fpath, "order": i})

    n = len(saved)
    train_end = max(1, int(n * 0.6))
    val_end = max(train_end + 1, int(n * 0.8))
    for i, s in enumerate(saved):
        split = "train" if i < train_end else ("val" if i < val_end else "test")
        split_manifest.append({
            "token": token, "display_text": m["display_text"], "source_video": m["file"],
            "sample_id": m["sample_id"], "frame_path": s["frame_path"], "order": s["order"], "split": split
        })
    print(token, "->", n, "frames", flush=True)

with open("data/frame_manifest.json", "w") as f:
    json.dump(split_manifest, f, indent=2)

print("DONE", len(split_manifest), "frames total", flush=True)
