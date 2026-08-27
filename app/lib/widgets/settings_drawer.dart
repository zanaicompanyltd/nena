import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/voice_profile_provider.dart';

/// Settings Drawer (Option A in the UI layout).
/// Lets the user pick Male or Female voice profile.
/// This is the "Application Settings Profile Topology" from Section 3.3.
class SettingsDrawer extends StatelessWidget {
  const SettingsDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final profileProvider = context.watch<VoiceProfileProvider>();

    return Drawer(
      backgroundColor: const Color(0xFF1A2332),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────
              const Text(
                'Nena',
                style: TextStyle(
                  color: Color(0xFF00BCD4),
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              const Text(
                'Mipangilio ya Sauti',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 13,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Voice Settings',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
              const Divider(color: Colors.white12, height: 40),

              // ── Voice Profile Label ──────────────────
              const Text(
                'VOICE PROFILE',
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 11,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),

              // ── Female Profile Button ────────────────
              _ProfileTile(
                label: 'Female Voice',
                sublabel: 'Sauti ya Kike',
                icon: Icons.person_outline,
                accentColor: const Color(0xFFE91E8C),
                isSelected: profileProvider.isFemale,
                onTap: () => profileProvider.setProfile('Female'),
              ),
              const SizedBox(height: 12),

              // ── Male Profile Button ──────────────────
              _ProfileTile(
                label: 'Male Voice',
                sublabel: 'Sauti ya Kiume',
                icon: Icons.person,
                accentColor: const Color(0xFF1E90E9),
                isSelected: profileProvider.isMale,
                onTap: () => profileProvider.setProfile('Male'),
              ),

              const Divider(color: Colors.white12, height: 48),

              // ── Current selection indicator ──────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    Icon(
                      profileProvider.isMale
                          ? Icons.volume_up
                          : Icons.volume_up_outlined,
                      color: profileProvider.isMale
                          ? const Color(0xFF1E90E9)
                          : const Color(0xFFE91E8C),
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Active Profile',
                          style: TextStyle(
                            color: Colors.white38,
                            fontSize: 10,
                            letterSpacing: 1,
                          ),
                        ),
                        Text(
                          '${profileProvider.voiceProfile} Voice',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // ── Footer ──────────────────────────────
              const Text(
                'TSL / KSL → Swahili\nMultimodal CLIP Architecture',
                style: TextStyle(
                  color: Colors.white24,
                  fontSize: 10,
                  height: 1.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Individual selectable profile tile
class _ProfileTile extends StatelessWidget {
  final String label;
  final String sublabel;
  final IconData icon;
  final Color accentColor;
  final bool isSelected;
  final VoidCallback onTap;

  const _ProfileTile({
    required this.label,
    required this.sublabel,
    required this.icon,
    required this.accentColor,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? accentColor.withOpacity(0.15)
              : Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? accentColor : Colors.white12,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? accentColor : Colors.white38, size: 22),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  sublabel,
                  style: TextStyle(
                    color: isSelected ? accentColor : Colors.white38,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const Spacer(),
            if (isSelected)
              Icon(Icons.check_circle, color: accentColor, size: 18),
          ],
        ),
      ),
    );
  }
}
