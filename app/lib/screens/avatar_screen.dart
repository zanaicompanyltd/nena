import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/voice_profile_provider.dart';
import '../services/voip_service.dart';
import '../services/whisper_service.dart';
import '../widgets/avatar_widget.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AvatarScreen — Stream B full-screen inbound display.
//
// Shown when the Deaf user wants to watch the caller's words being signed
// in full-screen mode (instead of the compact overlay in CallScreen).
//
// Layout:
// ┌────────────────────────────────┐
// │  [Back]   Caller speaking      │  ← Top bar
// ├────────────────────────────────┤
// │                                │
// │       🤟 Stick avatar          │  ← Centre: animated signing
// │       animating the sign       │
// │                                │
// ├────────────────────────────────┤
// │  Current word:  HABARI         │  ← Word display (large)
// ├────────────────────────────────┤
// │  habari  asante  msaada ...    │  ← Scrollable word history
// └────────────────────────────────┘
// ─────────────────────────────────────────────────────────────────────────────

class AvatarScreen extends StatefulWidget {
  /// Provide a VoipService that is already connected to a live call.
  /// AvatarScreen subscribes to its inboundTextStream.
  final VoipService voipService;
  final String callerName;

  const AvatarScreen({
    super.key,
    required this.voipService,
    required this.callerName,
  });

  @override
  State<AvatarScreen> createState() => _AvatarScreenState();
}

class _AvatarScreenState extends State<AvatarScreen>
    with SingleTickerProviderStateMixin {
  final _whisperService = WhisperService();

  // ── State ─────────────────────────────────────────────────────────────────
  String? _currentWord;               // Word the avatar is currently signing
  List<String> _wordHistory = [];     // Full transcript of received words
  StreamSubscription<String>? _sub;

  // ── Animation for word flash ──────────────────────────────────────────────
  late AnimationController _flashController;
  late Animation<double> _flashAnim;

  @override
  void initState() {
    super.initState();

    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _flashAnim = CurvedAnimation(
      parent: _flashController,
      curve: Curves.easeOut,
    );

    // Subscribe to Stream B — each emitted word drives the avatar
    _sub = widget.voipService.inboundTextStream.listen(_onWordReceived);
  }

  void _onWordReceived(String word) {
    if (!mounted) return;

    // Extract meaningful keywords before sending to avatar
    final keywords = _whisperService.extractKeywords(word);
    final display = keywords.isNotEmpty ? keywords.first : word;

    setState(() {
      _currentWord = display;
      _wordHistory.insert(0, display);
      if (_wordHistory.length > 30) _wordHistory.removeLast();
    });

    // Flash animation on new word
    _flashController.forward(from: 0);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _flashController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF060D17),
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar ────────────────────────────────────────────────
            _buildTopBar(context),

            // ── Avatar zone (centre, takes most space) ─────────────────
            Expanded(
              flex: 6,
              child: _buildAvatarZone(),
            ),

            // ── Current word display ───────────────────────────────────
            _buildWordDisplay(),

            // ── Scrollable word history ────────────────────────────────
            Expanded(
              flex: 2,
              child: _buildWordHistory(),
            ),

            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  // ── Widget builders ───────────────────────────────────────────────────────

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Back to call screen
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white70, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 8),
          Column(
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
              const Text(
                'Inasadifu ishara...',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
          const Spacer(),
          // Live indicator
          _LivePulse(isActive: _currentWord != null),
        ],
      ),
    );
  }

  Widget _buildAvatarZone() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1829),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: _currentWord != null
              ? const Color(0xFF00BCD4).withOpacity(0.3)
              : Colors.white.withOpacity(0.05),
        ),
      ),
      child: Center(
        child: _currentWord == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.front_hand_outlined,
                      color: Colors.white12, size: 48),
                  SizedBox(height: 12),
                  Text(
                    'Ngoja mwenzako aongee...',
                    style: TextStyle(color: Colors.white24, fontSize: 13),
                  ),
                  Text(
                    'Waiting for caller to speak',
                    style: TextStyle(color: Colors.white12, fontSize: 11),
                  ),
                ],
              )
            : AvatarWidget(
                word: _currentWord,
                compact: false,
              ),
      ),
    );
  }

  Widget _buildWordDisplay() {
    return AnimatedBuilder(
      animation: _flashAnim,
      builder: (_, __) {
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          decoration: BoxDecoration(
            color: Color.lerp(
              const Color(0xFF0D1829),
              const Color(0xFF00897B).withOpacity(0.2),
              _flashAnim.value,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Color.lerp(
                Colors.white.withOpacity(0.06),
                const Color(0xFF00BCD4).withOpacity(0.6),
                _flashAnim.value,
              )!,
            ),
          ),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'NENO LA SASA',
                    style: TextStyle(
                      color: Colors.white24,
                      fontSize: 10,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _currentWord?.toUpperCase() ?? '—',
                    style: TextStyle(
                      color: _currentWord != null
                          ? Colors.white
                          : Colors.white24,
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              if (_currentWord != null)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF00897B).withOpacity(0.2),
                  ),
                  child: const Icon(
                    Icons.sign_language_outlined,
                    color: Color(0xFF00BCD4),
                    size: 22,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWordHistory() {
    if (_wordHistory.isEmpty) {
      return const Center(
        child: Text(
          'Maneno yataonekana hapa',
          style: TextStyle(color: Colors.white12, fontSize: 12),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'HISTORIA',
            style: TextStyle(
              color: Colors.white24,
              fontSize: 10,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _wordHistory.asMap().entries.map((entry) {
                  final i = entry.key;
                  final word = entry.value;
                  final isLatest = i == 0;

                  return GestureDetector(
                    // Tap a history word to replay its sign
                    onTap: () => setState(() => _currentWord = word),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isLatest
                            ? const Color(0xFF00897B).withOpacity(0.2)
                            : Colors.white.withOpacity(0.04),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isLatest
                              ? const Color(0xFF00BCD4).withOpacity(0.5)
                              : Colors.white.withOpacity(0.08),
                        ),
                      ),
                      child: Text(
                        word,
                        style: TextStyle(
                          color: isLatest
                              ? const Color(0xFF00BCD4)
                              : Colors.white38,
                          fontSize: 13,
                          fontWeight: isLatest
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper: pulsing live indicator dot
// ─────────────────────────────────────────────────────────────────────────────
class _LivePulse extends StatefulWidget {
  final bool isActive;
  const _LivePulse({required this.isActive});

  @override
  State<_LivePulse> createState() => _LivePulseState();
}

class _LivePulseState extends State<_LivePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
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
      builder: (_, __) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.isActive
                  ? Color.fromRGBO(0, 188, 212,
                      0.4 + 0.6 * _ctrl.value)
                  : Colors.white24,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            widget.isActive ? 'LIVE' : 'PAUSE',
            style: TextStyle(
              color: widget.isActive
                  ? const Color(0xFF00BCD4)
                  : Colors.white24,
              fontSize: 10,
              letterSpacing: 1.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
