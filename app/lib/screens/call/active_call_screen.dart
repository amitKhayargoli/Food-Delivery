import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/call_provider.dart';
import '../../models/call.dart';

/// Full-screen active call interface showing:
/// - Call duration
/// - Mute / Speaker controls
/// - Hang-up button
/// - Callee/Caller info
class ActiveCallScreen extends StatefulWidget {
  const ActiveCallScreen({super.key});

  @override
  State<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends State<ActiveCallScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CallProvider>();
    final call = provider.activeCall;
    final callerName = call?.callerName ?? call?.calleeName ?? 'Connecting...';
    final isMuted = provider.isMuted;
    final isSpeakerOn = provider.isSpeakerOn;
    final duration = provider.callDuration;
    final isConnected = call?.status == CallStatus.connected;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1C1C),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),

            // ── Pulsing avatar while ringing ──
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: isConnected ? 1.0 : _pulseAnimation.value,
                  child: child,
                );
              },
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5222D).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isConnected
                        ? const Color(0xFF34C759)
                        : const Color(0xFFF5222D).withValues(alpha: 0.5),
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.person_rounded,
                  size: 44,
                  color: Colors.white,
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ── Name ──
            Text(
              callerName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w700,
              ),
            ),

            const SizedBox(height: 8),

            // ── Status / Duration ──
            Text(
              isConnected ? duration : 'Ringing...',
              style: TextStyle(
                color: isConnected
                    ? const Color(0xFF8E8E93)
                    : const Color(0xFF34C759),
                fontSize: 16,
                fontWeight: isConnected ? FontWeight.w400 : FontWeight.w500,
              ),
            ),

            const Spacer(flex: 2),

            // ── Control buttons ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Mute
                  _buildControlButton(
                    icon: isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    label: isMuted ? 'Unmute' : 'Mute',
                    isActive: isMuted,
                    activeColor: const Color(0xFFF5222D),
                    onTap: () => provider.toggleMute(),
                  ),

                  // Speaker
                  _buildControlButton(
                    icon: isSpeakerOn
                        ? Icons.volume_up_rounded
                        : Icons.volume_down_rounded,
                    label: isSpeakerOn ? 'Speaker' : 'Earpiece',
                    isActive: isSpeakerOn,
                    activeColor: const Color(0xFF007AFF),
                    onTap: () => provider.toggleSpeaker(),
                  ),
                ],
              ),
            ),

            const Spacer(flex: 1),

            // ── Hang-up button ──
            GestureDetector(
              onTap: () async {
                await provider.endCall();
                if (context.mounted) {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                }
              },
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF3B30),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF3B30).withValues(alpha: 0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.call_end_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
            ),

            const SizedBox(height: 16),
            const Text(
              'Tap to end call',
              style: TextStyle(
                color: Color(0xFF8E8E93),
                fontSize: 13,
              ),
            ),

            const Spacer(flex: 1),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isActive
                  ? activeColor.withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: isActive
                  ? Border.all(color: activeColor.withValues(alpha: 0.5), width: 1.5)
                  : null,
            ),
            child: Icon(
              icon,
              color: isActive ? activeColor : Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: isActive ? activeColor : const Color(0xFF8E8E93),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
