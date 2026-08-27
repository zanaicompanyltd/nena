"""
╔══════════════════════════════════════════════════════════════════════╗
║                  NENA — Sign-to-Swahili Voice App                   ║
║         Multimodal Contrastive Framework · TSL/KSL Edition          ║
║                                                                      ║
║  USAGE: Paste each cell into Google Colab (GPU runtime).             ║
║  Requires: Runtime → Change runtime type → T4 GPU                   ║
╚══════════════════════════════════════════════════════════════════════╝

STAGE OVERVIEW
--------------
  Cell 1 — Install dependencies
  Cell 2 — Imports & GPU check
  Cell 3 — CLIP model loader
  Cell 4 — Swahili sign vocabulary (placeholder — replace with real TSL data)
  Cell 5 — CLIP embedding pipeline
  Cell 6 — Few-shot sign classifier
  Cell 7 — TTS voice router (Male / Female Swahili neural voice)
  Cell 8 — Full end-to-end demo
  Cell 9 — Webcam / video file inference loop
  Cell 10 — Save checkpoint & push to GitHub instructions
"""

# ═══════════════════════════════════════════════════════════════
# CELL 1 — Install dependencies
# ═══════════════════════════════════════════════════════════════
# Paste into a new Colab cell and run first.

"""
!pip install -q open-clip-torch torch torchvision Pillow
!pip install -q google-cloud-texttospeech
!pip install -q opencv-python-headless
!pip install -q gtts playsound
!apt-get -qq install ffmpeg
"""

# ═══════════════════════════════════════════════════════════════
# CELL 2 — Imports & GPU check
# ═══════════════════════════════════════════════════════════════

import torch
import open_clip
import numpy as np
from PIL import Image
import cv2
import os
import json
from pathlib import Path
from typing import Optional

# Check GPU availability
device = "cuda" if torch.cuda.is_available() else "cpu"
print(f"✅ Device: {device}")
if device == "cuda":
    print(f"   GPU: {torch.cuda.get_device_name(0)}")
    print(f"   VRAM: {torch.cuda.get_device_properties(0).total_memory / 1e9:.1f} GB")
else:
    print("⚠️  No GPU detected. Go to Runtime → Change runtime type → T4 GPU")


# ═══════════════════════════════════════════════════════════════
# CELL 3 — Load CLIP model
# ═══════════════════════════════════════════════════════════════

print("Loading CLIP model… (first run downloads ~350 MB)")

model, _, preprocess = open_clip.create_model_and_transforms(
    "ViT-B-32",
    pretrained="laion2b_s34b_b79k"   # Strong multilingual pretraining
)
model = model.to(device).eval()
tokenizer = open_clip.get_tokenizer("ViT-B-32")

print("✅ CLIP ViT-B/32 loaded.")


# ═══════════════════════════════════════════════════════════════
# CELL 4 — Swahili sign vocabulary
#
# This is your PROTOTYPE vocabulary.
# Each entry = one sign concept with:
#   - swahili_text  : what gets spoken aloud
#   - description   : English description of the sign gesture
#                     (used to build CLIP text prototypes)
#   - reference_img : path to a reference image (None = text-only prototype)
#
# HOW TO EXPAND:
#   1. Record 5–10 video clips of each sign.
#   2. Extract key frames → save as JPG.
#   3. Add the frame paths to reference_img lists.
#   4. Run Cell 5 to rebuild embeddings.
# ═══════════════════════════════════════════════════════════════

VOCABULARY = [
    {
        "id": "habari",
        "swahili_text": "Habari",
        "description": "A person waving hello with an open right hand raised beside the face",
        "reference_img": None,
    },
    {
        "id": "asante",
        "swahili_text": "Asante",
        "description": "A person touching the chin with fingertips then moving the hand forward as a thank you sign",
        "reference_img": None,
    },
    {
        "id": "ndiyo",
        "swahili_text": "Ndiyo",
        "description": "A person nodding the head and showing a thumbs up sign for yes",
        "reference_img": None,
    },
    {
        "id": "hapana",
        "swahili_text": "Hapana",
        "description": "A person shaking the head and waving an index finger side to side for no",
        "reference_img": None,
    },
    {
        "id": "tafadhali",
        "swahili_text": "Tafadhali",
        "description": "A person pressing both palms together in a prayer position for please",
        "reference_img": None,
    },
    {
        "id": "maji",
        "swahili_text": "Maji",
        "description": "A person shaping the hand into the letter W and touching the chin for water",
        "reference_img": None,
    },
    {
        "id": "chakula",
        "swahili_text": "Chakula",
        "description": "A person bringing a flat hand to the mouth repeatedly to sign food or eating",
        "reference_img": None,
    },
    {
        "id": "msaada",
        "swahili_text": "Msaada",
        "description": "A person placing a closed fist on an open palm and lifting both hands up to sign help",
        "reference_img": None,
    },
    {
        "id": "jina_langu",
        "swahili_text": "Jina langu ni",
        "description": "A person pointing to their chest with one finger to indicate their own name or identity",
        "reference_img": None,
    },
    {
        "id": "kwaheri",
        "swahili_text": "Kwaheri",
        "description": "A person waving goodbye with all fingers extended and the hand moving side to side",
        "reference_img": None,
    },
]

print(f"✅ Vocabulary loaded: {len(VOCABULARY)} signs")


# ═══════════════════════════════════════════════════════════════
# CELL 5 — Build text prototype embeddings (few-shot setup)
#
# For each sign we create a CLIP text embedding from its
# English description. When you have real images, this cell
# also averages in visual embeddings for stronger prototypes.
# ═══════════════════════════════════════════════════════════════

def build_prototypes(vocabulary: list, model, tokenizer, preprocess, device: str) -> dict:
    """
    Returns a dict: sign_id → normalised prototype embedding (1, D).
    Uses text descriptions now; merges image embeddings when available.
    """
    prototypes = {}

    with torch.no_grad():
        for sign in vocabulary:
            embeddings = []

            # --- Text prototype ---
            # Wrap description in prompt templates for more robust matching
            prompts = [
                sign["description"],
                f"A sign language gesture: {sign['description']}",
                f"Tanzanian sign language sign meaning {sign['swahili_text']}: {sign['description']}",
            ]
            tokens = tokenizer(prompts).to(device)
            text_feats = model.encode_text(tokens)            # (3, D)
            text_feats = text_feats / text_feats.norm(dim=-1, keepdim=True)
            embeddings.append(text_feats.mean(dim=0, keepdim=True))  # (1, D)

            # --- Image prototype (if reference frames exist) ---
            if sign["reference_img"]:
                img_paths = sign["reference_img"]
                if isinstance(img_paths, str):
                    img_paths = [img_paths]
                img_feats_list = []
                for p in img_paths:
                    if Path(p).exists():
                        img = preprocess(Image.open(p).convert("RGB")).unsqueeze(0).to(device)
                        feat = model.encode_image(img)
                        feat = feat / feat.norm(dim=-1, keepdim=True)
                        img_feats_list.append(feat)
                if img_feats_list:
                    img_feats = torch.cat(img_feats_list, dim=0).mean(dim=0, keepdim=True)
                    embeddings.append(img_feats)

            # Average all sources into a single prototype
            proto = torch.cat(embeddings, dim=0).mean(dim=0, keepdim=True)
            proto = proto / proto.norm(dim=-1, keepdim=True)
            prototypes[sign["id"]] = proto

    print(f"✅ Built {len(prototypes)} prototype embeddings.")
    return prototypes


PROTOTYPES = build_prototypes(VOCABULARY, model, tokenizer, preprocess, device)

# Quick embedding dimension check
sample_key = list(PROTOTYPES.keys())[0]
print(f"   Embedding dim: {PROTOTYPES[sample_key].shape[-1]}")


# ═══════════════════════════════════════════════════════════════
# CELL 6 — Few-shot sign classifier
# ═══════════════════════════════════════════════════════════════

VOCAB_LOOKUP = {sign["id"]: sign["swahili_text"] for sign in VOCABULARY}

def embed_frame(frame_bgr: np.ndarray, model, preprocess, device: str) -> torch.Tensor:
    """
    Takes an OpenCV BGR frame, returns a normalised CLIP image embedding (1, D).
    """
    rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
    pil_img = Image.fromarray(rgb)
    tensor = preprocess(pil_img).unsqueeze(0).to(device)
    with torch.no_grad():
        feat = model.encode_image(tensor)
        feat = feat / feat.norm(dim=-1, keepdim=True)
    return feat


def classify_sign(
    frame_bgr: np.ndarray,
    prototypes: dict,
    model,
    preprocess,
    device: str,
    threshold: float = 0.20,       # Cosine similarity threshold; lower = more lenient
) -> tuple[Optional[str], float]:
    """
    Classifies a single video frame against all prototype embeddings.

    Returns:
        (sign_id, confidence) if match found above threshold, else (None, score).
    """
    query = embed_frame(frame_bgr, model, preprocess, device)   # (1, D)

    best_id, best_score = None, -1.0
    for sign_id, proto in prototypes.items():
        score = (query @ proto.T).item()    # Cosine similarity ∈ [-1, 1]
        if score > best_score:
            best_score = score
            best_id = sign_id

    if best_score < threshold:
        return None, best_score

    return best_id, best_score


# ═══════════════════════════════════════════════════════════════
# CELL 7 — TTS Voice Router
#
# Implements the "Profile Mode" from the architecture document:
#   Profile Alpha → Male Swahili voice (sw-TZ-Standard-B)
#   Profile Beta  → Female Swahili voice (sw-TZ-Standard-A)
#
# Two backends available:
#   Backend A: Google Cloud TTS (needs GOOGLE_APPLICATION_CREDENTIALS)
#   Backend B: gTTS (free, no API key, Swahili supported)
# ═══════════════════════════════════════════════════════════════

from gtts import gTTS
import tempfile

# ---- User profile state (mirrors the app settings layer) ----
USER_PROFILE = {
    "voice": "Female",          # <-- Change to "Male" or "Female"
    "speed": 1.0,
    "language": "sw",           # Swahili BCP-47
}

VOICE_MAP = {
    # Google Cloud TTS voice IDs (used when GCP backend is active)
    "Male":   "sw-TZ-Standard-B",
    "Female": "sw-TZ-Standard-A",
}


def text_to_swahili_speech_gtts(text: str, voice_setting: str, output_path: str = None) -> str:
    """
    Free TTS using gTTS (Google Translate TTS).
    Swahili is supported (lang='sw').
    voice_setting is stored in metadata but gTTS doesn't support gender switching —
    that requires Google Cloud TTS (see text_to_swahili_speech_gcp below).
    """
    if output_path is None:
        tmp = tempfile.NamedTemporaryFile(suffix=".mp3", delete=False)
        output_path = tmp.name

    tts = gTTS(text=text, lang="sw", slow=False)
    tts.save(output_path)

    voice_id = VOICE_MAP.get(voice_setting, "sw-TZ-Standard-A")
    print(f"[Nena] Text: '{text}'")
    print(f"[Nena] Voice profile: {voice_setting} ({voice_id})")
    print(f"[Nena] Audio saved → {output_path}")
    return output_path


def text_to_swahili_speech_gcp(text: str, voice_setting: str, output_path: str = None) -> str:
    """
    Google Cloud Neural TTS — requires a service account key.

    Setup:
      1. Create a GCP project, enable Cloud Text-to-Speech API.
      2. Download service-account JSON → upload to Colab.
      3. Set os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = "/path/to/key.json"

    Supports gender-correct sw-TZ voices (Standard-A = Female, Standard-B = Male).
    """
    from google.cloud import texttospeech

    client = texttospeech.TextToSpeechClient()
    synthesis_input = texttospeech.SynthesisInput(text=text)

    voice_id = VOICE_MAP.get(voice_setting, "sw-TZ-Standard-A")
    gender = (
        texttospeech.SsmlVoiceGender.MALE
        if voice_setting == "Male"
        else texttospeech.SsmlVoiceGender.FEMALE
    )

    voice = texttospeech.VoiceSelectionParams(
        language_code="sw-TZ",
        name=voice_id,
        ssml_gender=gender,
    )
    audio_config = texttospeech.AudioConfig(
        audio_encoding=texttospeech.AudioEncoding.MP3,
        speaking_rate=USER_PROFILE["speed"],
    )

    response = client.synthesize_speech(
        input=synthesis_input, voice=voice, audio_config=audio_config
    )

    if output_path is None:
        tmp = tempfile.NamedTemporaryFile(suffix=".mp3", delete=False)
        output_path = tmp.name

    with open(output_path, "wb") as f:
        f.write(response.audio_content)

    print(f"[Nena] Text: '{text}'")
    print(f"[Nena] Voice profile: {voice_setting} → {voice_id}")
    print(f"[Nena] Audio saved → {output_path}")
    return output_path


def speak(text: str, profile: dict = USER_PROFILE, backend: str = "gtts") -> str:
    """
    Main entry point for the TTS layer.
    backend = "gtts"  → free, no API key needed
    backend = "gcp"   → Google Cloud, gender-correct voices
    """
    voice_setting = profile.get("voice", "Female")
    if backend == "gcp":
        return text_to_swahili_speech_gcp(text, voice_setting)
    return text_to_swahili_speech_gtts(text, voice_setting)


# ═══════════════════════════════════════════════════════════════
# CELL 8 — End-to-end demo (single image or video frame)
# ═══════════════════════════════════════════════════════════════

def run_demo(image_path: Optional[str] = None, frame_bgr: Optional[np.ndarray] = None):
    """
    Pass either:
      image_path  → path to a JPG/PNG file
      frame_bgr   → raw OpenCV frame (numpy array)
    """
    if image_path:
        frame_bgr = cv2.imread(image_path)
        if frame_bgr is None:
            print(f"❌ Could not load image: {image_path}")
            return

    if frame_bgr is None:
        # Generate a synthetic noise frame for testing (no real sign data yet)
        print("ℹ️  No image provided — using synthetic noise frame for pipeline test.")
        frame_bgr = np.random.randint(0, 255, (480, 640, 3), dtype=np.uint8)

    print("─" * 50)
    print("NENA · Sign-to-Swahili · Inference")
    print("─" * 50)

    sign_id, confidence = classify_sign(
        frame_bgr, PROTOTYPES, model, preprocess, device
    )

    if sign_id is None:
        print(f"[Nena] No sign recognised (best cosine score: {confidence:.3f})")
        print("       Add more reference images or lower the threshold.")
        return

    swahili_text = VOCAB_LOOKUP[sign_id]
    print(f"[Nena] Sign detected : {sign_id}")
    print(f"[Nena] Swahili text  : {swahili_text}")
    print(f"[Nena] Confidence    : {confidence:.3f}")

    audio_path = speak(swahili_text, profile=USER_PROFILE, backend="gtts")

    # Play audio inside Colab
    from IPython.display import Audio, display
    display(Audio(audio_path, autoplay=True))
    print("─" * 50)


# Run with a synthetic frame to test the pipeline end-to-end
run_demo()


# ═══════════════════════════════════════════════════════════════
# CELL 9 — Webcam / video file inference loop
#
# In Colab, webcam access requires JavaScript bridge.
# This cell handles BOTH:
#   Option A: Video file upload (drag .mp4 into Colab sidebar)
#   Option B: Colab webcam snapshot (JavaScript bridge)
# ═══════════════════════════════════════════════════════════════

# ---------- Option A: video file ----------

def process_video_file(video_path: str, sample_every_n_frames: int = 15):
    """
    Reads a video file, classifies every Nth frame, and calls TTS for
    any newly detected sign (deduplicates consecutive identical predictions).
    """
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        print(f"❌ Cannot open video: {video_path}")
        return

    fps = cap.get(cv2.CAP_PROP_FPS)
    total = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    print(f"Video: {video_path}  |  FPS: {fps:.1f}  |  Frames: {total}")

    frame_idx = 0
    last_sign = None
    from IPython.display import Audio, display

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        if frame_idx % sample_every_n_frames == 0:
            sign_id, conf = classify_sign(frame, PROTOTYPES, model, preprocess, device)
            if sign_id and sign_id != last_sign:
                swahili_text = VOCAB_LOOKUP[sign_id]
                print(f"  Frame {frame_idx:5d} → {sign_id} ({swahili_text}) [{conf:.3f}]")
                audio_path = speak(swahili_text, profile=USER_PROFILE, backend="gtts")
                display(Audio(audio_path, autoplay=False))
                last_sign = sign_id

        frame_idx += 1

    cap.release()
    print("✅ Video processing complete.")


# Uncomment and set your path:
# process_video_file("/content/my_sign_video.mp4")


# ---------- Option B: Colab webcam snapshot ----------

COLAB_WEBCAM_JS = """
async function capturePhoto() {
  const div = document.createElement('div');
  const video = document.createElement('video');
  video.style.display = 'block';
  const stream = await navigator.mediaDevices.getUserMedia({video: true});

  document.body.appendChild(div);
  div.appendChild(video);
  video.srcObject = stream;
  await video.play();

  await new Promise(r => setTimeout(r, 2000));   // 2-second preview

  const canvas = document.createElement('canvas');
  canvas.width = video.videoWidth;
  canvas.height = video.videoHeight;
  canvas.getContext('2d').drawImage(video, 0, 0);
  stream.getTracks().forEach(t => t.stop());
  div.remove();

  const dataUrl = canvas.toDataURL('image/jpeg', 0.8);
  const response = await fetch('/nbextensions/google.colab/files.js');
  return dataUrl;
}

const dataUrl = await capturePhoto();
google.colab.kernel.invokeFunction('notebook.photo_callback', [dataUrl], {});
"""


def capture_and_classify():
    """
    Trigger a webcam snapshot inside Colab and classify the sign.
    Only works when running in Google Colab with a browser.
    """
    try:
        from google.colab import output
        from IPython.display import Javascript, display
        import base64

        photo_data = {}

        def photo_callback(data_url):
            header, encoded = data_url.split(",", 1)
            photo_data["bytes"] = base64.b64decode(encoded)

        output.register_callback("notebook.photo_callback", photo_callback)
        display(Javascript(COLAB_WEBCAM_JS))

        import time
        time.sleep(4)     # Wait for JS to complete

        if photo_data:
            nparr = np.frombuffer(photo_data["bytes"], np.uint8)
            frame = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
            run_demo(frame_bgr=frame)
        else:
            print("⚠️  No photo captured.")
    except ImportError:
        print("⚠️  Not running in Google Colab. Use process_video_file() instead.")


# Uncomment to trigger webcam:
# capture_and_classify()


# ═══════════════════════════════════════════════════════════════
# CELL 10 — Save checkpoint & GitHub instructions
# ═══════════════════════════════════════════════════════════════

def save_prototype_checkpoint(path: str = "/content/nena_prototypes.pt"):
    """Save prototype embeddings so you don't need to recompute on each session."""
    torch.save(
        {sign_id: proto.cpu() for sign_id, proto in PROTOTYPES.items()},
        path
    )
    print(f"✅ Prototypes saved → {path}")


def load_prototype_checkpoint(path: str = "/content/nena_prototypes.pt") -> dict:
    """Load previously saved prototypes."""
    data = torch.load(path, map_location=device)
    prototypes = {k: v.to(device) for k, v in data.items()}
    print(f"✅ Prototypes loaded from {path} ({len(prototypes)} signs)")
    return prototypes


save_prototype_checkpoint()

GITHUB_INSTRUCTIONS = """
╔══════════════════════════════════════════════════════════╗
║          Push Nena to GitHub from Colab                  ║
╠══════════════════════════════════════════════════════════╣
║                                                          ║
║  1. File → Save a copy in GitHub                         ║
║     (easiest, no terminal needed)                        ║
║                                                          ║
║  OR via terminal:                                        ║
║                                                          ║
║  !git config --global user.email "you@example.com"       ║
║  !git config --global user.name "Your Name"              ║
║  !git clone https://github.com/YOUR_USERNAME/nena.git    ║
║  !cp /content/*.py /content/nena/                        ║
║  !cp /content/nena_prototypes.pt /content/nena/          ║
║  %cd /content/nena                                       ║
║  !git add .                                              ║
║  !git commit -m "Add Nena sign-to-Swahili pipeline"      ║
║  !git push                                               ║
║                                                          ║
║  Repo structure to aim for:                              ║
║    nena/                                                 ║
║    ├── nena_sign_to_swahili.py   ← this file             ║
║    ├── nena_prototypes.pt        ← saved embeddings      ║
║    ├── data/                     ← your TSL frames       ║
║    │   ├── habari/               ← one folder per sign   ║
║    │   ├── asante/                                       ║
║    │   └── ...                                           ║
║    └── README.md                                         ║
╚══════════════════════════════════════════════════════════╝

NEXT STEPS TO COLLECT TSL DATA
───────────────────────────────
1. Film 10–20 short clips of each sign (phone camera is fine).
2. Extract frames:
     !ffmpeg -i my_sign.mp4 -vf fps=5 data/habari/frame_%04d.jpg
3. Add frame paths to the VOCABULARY list in Cell 4:
     "reference_img": ["data/habari/frame_0001.jpg", ...]
4. Re-run Cell 5 to rebuild prototypes with real visual signal.
5. Accuracy will improve dramatically with even 5 real frames per sign.

DATASETS TO WATCH (from Awesome-Sign-Language repo):
  · How2Sign (ASL) — structure your TSL data the same way
  · OpenASL — study the annotation format
  · Phoenix-2014T — good gloss-text alignment reference
"""

print(GITHUB_INSTRUCTIONS)
