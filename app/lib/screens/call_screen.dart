import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/voice_profile_provider.dart';
import '../services/ai_backend_service.dart';
import '../services/tts_service.dart';
import '../services/voip_service.dart';
import '../services/whisper_service.dart';
import 'avatar_screen.dart';
import '../widgets/avatar_widget.dart';

/// CallScreen — the NENA live VoIP call interface.
///
/// Layout:
/// ┌─────────────────────────────┐
/// │  Caller avatar / audio viz  │  ← Top 40%: Stream B display
/// │  Inbound signed words       │    (what the caller is saying)
/// ├─────────────────────────────┤
/// │  [your camera preview]      │  ← Middle 35%: Stream A input
/// │  Sign here to speak         │    (Deaf user's hand signs)
/// ├─────────────────────────────┤
/// │  Last spoken word           │  ← Bottom 25%: controls + status
/// │  [End Call]  [Mute]  [👤]  │
/// └─────────────────────────────┘
class CallScreen extends StatefulWidget {
  final String callerName;
  final String callerId;
  final bool isIncoming;

  const CallScreen({
    super.key,
    required this.callerName,
    required this.callerId,
    this.isIncoming = false,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen>
    with TickerProviderStateMixin {
  // ── Services ──────────────────────────────────────────────────────────────
  late final VoipService _voipService;
  final _ttsService = TtsService();
  final _aiService = AiBackendService();
  final _whisperService = WhisperService();

  // ── Camera ────────────────────────────────────────────────────────────────
  CameraController? _cameraController;
  bool _isCameraReady = false;

  // ── Stream subscriptions ──────────────────────────────────────────────────
  StreamSubscription<String>? _inboundSub;
  StreamSubscription<double>? _audioLevelSub;
  Timer? _signCaptureTimer;

  // ── State ─────────────────────────────────────────────────────────────────
  String? _lastSpokenWord;          // What the Deaf user last signed (outbound)
  String? _inboundWord;             // What the caller just said (inbound)
  List<String> _inboundHistory = []; // Scrollable transcript of caller's words
  double _audioLevel = 0.0;         // Caller's current audio level (0.0–1.0)
  bool _isSigning = false;          // Deaf user actively holding sign button
  bool _isMuted = false;
  bool _isCallActive = false;

  // ── Animation ─────────────────────────────────────────────────────────────
  late final AnimationController _pulseController;
  late final AnimationController _waveController;

  @override
  void initState() {
    super.initState();

    _voipService = VoipService();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat();

    _initCamera();
    _initCall();
    _listenToStreams();
  }

  // ── Initialisation ────────────────────────────────────────────────────────

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;

      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _cameraController!.initialize();
      if (mounted) setState(() => _isCameraReady = true);
    } catch (e) {
      debugPrint('[Call] Camera init error: $e');
    }
  }

  Future<void> _initCall() async {
    try {
      if (widget.isIncoming) {
        // Incoming call — show connecting state, user taps Accept
        setState(() => _isCallActive = false);
      } else {
        // Outgoing call — dial immediately
        await _voipService.startCall(widget.callerId);
        setState(() => _isCallActive = true);
      }
    } catch (e) {
      debugPrint('[Call] Init error: $e');
    }
  }

  void _listenToStreams() {
    // Stream B: inbound Swahili text tokens from the caller
    // Each word drives the avatar display and scrolling transcript
    _inboundSub = _voipService.inboundTextStream.listen((word) {
      if (!mounted) return;
      setState(() {
        _inboundWord = word;
        _inboundHistory.insert(0, word);
        if (_inboundHistory.length > 12) _inboundHistory.removeLast();
      });
    });

    // Caller's audio level — drives the waveform visualizer
    _audioLevelSub = _voipService.audioLevelStream.listen((level) {
      if (!mounted) return;
      setState(() => _audioLevel = level.clamp(0.0, 1.0));
    });
  }

  // ── Stream A: Sign capture ─────────────────────────────────────────────────

  void _startSigning() {
    if (!_isCameraReady || _isSigning) return;
    setState(() => _isSigning = true);

    // Capture a frame every 500ms while user holds the sign button
    _signCaptureTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _captureAndTranslate(),
    );
  }

  void _stopSigning() {
    _signCaptureTimer?.cancel();
    _signCaptureTimer = null;
    if (mounted) setState(() => _isSigning = false);
  }

  Future<void> _captureAndTranslate() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }
    try {
      final xFile = await _cameraController!.takePicture();
      final bytes = await xFile.readAsBytes();

      // Send frame to CLIP backend
      final prediction = await _aiService.predictSign(bytes);

      if (prediction != null && prediction != _lastSpokenWord) {
        setState(() => _lastSpokenWord = prediction);

        // Stream A: speak the word via TTS (caller hears it)
        final profile = context.read<VoiceProfileProvider>().voiceProfile;
        await _ttsService.speak(prediction, profile);

        // Also send the text token over WebRTC data channel
        // (so a relay server can inject audio into the caller's phone line)
        _voipService.sendSwahiliToken(prediction);
      }
    } catch (e) {
      debugPrint('[Call] Frame capture error: $e');
    }
  }

  // ── Call controls ─────────────────────────────────────────────────────────

  Future<void> _acceptIncomingCall() async {
    setState(() => _isCallActive = true);
    await _voipService.startCall(widget.callerId);
  }

  Future<void> _endCall() async {
    _stopSigning();
    await _voipService.endCall();
    if (mounted) Navigator.of(context).pop();
  }

  void _toggleMute() {
    setState(() => _isMuted = !_isMuted);
    _localStream?.getAudioTracks().forEach((t) => t.enabled = !_isMuted);
  }

  MediaStream? get _localStream => null; // Expose from VoipService if needed

  // ── Dispose ───────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _stopSigning();
    _inboundSub?.cancel();
    _audioLevelSub?.cancel();
    _pulseController.dispose();
    _waveController.dispose();
    _cameraController?.dispose();
    _ttsService.dispose();
    _voipService.dispose();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060D17),
      body: SafeArea(
        child: Column(
          children: [
            // ── Top: Stream B — what the caller is saying ──────────────
            Expanded(
              flex: 4,
              child: _buildInboundPanel(),
            ),

            // ── Middle: Stream A — Deaf user's camera sign zone ────────
            Expanded(
              flex: 35,
              child: _buildSigningPanel(),
            ),

            // ── Bottom: Controls + last spoken word ────────────────────
            _buildCallControls(),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // WIDGET BUILDERS
  // ─────────────────────────────────────────────────────────────────────────

  /// Top panel — Stream B (caller's speech → text tokens → display)
  Widget _buildInboundPanel() {
    return Container(
      width: double.infinity,
      color: const Color(0xFF0D1829),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Caller info bar
          Row(
            children: [
              _buildCallerAvatar(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.callerName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    ListenableBuilder(
                      listenable: _voipService,
                      builder: (_, __) => Text(
                        _isCallActive
                            ? _voipService.callDuration
                            : 'Connecting...',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Audio level waveform
              _AudioWaveBar(
                level: _audioLevel,
                controller: _waveController,
              ),
              const SizedBox(width: 8),
              // Expand to full-screen avatar view
              GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AvatarScreen(
                      voipService: _voipService,
                      callerName: widget.callerName,
                    ),
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C5CFC).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: const Color(0xFF7C5CFC).withOpacity(0.3)),
                  ),
                  child: const Icon(Icons.open_in_full_rounded,
                      color: Color(0xFF9D80FD), size: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Inbound word + compact avatar side by side
          if (_inboundWord != null)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AvatarWidget(word: _inboundWord, compact: true),
                const SizedBox(width: 12),
                Text(
                  _inboundWord!,
                  style: const TextStyle(
                    color: Color(0xFF7C5CFC),
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            )
          else
            Text(
              _isCallActive ? 'Ngoja mwenzako aongee...' : 'Inaungana...',
              style: const TextStyle(color: Colors.white24, fontSize: 13),
            ),
          // Recent inbound history (small scrollable row)
          if (_inboundHistory.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _inboundHistory.skip(1).take(6).map((word) =>
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C5CFC).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF7C5CFC).withOpacity(0.25)),
                      ),
                      child: Text(
                        word,
                        style: const TextStyle(
                          color: Color(0xFF9D80FD),
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Middle panel — Stream A (camera sign zone)
  Widget _buildSigningPanel() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Camera preview
        if (_isCameraReady)
          CameraPreview(_cameraController!)
        else
          const Center(
            child: CircularProgressIndicator(color: Color(0xFF00BCD4)),
          ),

        // Dark overlay when not signing
        if (!_isSigning)
          Container(color: Colors.black.withOpacity(0.35)),

        // Guide overlay
        Center(
          child: AnimatedOpacity(
            opacity: _isSigning ? 0.0 : 1.0,
            duration: const Duration(milliseconds: 300),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 180,
                  height: 200,
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: const Color(0xFF00BCD4).withOpacity(0.5),
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Shikilia kusema',
                  style: TextStyle(color: Colors.white60, fontSize: 13),
                ),
                const Text(
                  'Hold to sign',
                  style: TextStyle(color: Colors.white30, fontSize: 11),
                ),
              ],
            ),
          ),
        ),

        // Scanning animation while signing
        if (_isSigning) const _ScanOverlay(),

        // Last spoken word badge (bottom of camera)
        if (_lastSpokenWord != null)
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Container(
                  key: ValueKey(_lastSpokenWord),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00897B).withOpacity(0.9),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Text(
                    _lastSpokenWord!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Bottom controls bar
  Widget _buildCallControls() {
    // Show accept/reject if this is an unanswered incoming call
    if (widget.isIncoming && !_isCallActive) {
      return _buildIncomingCallActions();
    }

    return Container(
      color: const Color(0xFF060D17),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      child: Column(
        children: [
          // Hold-to-sign button (large, central)
          GestureDetector(
            onTapDown: (_) => _startSigning(),
            onTapUp: (_) => _stopSigning(),
            onTapCancel: () => _stopSigning(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: _isSigning ? 80 : 72,
              height: _isSigning ? 80 : 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isSigning
                    ? const Color(0xFFE53935)
                    : const Color(0xFF00897B),
                boxShadow: [
                  BoxShadow(
                    color: (_isSigning
                            ? const Color(0xFFE53935)
                            : const Color(0xFF00897B))
                        .withOpacity(0.45),
                    blurRadius: _isSigning ? 28 : 14,
                    spreadRadius: _isSigning ? 6 : 0,
                  ),
                ],
              ),
              child: Icon(
                _isSigning ? Icons.stop_rounded : Icons.front_hand_outlined,
                color: Colors.white,
                size: 30,
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Secondary controls row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ControlButton(
                icon: _isMuted ? Icons.mic_off : Icons.mic,
                label: _isMuted ? 'Unmute' : 'Mute',
                color: _isMuted
                    ? const Color(0xFFE53935)
                    : Colors.white38,
                onTap: _toggleMute,
              ),
              // End Call button
              _ControlButton(
                icon: Icons.call_end_rounded,
                label: 'Maliza',
                color: const Color(0xFFE53935),
                size: 58,
                onTap: _endCall,
              ),
              _ControlButton(
                icon: Icons.history_edu_outlined,
                label: 'Maneno',
                color: Colors.white38,
                onTap: () => _showTranscriptSheet(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildIncomingCallActions() {
    return Container(
      color: const Color(0xFF060D17),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
      child: Column(
        children: [
          Text(
            '${widget.callerName} anapigia simu...',
            style: const TextStyle(color: Colors.white54, fontSize: 14),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ControlButton(
                icon: Icons.call_end_rounded,
                label: 'Kataa',
                color: const Color(0xFFE53935),
                size: 64,
                onTap: () => Navigator.of(context).pop(),
              ),
              _ControlButton(
                icon: Icons.call_rounded,
                label: 'Pokea',
                color: const Color(0xFF43A047),
                size: 64,
                onTap: _acceptIncomingCall,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCallerAvatar() {
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (_, child) {
        final scale = 1.0 + (_pulseController.value * 0.08);
        return Transform.scale(
          scale: _isCallActive ? scale : 1.0,
          child: child,
        );
      },
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0xFF7C5CFC).withOpacity(0.2),
          border: Border.all(color: const Color(0xFF7C5CFC), width: 1.5),
        ),
        child: Center(
          child: Text(
            widget.callerName.isNotEmpty
                ? widget.callerName[0].toUpperCase()
                : '?',
            style: const TextStyle(
              color: Color(0xFF9D80FD),
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  void _showTranscriptSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0D1829),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Maneno yaliyosemwa',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Text(
              'Words spoken this call',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _inboundHistory.isEmpty
                  ? const Center(
                      child: Text(
                        'Hakuna maneno bado',
                        style: TextStyle(color: Colors.white24),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _inboundHistory.length,
                      itemBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF7C5CFC),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              _inboundHistory[i],
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPER WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

/// Scanning animation overlay shown on the camera while the user is signing
class _ScanOverlay extends StatefulWidget {
  const _ScanOverlay();

  @override
  State<_ScanOverlay> createState() => _ScanOverlayState();
}

class _ScanOverlayState extends State<_ScanOverlay>
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
      builder: (_, __) {
        return CustomPaint(painter: _ScanPainter(_ctrl.value));
      },
    );
  }
}

class _ScanPainter extends CustomPainter {
  final double progress;
  _ScanPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * progress;
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          const Color(0xFF00BCD4).withOpacity(0.7),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, y - 2, size.width, 4))
      ..strokeWidth = 2;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
  }

  @override
  bool shouldRepaint(_ScanPainter old) => old.progress != progress;
}

/// Audio waveform bar — shows caller's voice activity
class _AudioWaveBar extends StatelessWidget {
  final double level;
  final AnimationController controller;

  const _AudioWaveBar({required this.level, required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        return Row(
          children: List.generate(5, (i) {
            final wave = math.sin(
              (controller.value * 2 * math.pi) + (i * 0.8),
            );
            final h = 6.0 + (level * 20 * (0.4 + 0.6 * ((wave + 1) / 2)));
            return Container(
              width: 3,
              height: h.clamp(4.0, 26.0),
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(
                color: level > 0.1
                    ? const Color(0xFF7C5CFC)
                    : Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        );
      },
    );
  }
}

/// Circular icon button for call controls
class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final double size;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.size = 48,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.15),
              border: Border.all(color: color.withOpacity(0.5)),
            ),
            child: Icon(icon, color: color, size: size * 0.44),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }
}
