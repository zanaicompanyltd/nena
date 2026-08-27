"""
backend/sign/train.py

Builds the few-shot reference embeddings database from Person 2's
dataset manifest (data/frame_manifest.json), using only the "train"
split so val/test frames stay held out for honest evaluation.

For each token, we average the CLIP embeddings of its train-split
frames into a single class prototype vector. At inference time,
predict() compares an incoming frame's embedding to every class
prototype via cosine similarity (nearest-centroid classification).

Usage:
    python train.py --manifest ../../data/frame_manifest.json \
                     --out ../../models/sign/sign-0.1.0
"""

import argparse
import hashlib
import json
import os
from collections import defaultdict

import torch

from model import embed_image_path, DEFAULT_CLIP_MODEL

MODEL_VERSION = "sign-0.1.0"

# Project root = two levels up from this file (backend/sign/train.py -> repo root).
# Used to resolve frame_path entries in the manifest regardless of the
# working directory the script is launched from, so this works the same
# on any machine / any checkout location.
ROOT_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def _resolve(path: str) -> str:
    return path if os.path.isabs(path) else os.path.join(ROOT_DIR, path)


def build_embeddings_db(manifest_path: str, model_name: str = DEFAULT_CLIP_MODEL):
    with open(_resolve(manifest_path)) as f:
        manifest = json.load(f)

    train_rows = [m for m in manifest if m["split"] == "train"]

    by_token = defaultdict(list)
    display_text_by_token = {}

    for row in train_rows:
        emb = embed_image_path(_resolve(row["frame_path"]), model_name=model_name)
        by_token[row["token"]].append(emb)
        display_text_by_token[row["token"]] = row["display_text"]

    prototypes = {}
    for token, embs in by_token.items():
        stacked = torch.stack(embs)
        proto = stacked.mean(dim=0)
        proto = proto / proto.norm()
        prototypes[token] = proto

    return prototypes, display_text_by_token, len(train_rows)


def save_artifact(prototypes, display_text_by_token, out_dir: str, model_name: str):
    os.makedirs(out_dir, exist_ok=True)

    tokens = sorted(prototypes.keys())
    matrix = torch.stack([prototypes[t] for t in tokens])

    weights_path = os.path.join(out_dir, "embeddings.pt")
    torch.save({"tokens": tokens, "matrix": matrix}, weights_path)

    labels_path = os.path.join(out_dir, "labels.json")
    with open(labels_path, "w") as f:
        json.dump(display_text_by_token, f, indent=2, ensure_ascii=False)

    meta = {
        "model_version": MODEL_VERSION,
        "clip_backbone": model_name,
        "num_classes": len(tokens),
        "tokens": tokens,
    }
    meta_path = os.path.join(out_dir, "meta.json")
    with open(meta_path, "w") as f:
        json.dump(meta, f, indent=2)

    checksum = hashlib.md5(open(weights_path, "rb").read()).hexdigest()
    with open(os.path.join(out_dir, "CHECKSUM.txt"), "w") as f:
        f.write(f"embeddings.pt md5: {checksum}\n")

    return weights_path, checksum


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", default="data/frame_manifest.json",
                         help="Path relative to repo root (or absolute).")
    parser.add_argument("--out", default="models/sign/sign-0.1.0",
                         help="Path relative to repo root (or absolute).")
    parser.add_argument("--model-name", default=DEFAULT_CLIP_MODEL)
    args = parser.parse_args()
    args.out = _resolve(args.out)

    print(f"Building embeddings from train split in {args.manifest} ...")
    prototypes, display_text_by_token, n_train = build_embeddings_db(
        args.manifest, model_name=args.model_name
    )
    print(f"Built {len(prototypes)} class prototypes from {n_train} train frames.")

    weights_path, checksum = save_artifact(
        prototypes, display_text_by_token, args.out, args.model_name
    )
    print(f"Saved artifact to {weights_path}")
    print(f"Checksum (md5): {checksum}")
    print("NOTE: do not commit this artifact to Git. Store it in artifact "
          "storage and record this checksum/version in docs.")


if __name__ == "__main__":
    main()
