import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/voice_profile_provider.dart';
import '../providers/theme_provider.dart';
import '../services/ai_backend_service.dart';
import '../services/tts_service.dart';
import '../widgets/caption_bar.dart';
import '../widgets/settings_drawer.dart';
import 'call_screen.dart';

/// HomeScreen — main screen of the NENA app.
///
/// Applied UX Design principles applied:
/// • Control: users explicitly choose voice profile + light/dark theme
/// • Transparency: status indicators show exactly what the AI is doing
/// • Trust calibration: the hand guide overlay sets correct expectations
///   about where to position hands before the AI starts processing
/// • Graceful defaults: theme choice persists across sessions
///
/// Theme toggle: appears only when the user taps the settings gear icon.
/// (Progressive disclosure — don't show everything at once.)
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _aiService  = AiBackendService();
  final _ttsService = TtsService();

  CameraController? _cameraController;
  bool _isCameraReady = false;

  String? _predictedWord;
  bool   _isSpeaking  = false;
  bool   _isListening = false;

  Timer? _frameTimer;
  static const _intervalMs = 500;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      _cameraController = CameraController(
        front, ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await _cameraController!.initialize();
      if (mounted) setState(() => _isCameraReady = true);
    } catch (e) {
      debugPrint('[Camera] $e');
    }
  }

  void _startListening() {
    if (!_isCameraReady || _isListening) return;
    setState(() => _isListening = true);
    _cameraController!.startImageStream((_) {});
    _frameTimer = Timer.periodic(
      const Duration(milliseconds: _intervalMs),
      (_) => _captureAndSend(),
    );
  }

  void _stopListening() {
    _frameTimer?.cancel();
    _frameTimer = null;
    _cameraController?.stopImageStream().catchError((_) {});
    if (mounted) setState(() => _isListening = false);
  }

  Future<void> _captureAndSend() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    try {
      final xFile = await _cameraController!.takePicture();
      final bytes = await xFile.readAsBytes();
      final prediction = await _aiService.predictSign(bytes);
      if (prediction != null && prediction != _predictedWord) {
        setState(() => _predictedWord = prediction);
        if (mounted) {
          final profile = context.read<VoiceProfileProvider>().voiceProfile;
          _speakWord(prediction, profile);
        }
      }
    } catch (e) {
      debugPrint('[Frame] $e');
    }
  }

  Future<void> _speakWord(String word, String profile) async {
    setState(() => _isSpeaking = true);
    await _ttsService.speak(word, profile);
    if (mounted) setState(() => _isSpeaking = false);
  }

  @override
  void dispose() {
    _stopListening();
    _cameraController?.dispose();
    _ttsService.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final profileProvider = context.watch<VoiceProfileProvider>();
    final themeProvider   = context.watch<ThemeProvider>();
    final isDark          = themeProvider.isDark;

    // Adaptive colour tokens — switch cleanly between dark and light
    final bg        = isDark ? const Color(0xFF0A0F1A) : const Color(0xFFF4F6F9);
    final surface   = isDark ? const Color(0xFF0D1829) : Colors.white;
    final onSurface = isDark ? Colors.white            : const Color(0xFF0D1829);
    final accent    = const Color(0xFF00BCD4);
    final subtle    = isDark ? Colors.white24          : Colors.black26;

    return Scaffold(
      backgroundColor: bg,
      drawer: const SettingsDrawer(),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(
              context, profileProvider, themeProvider,
              isDark: isDark,
              onSurface: onSurface,
              accent: accent,
              subtle: subtle,
            ),
            Expanded(
              flex: 6,
              child: _buildViewfinder(isDark: isDark, subtle: subtle),
            ),
            Expanded(
              flex: 4,
              child: CaptionBar(
                predictedWord: _predictedWord,
                isSpeaking: _isSpeaking,
                isListening: _isListening,
                onReplay: _predictedWord != null
                    ? () => _speakWord(_predictedWord!, profileProvider.voiceProfile)
                    : null,
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _buildSignButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  // ── Top bar ───────────────────────────────────────────────────────────────

  Widget _buildTopBar(
    BuildContext context,
    VoiceProfileProvider profileProvider,
    ThemeProvider themeProvider, {
    required bool isDark,
    required Color onSurface,
    required Color accent,
    required Color subtle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          // ── Settings drawer ──────────────────────────────────────────────
          Builder(
            builder: (ctx) => IconButton(
              icon: Icon(Icons.tune, color: onSurface.withOpacity(0.7)),
              tooltip: 'Mipangilio / Settings',
              onPressed: () => Scaffold.of(ctx).openDrawer(),
            ),
          ),

          const Spacer(),

          // ── App title — long-press reveals theme toggle ──────────────────
          GestureDetector(
            onLongPress: () => _showThemeDialog(context, themeProvider),
            child: Text(
              'NENA',
              style: TextStyle(
                color: accent,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 4,
              ),
            ),
          ),

          const Spacer(),

          // ── Call button ──────────────────────────────────────────────────
          IconButton(
            icon: Icon(Icons.call_rounded, color: accent),
            tooltip: 'Piga Simu / Start Call',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const CallScreen(
                  callerName: 'Mwenzako',
                  callerId:   'user-001',
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),

          // ── Voice profile badge ──────────────────────────────────────────
          GestureDetector(
            onTap: () => profileProvider.setProfile(
              profileProvider.isMale ? 'Female' : 'Male'),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: (profileProvider.isMale
                    ? const Color(0xFF1E90E9)
                    : const Color(0xFFE91E8C)).withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: profileProvider.isMale
                      ? const Color(0xFF1E90E9)
                      : const Color(0xFFE91E8C),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    profileProvider.isMale ? Icons.person : Icons.person_outline,
                    size: 13,
                    color: profileProvider.isMale
                        ? const Color(0xFF1E90E9)
                        : const Color(0xFFE91E8C),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    profileProvider.voiceProfile,
                    style: TextStyle(
                      color: profileProvider.isMale
                          ? const Color(0xFF1E90E9)
                          : const Color(0xFFE91E8C),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Theme dialog — only shown on long-press (progressive disclosure) ──────

  void _showThemeDialog(BuildContext context, ThemeProvider themeProvider) {
    final isDark = themeProvider.isDark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF0D1829) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mandhari / Appearance',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Chagua mwanga wa skrini',
              style: TextStyle(
                color: isDark ? Colors.white38 : Colors.black38,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _ThemeOptionTile(
                    label: 'Giza',
                    sublabel: 'Dark',
                    icon: Icons.dark_mode_outlined,
                    isSelected: isDark,
                    selectedColor: const Color(0xFF00BCD4),
                    isDark: isDark,
                    onTap: () {
                      if (!isDark) themeProvider.toggle();
                      Navigator.pop(context);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ThemeOptionTile(
                    label: 'Mwanga',
                    sublabel: 'Light',
                    icon: Icons.light_mode_outlined,
                    isSelected: !isDark,
                    selectedColor: const Color(0xFFFF8F00),
                    isDark: isDark,
                    onTap: () {
                      if (isDark) themeProvider.toggle();
                      Navigator.pop(context);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Viewfinder ────────────────────────────────────────────────────────────

  Widget _buildViewfinder({required bool isDark, required Color subtle}) {
    if (!_isCameraReady) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Color(0xFF00BCD4)),
            const SizedBox(height: 16),
            Text(
              'Inaanzisha kamera...',
              style: TextStyle(
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            ),
          ],
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(child: CameraPreview(_cameraController!)),

        // Hand guide overlay — sets correct expectation (trust calibration)
        if (!_isListening)
          Center(
            child: Container(
              width: 200,
              height: 220,
              decoration: BoxDecoration(
                border: Border.all(
                  color: const Color(0xFF00BCD4).withOpacity(0.5),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(
                  'Weka mikono hapa\nPlace hands here',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDark ? Colors.white60 : Colors.white,
                    fontSize: 12,
                    height: 1.6,
                    shadows: const [Shadow(blurRadius: 8)],
                  ),
                ),
              ),
            ),
          ),

        // Scanning line
        if (_isListening)
          Positioned.fill(child: _ScanLine()),
      ],
    );
  }

  // ── Hold-to-sign FAB ──────────────────────────────────────────────────────

  Widget _buildSignButton() {
    return GestureDetector(
      onTapDown: (_) => _startListening(),
      onTapUp: (_) => _stopListening(),
      onTapCancel: () => _stopListening(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: _isListening ? 72 : 64,
        height: _isListening ? 72 : 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _isListening
              ? const Color(0xFFE53935)
              : const Color(0xFF00897B),
          boxShadow: [
            BoxShadow(
              color: (_isListening
                      ? const Color(0xFFE53935)
                      : const Color(0xFF00897B))
                  .withOpacity(0.5),
              blurRadius: _isListening ? 24 : 12,
              spreadRadius: _isListening ? 4 : 0,
            ),
          ],
        ),
        child: Icon(
          _isListening ? Icons.stop : Icons.front_hand_outlined,
          color: Colors.white,
          size: 28,
        ),
      ),
    );
  }
}

// ── Theme option tile ─────────────────────────────────────────────────────────

class _ThemeOptionTile extends StatelessWidget {
  final String label;
  final String sublabel;
  final IconData icon;
  final bool isSelected;
  final Color selectedColor;
  final bool isDark;
  final VoidCallback onTap;

  const _ThemeOptionTile({
    required this.label,
    required this.sublabel,
    required this.icon,
    required this.isSelected,
    required this.selectedColor,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final text = isDark ? Colors.white : Colors.black87;
    final textSub = isDark ? Colors.white38 : Colors.black38;
    final border = isDark ? Colors.white12 : Colors.black12;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected
              ? selectedColor.withOpacity(0.12)
              : (isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.04)),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? selectedColor : border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
              color: isSelected ? selectedColor : textSub,
              size: 28,
            ),
            const SizedBox(height: 8),
            Text(label,
              style: TextStyle(
                color: isSelected ? text : textSub,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(sublabel,
              style: TextStyle(
                color: isSelected ? selectedColor : textSub,
                fontSize: 11,
              ),
            ),
            if (isSelected) ...[
              const SizedBox(height: 6),
              Icon(Icons.check_circle, color: selectedColor, size: 16),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Scan line animation ───────────────────────────────────────────────────────

class _ScanLine extends StatefulWidget {
  @override
  State<_ScanLine> createState() => _ScanLineState();
}

class _ScanLineState extends State<_ScanLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) => CustomPaint(
        painter: _ScanPainter(_ctrl.value),
      ),
    );
  }
}

class _ScanPainter extends CustomPainter {
  final double p;
  _ScanPainter(this.p);

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * p;
    final paint = Paint()
      ..shader = LinearGradient(colors: [
        Colors.transparent,
        const Color(0xFF00BCD4).withOpacity(0.75),
        Colors.transparent,
      ]).createShader(Rect.fromLTWH(0, y - 1, size.width, 2))
      ..strokeWidth = 2;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
  }

  @override
  bool shouldRepaint(_ScanPainter o) => o.p != p;
}
