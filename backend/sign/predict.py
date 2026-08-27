"""
backend/sign/predict.py

Exposes predict(frame) — the single function Person 5's API layer calls
for POST /v1/sign/predict. Output matches the frozen contract exactly:

    {
      "token": "habari",
      "display_text": "Habari",
      "confidence": 0.91,
      "model_version": "sign-0.1.0",
      "accepted": true
    }

Below CONFIDENCE_THRESHOLD, accepted is False and the caller (Person 5's
API layer) is expected to surface the shared LOW_CONFIDENCE error shape:

    {
      "error": {
        "code": "LOW_CONFIDENCE",
        "message": "Sign could not be recognized confidently",
        "retryable": true
      }
    }
"""

import functools
import json
import os

import torch
from PIL import Image

from model import embed_image, DEFAULT_CLIP_MODEL

ARTIFACT_DIR = os.environ.get(
    "SIGN_MODEL_DIR",
    os.path.join(os.path.dirname(__file__), "..", "..", "models", "sign", "sign-0.1.0"),
)

# Below this cosine-similarity score, we do not trust the prediction.
# Tuned initially against the held-out val split in benchmark.py;
# revisit once real (non-placeholder) multi-signer data is available.
CONFIDENCE_THRESHOLD = 0.70


@functools.lru_cache(maxsize=1)
def _load_artifact(artifact_dir: str = ARTIFACT_DIR):
    weights_path = os.path.join(artifact_dir, "embeddings.pt")
    labels_path = os.path.join(artifact_dir, "labels.json")
    meta_path = os.path.join(artifact_dir, "meta.json")

    if not os.path.exists(weights_path):
        raise FileNotFoundError(
            f"No trained artifact found at {weights_path}. Run train.py first."
        )

    data = torch.load(weights_path, weights_only=True)
    with open(labels_path) as f:
        display_text_by_token = json.load(f)
    with open(meta_path) as f:
        meta = json.load(f)

    return data["tokens"], data["matrix"], display_text_by_token, meta


def predict(frame, artifact_dir: str = ARTIFACT_DIR, threshold: float = CONFIDENCE_THRESHOLD) -> dict:
    """
    frame: a PIL.Image (already-decoded JPEG frame from the multipart
           upload in POST /v1/sign/predict).

    Returns a dict matching the frozen sign-prediction contract exactly.
    """
    if not isinstance(frame, Image.Image):
        raise TypeError("predict() expects a PIL.Image; decode the upload before calling.")

    tokens, matrix, display_text_by_token, meta = _load_artifact(artifact_dir)

    query = embed_image(frame, model_name=meta["clip_backbone"])
    sims = matrix @ query  # cosine similarity since both sides are L2-normalized
    best_idx = int(torch.argmax(sims))
    best_token = tokens[best_idx]
    confidence = float(sims[best_idx])

    accepted = confidence >= threshold

    return {
        "token": best_token if accepted else None,
        "display_text": display_text_by_token.get(best_token) if accepted else None,
        "confidence": round(confidence, 4),
        "model_version": meta["model_version"],
        "accepted": accepted,
    }
