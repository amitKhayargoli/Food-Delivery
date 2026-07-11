import 'package:flutter/material.dart';

/// A card that displays the rider's profile information and action buttons
/// (call & message).
///
/// Designed to sit below the [TimeStatusCard] in the order detail screen.
class RiderProfileCard extends StatelessWidget {
  final String riderName;
  final String? avatarUrl;
  final double rating;
  final int deliveryCount;
  final String vehicleInfo;
  final VoidCallback? onCall;
  final VoidCallback? onMessage;

  const RiderProfileCard({
    super.key,
    required this.riderName,
    this.avatarUrl,
    this.rating = 4.8,
    this.deliveryCount = 0,
    this.vehicleInfo = '',
    this.onCall,
    this.onMessage,
  });

  static const Color _brandRed = Color(0xFFF5222D);
  static const Color _cardBg = Color(0xFFFAF9F9);
  static const Color _borderColor = Color(0xFFE8E8E8);
  static const Color _textDim = Color(0xFF595959);
  static const Color _textDark = Color(0xFF1A1A1A);
  static const Color _avatarBorder = Color(0xFFE8E8E8);
  static const Color _actionBtnBg = Color(0xFFE8E8E8);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          // ── Avatar + Name/Rating/Vehicle ──
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Avatar stack (image + online indicator)
                _buildAvatar(),
                const SizedBox(width: 16),
                // Name / Rating / Vehicle
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Rider name
                      Text(
                        riderName,
                        style: const TextStyle(
                          color: _textDark,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // Rating + delivery count (only show when we have real data)
                      if (deliveryCount > 0 || rating > 0)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.star_rounded,
                                size: 14, color: Color(0xFFF9A825)),
                            const SizedBox(width: 2),
                            Text(
                              rating.toStringAsFixed(1),
                              style: const TextStyle(
                                color: _textDark,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 4),
                            if (deliveryCount > 0)
                              Text(
                                '($deliveryCount deliveries)',
                                style: const TextStyle(
                                  color: _textDim,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      // Vehicle info
                      if (vehicleInfo.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          vehicleInfo,
                          style: const TextStyle(
                            color: _textDim,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Action Buttons ──
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Message button (placeholder, shows disabled state when null)
              _actionButton(
                icon: Icons.chat_bubble_outline_rounded,
                bgColor: onMessage != null ? _actionBtnBg : _actionBtnBg.withValues(alpha: 0.5),
                iconColor: onMessage != null ? _textDark : _textDark.withValues(alpha: 0.3),
                onTap: onMessage,
              ),
              const SizedBox(width: 8),
              // Call button
              _actionButton(
                icon: Icons.phone_rounded,
                bgColor: _brandRed,
                iconColor: Colors.white,
                onTap: onCall,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    return Stack(
      children: [
        // Avatar image
        Container(
          width: 58,
          height: 64,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: _avatarBorder, width: 2),
            image: avatarUrl != null && avatarUrl!.isNotEmpty
                ? DecorationImage(
                    image: NetworkImage(avatarUrl!),
                    fit: BoxFit.cover,
                  )
                : null,
            color: const Color(0xFFFFF1F0),
          ),
          child: (avatarUrl == null || avatarUrl!.isEmpty)
              ? const Icon(Icons.person_rounded,
                  size: 28, color: Color(0xFFBFBFBF))
              : null,
        ),
        // Online indicator dot
        Positioned(
          right: 0,
          bottom: 2,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: const Color(0xFF52C41A),
              shape: BoxShape.circle,
              border: Border.all(color: _cardBg, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required Color bgColor,
    required Color iconColor,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
          boxShadow: onTap != null
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Icon(icon, size: 20, color: iconColor),
      ),
    );
  }
}
