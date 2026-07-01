import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/call.dart';
import '../../providers/call_provider.dart';
import 'active_call_screen.dart';

/// Full-screen incoming call notification.
/// Shows when someone is calling the current user.
class IncomingCallScreen extends StatelessWidget {
  final Call call;

  const IncomingCallScreen({super.key, required this.call});

  @override
  Widget build(BuildContext context) {
    final callerName = call.callerName ?? 'Caller';
    final callerRole = call.callerRole ?? 'User';
    final roleLabel = _formatRoleLabel(callerRole);

    return Scaffold(
      backgroundColor: const Color(0xFF1A1C1C),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),

            // ── Avatar ──
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: const Color(0xFFF5222D).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person_rounded,
                size: 48,
                color: Color(0xFFF5222D),
              ),
            ),

            const SizedBox(height: 24),

            // ── Caller name ──
            Text(
              callerName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),

            const SizedBox(height: 8),

            // ── Role label ──
            Text(
              '$roleLabel is calling...',
              style: const TextStyle(
                color: Color(0xFF8E8E93),
                fontSize: 16,
              ),
            ),

            const Spacer(flex: 1),

            // ── Action buttons ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Decline button
                  _buildActionButton(
                    context: context,
                    icon: Icons.call_end_rounded,
                    label: 'Decline',
                    color: const Color(0xFFFF3B30),
                    onTap: () {
                      context.read<CallProvider>().rejectCall();
                      Navigator.of(context).pop();
                    },
                  ),

                  // Accept button
                  _buildActionButton(
                    context: context,
                    icon: Icons.call_rounded,
                    label: 'Accept',
                    color: const Color(0xFF34C759),
                    onTap: () async {
                      final provider = context.read<CallProvider>();
                      final result = await provider.acceptCall();
                      if (result.success && context.mounted) {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => ActiveCallScreen(),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),

            const Spacer(flex: 1),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  String _formatRoleLabel(String role) {
    switch (role.toUpperCase()) {
      case 'DELIVERY_BOY':
        return 'Delivery Rider';
      case 'CUSTOMER':
      case 'USER':
        return 'Customer';
      case 'RESTAURANT_OWNER':
        return 'Restaurant Owner';
      default:
        return role;
    }
  }
}
