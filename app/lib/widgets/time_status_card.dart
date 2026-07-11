import 'package:flutter/material.dart';
import '../models/order.dart';

/// A card that displays the estimated arrival time, a 3-segment progress bar
/// (Accepted → On the way → Delivered), and step labels.
///
/// Designed to sit below the live tracking map in the order detail screen.
class TimeStatusCard extends StatelessWidget {
  final int etaMinutes;
  final OrderStatus currentStatus;

  const TimeStatusCard({
    super.key,
    required this.etaMinutes,
    required this.currentStatus,
  });

  /// Which of the 3 steps is currently active (0, 1, or 2).
  /// `null` when the order is cancelled.
  int? get _activeStep {
    switch (currentStatus) {
      case OrderStatus.created:
      case OrderStatus.accepted:
      case OrderStatus.preparing:
        return 0;
      case OrderStatus.outForDelivery:
      case OrderStatus.pickedUp:
        return 1;
      case OrderStatus.delivered:
        return 2;
      case OrderStatus.cancelled:
        return null;
    }
  }

  String get _etaDisplay {
    if (etaMinutes <= 0) return 'Calculating...';
    if (etaMinutes <= 1) return 'Arriving now';
    if (etaMinutes < 60) return '$etaMinutes mins';
    final h = etaMinutes ~/ 60;
    final m = etaMinutes % 60;
    return '${h}h ${m}m';
  }

  static const Color _brandRed = Color(0xFFF5222D);
  static const Color _cardBg = Color(0xFFFAF9F9);
  static const Color _borderColor = Color(0xFFE8E8E8);
  static const Color _textDim = Color(0xFF595959);
  static const Color _textDark = Color(0xFF1A1A1A);
  static const Color _pendingGray = Color(0xFFE8E8E8);

  @override
  Widget build(BuildContext context) {
    final activeStep = _activeStep;
    if (activeStep == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Estimated Arrival + Status Badge ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Estimated Arrival',
                      style: TextStyle(
                        color: _textDim,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _etaDisplay,
                      style: const TextStyle(
                        color: _textDark,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _brandRed,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _statusLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Progress Bar ──
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              width: double.infinity,
              height: 8,                  child: Row(
                    children: List.generate(3, (i) {
                      Color segmentColor;
                      if (i < activeStep) {
                        segmentColor = _brandRed; // completed
                      } else if (i == activeStep) {
                        segmentColor = _brandRed; // current
                      } else {
                        segmentColor = _pendingGray; // pending
                      }

                      final bool isCurrentStep =
                          (i == activeStep && currentStatus != OrderStatus.delivered);

                      return Expanded(
                        child: Container(
                          height: double.infinity,
                          decoration: BoxDecoration(
                            color: segmentColor,
                            border: isCurrentStep
                                ? Border.symmetric(
                                    vertical: BorderSide(
                                      color: _cardBg,
                                      width: 5,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                      );
                    }),
                  ),
            ),
          ),

          const SizedBox(height: 6),

          // ── Step Labels ──
          Row(
            children: [
              _stepLabel('Accepted', activeStep >= 0, _brandRed),
              const Spacer(),
              _stepLabel('On the way', activeStep >= 1, _brandRed),
              const Spacer(),
              _stepLabel('Delivered', activeStep >= 2, _brandRed),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stepLabel(String text, bool isActive, Color activeColor) {
    return Text(
      text,
      style: TextStyle(
        color: isActive ? activeColor : _textDim,
        fontSize: 12,
        fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
      ),
    );
  }

  String get _statusLabel {
    switch (currentStatus) {
      case OrderStatus.created:
        return 'Pending';
      case OrderStatus.accepted:
        return 'Accepted';
      case OrderStatus.preparing:
        return 'Preparing';
      case OrderStatus.outForDelivery:
        return 'Ready';
      case OrderStatus.pickedUp:
        return 'On the way';
      case OrderStatus.delivered:
        return 'Delivered';
      case OrderStatus.cancelled:
        return 'Cancelled';
    }
  }
}
