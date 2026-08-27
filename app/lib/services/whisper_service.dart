import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Whisper ASR Service — Stream B inbound pipeline.
///
/// Sends raw audio bytes from the caller to your Flask/Colab backend
/// which runs OpenAI Whisper to convert speech into Swahili text.
/// The returned text tokens drive the avatar on the Deaf user's screen.
class WhisperService {
  // Same base URL as your AI backend service
  // Update this when your Colab ngrok URL changes
  static const String _baseUrl = 'https://YOUR_COLAB_NGROK_URL_HERE';

  /// Transcribe an audio clip to Swahili text.
  /// [audioBytes] — raw PCM or WAV audio bytes from the caller
  /// Returns the Swahili transcription or null on failure.
  Future<String?> transcribeAudio(Uint8List audioBytes) async {
    try {
      final uri = Uri.parse('$_baseUrl/transcribe');
      final base64Audio = base64Encode(audioBytes);

      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'audio': base64Audio}),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final text = data['text'] as String?;
        if (text != null && text.trim().isNotEmpty) {
          debugPrint('[Whisper] Transcribed: "$text"');
          return text.trim();
        }
      } else {
        debugPrint('[Whisper] Error ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      debugPrint('[Whisper] Connection error: $e');
    }
    return null;
  }

  /// Extract key semantic words from a full Swahili sentence.
  /// Strips filler words so the avatar only signs meaningful content.
  List<String> extractKeywords(String sentence) {
    // Swahili filler/connector words to remove before avatar signing
    const fillers = {
      'na', 'ya', 'wa', 'la', 'kwa', 'ni', 'si', 'au',
      'pia', 'tu', 'hii', 'hiyo', 'ile', 'hizo',
      'a', 'e', 'i', 'o', 'u',
    };

    return sentence
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '') // Remove punctuation
        .split(RegExp(r'\s+'))
        .where((word) => word.length > 1 && !fillers.contains(word))
        .toList();
  }
}
