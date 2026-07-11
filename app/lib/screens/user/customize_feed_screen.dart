import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state_providers.dart';

/// Settings screen where users can toggle personalization features
/// on their home screen feed (Time-of-Day greeting, personalized
/// suggestions, quick reorder, and future features).
class CustomizeFeedScreen extends ConsumerWidget {
  const CustomizeFeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(feedPreferencesProvider);
    final disabledCount = prefs.disabledCount;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(context, disabledCount),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // ── Section: Home Screen Features ──
          _buildSectionHeader(context, 'Home Screen Features'),
          const SizedBox(height: 4),

          _buildFeatureToggle(
            context: context,
            icon: Icons.wb_sunny_outlined,
            iconColor: const Color(0xFFF9A825),
            title: 'Time-of-Day Greeting',
            subtitle: 'Show a personalized greeting (Good Morning ☀️) and meal-type suggestions based on the current time',
            value: prefs.timeOfDayEnabled,
            onChanged: (v) => ref.read(feedPreferencesProvider.notifier).setTimeOfDayEnabled(v),
          ),

          _buildFeatureToggle(
            context: context,
            icon: Icons.recommend_outlined,
            iconColor: const Color(0xFF1967D2),
            title: 'Personalized Suggestions',
            subtitle: 'Show food recommendations based on your order history and favorite cuisines',
            value: prefs.personalizedSuggestionsEnabled,
            onChanged: (v) => ref.read(feedPreferencesProvider.notifier).setPersonalizedSuggestionsEnabled(v),
          ),

          _buildFeatureToggle(
            context: context,
            icon: Icons.replay_rounded,
            iconColor: const Color(0xFFBB0018),
            title: 'Quick Reorder',
            subtitle: 'Show your recent orders so you can quickly reorder with one tap',
            value: prefs.quickReorderEnabled,
            onChanged: (v) => ref.read(feedPreferencesProvider.notifier).setQuickReorderEnabled(v),
          ),

          const SizedBox(height: 24),

          // ── Info card ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F8FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF1967D2).withValues(alpha: 0.15),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline,
                    size: 20, color: Color(0xFF1967D2)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'About Personalized Feed',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1C1C),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Turning off a feature removes it from your home screen. '
                        'Your preferences are saved locally and can be changed anytime.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Reset to defaults ──
          if (disabledCount > 0)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  ref.read(feedPreferencesProvider.notifier).resetToDefaults();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Feed preferences reset to defaults'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                label: const Text('Reset to Defaults'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFBB0018),
                  side: const BorderSide(color: Color(0xFFBB0018)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // App Bar
  // ──────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(BuildContext context, int disabledCount) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(56),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Color(0x0C000000),
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.maybePop(context),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_back_ios_new_rounded,
                        size: 16, color: Color(0xFF1A1A1A)),
                  ),
                ),
                const Spacer(),
                const Text(
                  'Customize Feed',
                  style: TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                // Badge showing how many features are disabled
                if (disabledCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1F0),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$disabledCount off',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFBB0018),
                      ),
                    ),
                  )
                else
                  const SizedBox(width: 36),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Section Header
  // ──────────────────────────────────────────────

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF8E8E93),
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Feature Toggle
  // ──────────────────────────────────────────────

  Widget _buildFeatureToggle({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value
              ? const Color(0xFFF0F0F0)
              : const Color(0xFFFFF1F0),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 22, color: iconColor),
          ),
          const SizedBox(width: 14),
          // Text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1C1C),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF8E8E93),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Toggle
          SizedBox(
            height: 32,
            child: Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeThumbColor: const Color(0xFFBB0018),
              activeTrackColor: const Color(0xFFBB0018).withValues(alpha: 0.3),
            ),
          ),
        ],
      ),
    );
  }
}
