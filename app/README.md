# Nena — Sign Language to Swahili Voice App
### TSL / KSL → Real-Time Swahili Speech Synthesis

> "Nena" means **"Speak"** in Swahili.

---

## What This App Does
1. Opens the front camera and streams video frames
2. Sends frames to your AI backend (CLIP few-shot model)
3. Receives a Swahili word prediction (e.g. *"Habari"*)
4. Speaks it aloud using the user's chosen **Male or Female voice profile**

---

## Directory Structure
```
C:\nena\
├── lib\
│   ├── main.dart                    ← App entry point
│   ├── screens\
│   │   └── home_screen.dart         ← Main UI (camera + captions)
│   ├── widgets\
│   │   ├── settings_drawer.dart     ← Voice profile selector
│   │   └── caption_bar.dart         ← Swahili word display
│   ├── services\
│   │   ├── tts_service.dart         ← Text-to-Speech (Male/Female routing)
│   │   └── ai_backend_service.dart  ← HTTP calls to your AI backend
│   └── providers\
│       └── voice_profile_provider.dart  ← Global state (Male/Female toggle)
├── android\
│   └── app\src\main\
│       └── AndroidManifest.xml      ← Camera + Internet permissions
├── assets\
│   └── images\                      ← Place any icons/images here
└── pubspec.yaml                     ← All dependencies
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
cd C:\nena
code .         # Opens VS Code in this folder
```

### Step 3 — Install dependencies
```bash
flutter pub get
```

### Step 4 — Connect your Android phone
1. Enable **Developer Options** on your phone (tap Build Number 7 times)
2. Enable **USB Debugging**
3. Connect via USB cable
4. Run: `flutter devices` — your phone should appear

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
- `POST /predict` — accepts `{ "frame": "<base64 jpeg>" }`, returns `{ "prediction": "Habari" }`
- `GET /health` — returns 200 OK

---

## Voice Profiles

| Profile | Swahili | Voice | Pitch |
|---------|---------|-------|-------|
| Female (Beta) | Sauti ya Kike | sw-tz-x-sfg-local | High |
| Male (Alpha) | Sauti ya Kiume | sw-tz-x-mtm-local | Low |

The user picks their profile once in Settings — the app remembers it forever.

---

## Architecture Reference
See `Sign_to_Swahili_Multimodal_Architecture.pdf` for the full technical blueprint.
