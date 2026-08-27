# Nena — Sign Language to Swahili Voice App

**TSL / KSL → Real-Time Swahili Speech Synthesis**

> *"Nena" means "Speak" in Swahili.*

## Project Description

Nena is an AI-powered bidirectional mobile communication platform that eliminates
communication barriers for Deaf and hard-of-hearing individuals across East Africa.
It enables real-time, two-way translation between Tanzanian/Kenyan Sign Language (TSL/KSL)
and spoken Swahili — both face-to-face and during live phone calls — without needing a
human interpreter.

The app turns any Android smartphone into a pocket interpreter by combining:
- **Few-shot CLIP** gesture recognition (on-device, privacy-preserving)
- **OpenAI Whisper** speech recognition
- **Neural text-to-speech** with a user-selectable Male/Female voice profile
- **WebRTC/SIP-based live calling** (Nena Call) for real phone conversations

### What Nena Does

1. Opens the front camera and streams video frames.
2. Sends frames to the AI backend for gesture classification (few-shot CLIP model).
3. Receives a predicted Swahili word (e.g. *"Habari"*).
4. Speaks it aloud using the user's chosen Male or Female voice profile.
5. For incoming speech (Nena Call or in person), transcribes Swahili audio via Whisper
   and displays it as sign animation for the Deaf user.

### Why It Matters

- No affordable interpreter access excludes Deaf individuals from hospitals, banks,
  and government services.
- Standard phone networks carry only audio — Deaf users can't call independently.
- TSL/KSL have very little annotated training data, requiring a few-shot learning
  approach rather than standard deep learning.
- Nena is designed to run on constrained 3G networks and mid-range Android hardware
  (2019+), with all gesture-recognition inference happening **on-device** — no video
  is ever uploaded, preserving user privacy.

Target MVP release: **Android, Q4 2026** (iOS planned for a later phase).

---

## Directory Structure

```
nena/
├── app/                        # Flutter mobile app
│   ├── lib/
│   │   ├── main.dart           # App entry point
│   │   ├── screens/            # UI screens (home, call, avatar)
│   │   ├── widgets/            # Reusable widgets (settings drawer, caption bar)
│   │   ├── services/           # TTS, Whisper, VoIP, AI backend calls
│   │   └── providers/          # State management (voice profile, theme)
│   ├── android/                # Android platform files
│   └── pubspec.yaml
├── backend/sign/                # Python CLIP sign-recognition model
│   ├── model.py
│   ├── train.py
│   ├── predict.py
│   └── requirements.txt
├── models/sign/                  # Trained model weights (gitignored)
├── data/                         # Training data & scripts
│   ├── frames/                   # Labeled sign video frames (43 signs)
│   ├── frame_manifest.json
│   ├── labeled_inventory.json
│   ├── extract_frames.py
│   └── nena_sign_to_swahili.py
├── dictionaries/                  # TSL reference books
├── docs/                          # Architecture docs, concept notes, diagrams
├── notebooks/                     # Training notebooks (Colab/Jupyter)
└── README.md
```

---

## Setup Instructions (VS Code on Windows)

### Step 1 — Install Flutter

1. Download Flutter SDK: https://docs.flutter.dev/get-started/install/windows
2. Extract to `C:\flutter`
3. Add `C:\flutter\bin` to your Windows PATH
4. Run `flutter doctor` in terminal — fix any issues it flags

### Step 2 — Open the project

```bash
cd nena/app
code .
```

### Step 3 — Install dependencies

```bash
flutter pub get
```

### Step 4 — Connect your Android phone

1. Enable **Developer Options** on your phone (tap Build Number 7 times)
2. Enable **USB Debugging**
3. Connect via USB cable
4. Run `flutter devices` — your phone should appear

### Step 5 — Run the app

```bash
flutter run
```

---

## Connecting to Your AI Backend (Google Colab)

1. Open `lib/services/ai_backend_service.dart`
2. Find this line:
   ```dart
   static const String _baseUrl = 'https://YOUR_COLAB_NGROK_URL_HERE';
   ```
3. Replace it with your ngrok URL from Colab, e.g.:
   ```dart
   static const String _baseUrl = 'https://abcd-12-34-56-78.ngrok-free.app';
   ```

Your Flask backend in Colab should have two endpoints:
- `POST /predict` — accepts `{"frame": "base64 jpeg"}`, returns `{"prediction": "habari"}`
- `GET /health` — returns 200 OK

---

## Voice Profiles

| Profile | Swahili | Voice | Pitch |
|---|---|---|---|
| Female (Beta) | Sauti ya Kike | sw-tz-x-sfg-local | High |
| Male (Alpha) | Sauti ya Kiume | sw-tz-x-mtm-local | Low |

The user picks their profile once in Settings — the app remembers it forever.

---

## Architecture Reference

See [`docs/Sign_to_Swahili_Multimodal_Architecture.pdf`](docs/Sign_to_Swahili_Multimodal_Architecture.pdf)
for the full technical blueprint, and
[`docs/NENA_Bidirectional_VoIP_Architecture.pdf`](docs/NENA_Bidirectional_VoIP_Architecture.pdf)
for the Nena Call (live phone relay) design.

For full MVP scope, requirements, sprint plan, and team roles, see
[`docs/nena_project_guideline.pdf`](docs/nena_project_guideline.pdf).
