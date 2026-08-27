import 'package:flutter_tts/flutter_tts.dart';

/// Neural audio output layer.
/// Routes translated Swahili tokens to the correct voice profile
/// (Profile Mode Alpha = Male, Profile Mode Beta = Female)
/// as specified in Section 3.3 of the architecture document.
class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _isInitialized = false;

  Future<void> _init() async {
    if (_isInitialized) return;

    // Set language to Tanzanian Swahili
    await _tts.setLanguage('sw-TZ');

    // Speech rate: slightly slower for clarity (sign language users)
    await _tts.setSpeechRate(0.45);

    // Volume and pitch defaults
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    _isInitialized = true;
  }

  /// Speak the predicted Swahili word using the user's selected voice profile.
  ///
  /// [predictedText]  — the Swahili token returned by the AI backend
  /// [voiceProfile]   — 'Male' (Profile Alpha) or 'Female' (Profile Beta)
  Future<void> speak(String predictedText, String voiceProfile) async {
    await _init();

    // Stop any currently playing speech first
    await _tts.stop();

    if (voiceProfile == 'Male') {
      // Profile Mode Alpha — Acoustic Masculine
      // sw-TZ-Standard-B equivalent on device
      await _tts.setVoice({
        'name': 'sw-tz-x-mtm-local', // Swahili male voice on Android
        'locale': 'sw-TZ',
      });
      await _tts.setPitch(0.80); // Lower pitch = masculine resonance
    } else {
      // Profile Mode Beta — Acoustic Feminine
      // sw-TZ-Standard-A equivalent on device
      await _tts.setVoice({
        'name': 'sw-tz-x-sfg-local', // Swahili female voice on Android
        'locale': 'sw-TZ',
      });
      await _tts.setPitch(1.15); // Higher pitch = feminine tone
    }

    await _tts.speak(predictedText);
  }

  /// Stop playback immediately
  Future<void> stop() async {
    await _tts.stop();
  }

  /// List all voices available on the device (useful for debugging)
  Future<List<dynamic>> getAvailableVoices() async {
    await _init();
    return await _tts.getVoices ?? [];
  }

  void dispose() {
    _tts.stop();
  }
}
