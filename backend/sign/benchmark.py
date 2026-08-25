"""
backend/sign/benchmark.py

Evaluates predict() against the held-out val/test frames from Person 2's
manifest (frames never seen during train.py's prototype building), and
records accuracy + per-frame latency. This is the Day 1 baseline
publication and the accuracy/latency evidence required for definition
of done.

Usage:
    python benchmark.py --manifest ../../data/frame_manifest.json \
                         --split test
"""

import argparse
import json
import os
import time

from PIL import Image

from predict import predict, CONFIDENCE_THRESHOLD

ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def _resolve(path: str) -> str:
    return path if os.path.isabs(path) else os.path.join(ROOT_DIR, path)


def run_benchmark(manifest_path: str, split: str, threshold: float = CONFIDENCE_THRESHOLD):
    with open(_resolve(manifest_path)) as f:
        manifest = json.load(f)

    rows = [m for m in manifest if m["split"] == split]
    if not rows:
        raise ValueError(f"No rows found for split={split!r} in {manifest_path}")

    results = []
    latencies = []
    correct = 0
    accepted_count = 0

    for row in rows:
        image = Image.open(_resolve(row["frame_path"]))

        start = time.perf_counter()
        pred = predict(image, threshold=threshold)
        elapsed_ms = (time.perf_counter() - start) * 1000

        latencies.append(elapsed_ms)
        is_correct = pred["accepted"] and pred["token"] == row["token"]
        correct += int(is_correct)
        accepted_count += int(pred["accepted"])

        results.append({
            "frame_path": row["frame_path"],
            "true_token": row["token"],
            "predicted_token": pred["token"],
            "confidence": pred["confidence"],
            "accepted": pred["accepted"],
            "correct": is_correct,
            "latency_ms": round(elapsed_ms, 2),
        })

    n = len(rows)
    accuracy = correct / n
    acceptance_rate = accepted_count / n
    # accuracy computed only among frames the model chose to accept
    accuracy_when_accepted = (correct / accepted_count) if accepted_count else 0.0
    latencies.sort()
    p50 = latencies[len(latencies) // 2]
    p95 = latencies[int(len(latencies) * 0.95) - 1] if n > 1 else latencies[0]

    summary = {
        "split": split,
        "num_frames": n,
        "num_classes": len(set(r["token"] for r in rows)),
        "accuracy_overall": round(accuracy, 4),
        "acceptance_rate": round(acceptance_rate, 4),
        "accuracy_when_accepted": round(accuracy_when_accepted, 4),
        "latency_ms_p50": round(p50, 2),
        "latency_ms_p95": round(p95, 2),
        "latency_ms_mean": round(sum(latencies) / n, 2),
        "confidence_threshold": threshold,
    }

    return summary, results


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", default="data/frame_manifest.json",
                         help="Path relative to repo root (or absolute).")
    parser.add_argument("--split", default="test", choices=["val", "test"])
    parser.add_argument("--out", default=None,
                         help="Path to write full per-frame results JSON")
    args = parser.parse_args()

    summary, results = run_benchmark(args.manifest, args.split)

    print(json.dumps(summary, indent=2))

    out_path = args.out or f"benchmark_{args.split}_results.json"
    with open(out_path, "w") as f:
        json.dump({"summary": summary, "results": results}, f, indent=2)
    print(f"\nFull per-frame results written to {out_path}")


if __name__ == "__main__":
    main()
