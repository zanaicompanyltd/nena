"""
backend/sign/model.py

Loads CLIP once and exposes a single shared instance for embedding
extraction. Avoids reloading the model on every predict() call, which
matters for latency in the /v1/sign/predict endpoint.
"""

import functools
import torch
import clip
from PIL import Image

DEFAULT_CLIP_MODEL = "ViT-B/32"


@functools.lru_cache(maxsize=1)
def get_clip(model_name: str = DEFAULT_CLIP_MODEL):
    """
    Load and cache the CLIP model + preprocessing transform.
    Cached with lru_cache so repeated calls are free after the first.
    """
    device = "cuda" if torch.cuda.is_available() else "cpu"
    model, preprocess = clip.load(model_name, device=device)
    model.eval()
    return model, preprocess, device


def embed_image(image: Image.Image, model_name: str = DEFAULT_CLIP_MODEL) -> torch.Tensor:
    """
    Convert a single PIL image into a normalized CLIP embedding vector.
    Accepts any RGB PIL.Image (already-decoded frame from the mobile client
    or extracted from a reference video).
    """
    model, preprocess, device = get_clip(model_name)
    with torch.no_grad():
        tensor = preprocess(image.convert("RGB")).unsqueeze(0).to(device)
        features = model.encode_image(tensor)
        features = features / features.norm(dim=-1, keepdim=True)
    return features.squeeze(0).cpu()


def embed_image_path(path: str, model_name: str = DEFAULT_CLIP_MODEL) -> torch.Tensor:
    """Convenience wrapper for embedding an image already saved to disk."""
    image = Image.open(path)
    return embed_image(image, model_name=model_name)
