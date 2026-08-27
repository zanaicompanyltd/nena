import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages the user's chosen voice profile across the entire app.
/// This is the "Application Settings Profile Topology" described in the
/// architecture document — decouples gender from Swahili text tokens.
class VoiceProfileProvider extends ChangeNotifier {
  // Default to Female profile on first launch
  String _voiceProfile = 'Female';

  String get voiceProfile => _voiceProfile;

  bool get isMale => _voiceProfile == 'Male';
  bool get isFemale => _voiceProfile == 'Female';

  VoiceProfileProvider() {
    _loadSavedProfile(); // Restore last-used setting on app start
  }

  /// Load the saved preference from device storage (survives app restarts)
  Future<void> _loadSavedProfile() async {
    final prefs = await SharedPreferences.getInstance();
    _voiceProfile = prefs.getString('voice_profile') ?? 'Female';
    notifyListeners();
  }

  /// Toggle between Male and Female and save immediately
  Future<void> setProfile(String profile) async {
    if (profile != 'Male' && profile != 'Female') return;
    _voiceProfile = profile;
    notifyListeners(); // Rebuild any widget watching this provider

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('voice_profile', profile);
  }
}
