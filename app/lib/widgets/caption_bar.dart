import 'package:flutter/material.dart';

/// Captions & Audio Bar — bottom 40% of the screen.
/// Displays the predicted Swahili word in large bold text
/// and shows playback status.
class CaptionBar extends StatelessWidget {
  final String? predictedWord;
  final bool isSpeaking;
  final bool isListening;
  final VoidCallback? onReplay;

  const CaptionBar({
    super.key,
    this.predictedWord,
    required this.isSpeaking,
    required this.isListening,
    this.onReplay,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFF0D1B2A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(28, 20, 28, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Drag handle ─────────────────────────
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── Status label ────────────────────────
          Row(
            children: [
              _StatusDot(isActive: isListening),
              const SizedBox(width: 8),
              Text(
                isListening
                    ? 'INABIRI ISHARA...'       // "Reading sign..."
                    : isSpeaking
                        ? 'INASEMA...'          // "Speaking..."
                        : 'SUBIRI ISHARA',      // "Waiting for sign"
                style: const TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Main Swahili word display ────────────
          Expanded(
            child: Center(
              child: predictedWord != null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          predictedWord!,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 52,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1,
                            height: 1.0,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: 60,
                          height: 3,
                          decoration: BoxDecoration(
                            color: const Color(0xFF00BCD4),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ],
                    )
                  : const Text(
                      '—',
                      style: TextStyle(
                        color: Colors.white12,
                        fontSize: 52,
                        fontWeight: FontWeight.w100,
                      ),
                    ),
            ),
          ),

          // ── Replay button ───────────────────────
          if (predictedWord != null && onReplay != null)
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: onReplay,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00897B).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFF00897B)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.replay, color: Color(0xFF00BCD4), size: 16),
                      SizedBox(width: 6),
                      Text(
                        'Rudia', // "Repeat" in Swahili
                        style: TextStyle(
                          color: Color(0xFF00BCD4),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Animated pulsing status dot
class _StatusDot extends StatefulWidget {
  final bool isActive;
  const _StatusDot({required this.isActive});

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _opacity = Tween(begin: 0.3, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacity,
      builder: (_, __) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.isActive
              ? Color.fromRGBO(
                  0, 188, 212, _opacity.value) // Teal pulse when active
              : Colors.white24,
        ),
      ),
    );
  }
}
