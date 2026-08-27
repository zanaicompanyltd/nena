import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

/// Ingestion & Alignment Layer.
/// Sends buffered camera frames to your AI backend (Google Colab / Flask server)
/// and receives the predicted Swahili token string in return.
class AiBackendService {
  // ──────────────────────────────────────────────
  // IMPORTANT: Replace this URL with your actual backend address.
  // When running on Google Colab + ngrok, it will look like:
  //   'https://abcd-12-34-56-78.ngrok-free.app'
  // For local testing with Flutter web emulator:
  //   'http://127.0.0.1:5000'
  // ──────────────────────────────────────────────
  static const String _baseUrl = 'https://YOUR_COLAB_NGROK_URL_HERE';

  /// Send a single JPEG frame (as raw bytes) to the /predict endpoint.
  /// Returns the predicted Swahili word, or null on error.
  Future<String?> predictSign(Uint8List jpegFrameBytes) async {
    try {
      final uri = Uri.parse('$_baseUrl/predict');

      // Encode frame as base64 so it can travel in JSON
      final base64Image = base64Encode(jpegFrameBytes);

      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'frame': base64Image}),
          )
          .timeout(const Duration(seconds: 5)); // Don't block the UI thread

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        // Expected response format: { "prediction": "Habari", "confidence": 0.91 }
        return data['prediction'] as String?;
      } else {
        // Non-200 response — log for debugging
        print('[AI Backend] Error ${response.statusCode}: ${response.body}');
        return null;
      }
    } catch (e) {
      // Network error or timeout — fail silently so the app keeps running
      print('[AI Backend] Connection error: $e');
      return null;
    }
  }

  /// Health-check: verify the backend is reachable before streaming frames.
  Future<bool> isBackendReachable() async {
    try {
      final uri = Uri.parse('$_baseUrl/health');
      final response = await http
          .get(uri)
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
