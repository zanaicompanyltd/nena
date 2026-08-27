import 'dart:math' as math;
import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AvatarWidget — Stream B visual output layer.
//
// Displays an animated stick-figure avatar performing a sign for a given
// Swahili word. Each word maps to a named animation sequence.
//
// In Phase 3 (production), replace the stick-figure with a Unity 3D avatar
// or a pre-recorded video dictionary clip. For now this serves as a
// functional animated placeholder that proves the pipeline works.
// ─────────────────────────────────────────────────────────────────────────────

class AvatarWidget extends StatefulWidget {
  /// The Swahili word to sign. Drives the animation selection.
  final String? word;

  /// If true, shows a compact version (for in-call overlay).
  /// If false, shows the full-screen avatar.
  final bool compact;

  const AvatarWidget({
    super.key,
    this.word,
    this.compact = false,
  });

  @override
  State<AvatarWidget> createState() => _AvatarWidgetState();
}

class _AvatarWidgetState extends State<AvatarWidget>
    with TickerProviderStateMixin {
  late AnimationController _bodyController;
  late AnimationController _handController;
  late AnimationController _fadeController;

  late Animation<double> _leftHandX;
  late Animation<double> _leftHandY;
  late Animation<double> _rightHandX;
  late Animation<double> _rightHandY;
  late Animation<double> _bodyTilt;
  late Animation<double> _fadeAnim;

  String? _currentWord;

  // ── Sign animation definitions ────────────────────────────────────────────
  // Each entry defines hand target positions relative to body center.
  // Format: [leftX, leftY, rightX, rightY, bodyTilt]
  // These are approximate representations — replace with real TSL keyframes.
  static const Map<String, List<double>> _signPositions = {
    'habari':   [-0.35, -0.20,  0.35, -0.20,  0.0],  // Both hands raised — greeting
    'asante':   [-0.10, -0.05,  0.10, -0.35,  0.0],  // Right hand to chest
    'msaada':   [-0.40,  0.05,  0.40,  0.05,  0.0],  // Both hands extended out
    'ndiyo':    [-0.12,  0.10,  0.12, -0.30,  0.05], // Nod + fist
    'hapana':   [-0.35,  0.00,  0.35,  0.00, -0.05], // Both hands wave outward
    'maji':     [-0.15,  0.05,  0.10, -0.15,  0.0],  // Fingers to mouth
    'chakula':  [-0.10,  0.05,  0.10, -0.20,  0.0],  // Hand to mouth (eating)
    'daktari':  [-0.30, -0.10,  0.30, -0.10,  0.0],  // Both hands raised — D sign
    'simu':     [-0.15,  0.10,  0.30, -0.30,  0.0],  // Hand to ear — phone sign
    'piga':     [-0.15,  0.05,  0.35, -0.15, -0.05], // Forward push
    'sawa':     [-0.10,  0.10,  0.10, -0.20,  0.0],  // OK gesture
    'pole':     [-0.10,  0.00,  0.10, -0.30,  0.0],  // Hand to heart — sorry
    'karibu':   [-0.30, -0.10,  0.30, -0.10,  0.0],  // Welcome — open arms
    'kwaheri':  [-0.10,  0.10,  0.35, -0.25,  0.05], // Wave goodbye
    'default':  [-0.18,  0.15,  0.18,  0.15,  0.0],  // Rest position
  };

  @override
  void initState() {
    super.initState();

    _bodyController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _handController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeIn);

    _initAnimations('default');
    _fadeController.forward();
  }

  @override
  void didUpdateWidget(AvatarWidget old) {
    super.didUpdateWidget(old);
    if (widget.word != old.word && widget.word != null) {
      _playSign(widget.word!);
    }
  }

  void _initAnimations(String word) {
    final key = word.toLowerCase();
    final pos = _signPositions[key] ?? _signPositions['default']!;

    final restPos = _signPositions['default']!;

    _leftHandX = Tween(begin: restPos[0], end: pos[0]).animate(
      CurvedAnimation(parent: _handController, curve: Curves.easeInOutCubic),
    );
    _leftHandY = Tween(begin: restPos[1], end: pos[1]).animate(
      CurvedAnimation(parent: _handController, curve: Curves.easeInOutCubic),
    );
    _rightHandX = Tween(begin: restPos[2], end: pos[2]).animate(
      CurvedAnimation(parent: _handController, curve: Curves.easeInOutCubic),
    );
    _rightHandY = Tween(begin: restPos[3], end: pos[3]).animate(
      CurvedAnimation(parent: _handController, curve: Curves.easeInOutCubic),
    );
    _bodyTilt = Tween(begin: 0.0, end: pos[4]).animate(
      CurvedAnimation(parent: _bodyController, curve: Curves.easeInOut),
    );
  }

  Future<void> _playSign(String word) async {
    _currentWord = word;

    // Fade out → update → fade in
    await _fadeController.reverse();

    _handController.reset();
    _bodyController.reset();
    _initAnimations(word);

    await Future.wait([
      _handController.forward(),
      _bodyController.forward(),
      _fadeController.forward(),
    ]);

    // Hold for 800ms then return to rest
    await Future.delayed(const Duration(milliseconds: 800));

    if (mounted && _currentWord == word) {
      _handController.reverse();
      _bodyController.reverse();
    }
  }

  @override
  void dispose() {
    _bodyController.dispose();
    _handController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.compact ? 140.0 : 260.0;

    return FadeTransition(
      opacity: _fadeAnim,
      child: AnimatedBuilder(
        animation: Listenable.merge([_handController, _bodyController]),
        builder: (_, __) {
          return SizedBox(
            width: size,
            height: size * 1.2,
            child: CustomPaint(
              painter: _AvatarPainter(
                leftHandX: _leftHandX.value,
                leftHandY: _leftHandY.value,
                rightHandX: _rightHandX.value,
                rightHandY: _rightHandY.value,
                bodyTilt: _bodyTilt.value,
                compact: widget.compact,
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom painter — draws the stick figure avatar
// ─────────────────────────────────────────────────────────────────────────────
class _AvatarPainter extends CustomPainter {
  final double leftHandX;
  final double leftHandY;
  final double rightHandX;
  final double rightHandY;
  final double bodyTilt;
  final bool compact;

  _AvatarPainter({
    required this.leftHandX,
    required this.leftHandY,
    required this.rightHandX,
    required this.rightHandY,
    required this.bodyTilt,
    required this.compact,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final scale = size.width;

    final bodyColor = const Color(0xFF00BCD4);
    final handColor = const Color(0xFF00897B);
    final jointColor = const Color(0xFF4DD0E1);

    final linePaint = Paint()
      ..color = bodyColor
      ..strokeWidth = compact ? 2.5 : 4.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final handPaint = Paint()
      ..color = handColor
      ..strokeWidth = compact ? 2.0 : 3.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final jointPaint = Paint()
      ..color = jointColor
      ..style = PaintingStyle.fill;

    final headPaint = Paint()
      ..color = bodyColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = compact ? 2.5 : 4.0;

    // ── Body proportions (relative to canvas) ────────────────────────────
    final headR   = scale * 0.13;
    final headY   = cy - scale * 0.35;
    final neckY   = headY + headR;
    final hipY    = cy + scale * 0.05;
    final kneeY   = cy + scale * 0.22;
    final footY   = cy + scale * 0.40;

    final shoulderOffset = scale * 0.18;
    final shoulderY = neckY + scale * 0.04;

    // Apply body tilt via canvas transform
    canvas.save();
    canvas.translate(cx, cy);
    canvas.rotate(bodyTilt);
    canvas.translate(-cx, -cy);

    // ── Head ────────────────────────────────────────────────────────────
    canvas.drawCircle(Offset(cx, headY), headR, headPaint);

    // ── Spine ───────────────────────────────────────────────────────────
    canvas.drawLine(
      Offset(cx, neckY),
      Offset(cx, hipY),
      linePaint,
    );

    // ── Legs ────────────────────────────────────────────────────────────
    canvas.drawLine(Offset(cx, hipY), Offset(cx - scale * 0.12, kneeY), linePaint);
    canvas.drawLine(Offset(cx, hipY), Offset(cx + scale * 0.12, kneeY), linePaint);
    canvas.drawLine(Offset(cx - scale * 0.12, kneeY), Offset(cx - scale * 0.14, footY), linePaint);
    canvas.drawLine(Offset(cx + scale * 0.12, kneeY), Offset(cx + scale * 0.14, footY), linePaint);

    // ── Shoulder line ────────────────────────────────────────────────────
    canvas.drawLine(
      Offset(cx - shoulderOffset, shoulderY),
      Offset(cx + shoulderOffset, shoulderY),
      linePaint,
    );

    canvas.restore();

    // ── Arms + hands (not tilted — move independently) ──────────────────
    final shoulderL = Offset(cx - shoulderOffset, shoulderY);
    final shoulderR = Offset(cx + shoulderOffset, shoulderY);

    final elbowL = Offset(
      cx + leftHandX * scale * 0.7,
      shoulderY + leftHandY * scale * 0.6,
    );
    final elbowR = Offset(
      cx + rightHandX * scale * 0.7,
      shoulderY + rightHandY * scale * 0.6,
    );

    final handL = Offset(
      cx + leftHandX * scale,
      shoulderY + leftHandY * scale,
    );
    final handR = Offset(
      cx + rightHandX * scale,
      shoulderY + rightHandY * scale,
    );

    // Upper arms
    canvas.drawLine(shoulderL, elbowL, handPaint);
    canvas.drawLine(shoulderR, elbowR, handPaint);
    // Forearms
    canvas.drawLine(elbowL, handL, handPaint);
    canvas.drawLine(elbowR, handR, handPaint);

    // Elbow joints
    final r = compact ? 3.5 : 5.0;
    canvas.drawCircle(elbowL, r, jointPaint);
    canvas.drawCircle(elbowR, r, jointPaint);

    // Hands (filled circles)
    final handR2 = compact ? 5.0 : 8.0;
    canvas.drawCircle(handL, handR2, Paint()..color = handColor);
    canvas.drawCircle(handR, handR2, Paint()..color = handColor);
  }

  @override
  bool shouldRepaint(_AvatarPainter old) =>
      old.leftHandX != leftHandX ||
      old.leftHandY != leftHandY ||
      old.rightHandX != rightHandX ||
      old.rightHandY != rightHandY ||
      old.bodyTilt != bodyTilt;
}
