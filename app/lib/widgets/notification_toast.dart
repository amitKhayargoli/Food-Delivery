import 'dart:async';
import 'package:flutter/material.dart';
import '../injection_container.dart' as di;

/// Shows a notification toast that slides in from the top of the screen
/// as an overlay entry. Auto-dismisses after [duration].
///
/// Returns a function that can be called to dismiss the toast early.
void Function() showNotificationToast({
  required String title,
  required String body,
  String? type,
  Duration duration = const Duration(seconds: 4),
}) {
  final navigatorKey = di.sl<GlobalKey<NavigatorState>>();
  final ctx = navigatorKey.currentContext;
  if (ctx == null) return () {};

  OverlayEntry? overlayEntry;
  Timer? timer;

  void dismiss() {
    timer?.cancel();
    overlayEntry?.remove();
    overlayEntry = null;
  }

  overlayEntry = OverlayEntry(
    builder: (context) => _NotificationToastOverlay(
      title: title,
      body: body,
      type: type,
      onDismiss: dismiss,
      onAppeared: () {
        timer = Timer(duration, dismiss);
      },
    ),
  );

  Overlay.of(ctx).insert(overlayEntry!);

  return dismiss;
}

// ──────────────────────────────────────────────
//  Toast Widget
// ──────────────────────────────────────────────

class _NotificationToastOverlay extends StatefulWidget {
  final String title;
  final String body;
  final String? type;
  final VoidCallback onDismiss;
  final VoidCallback onAppeared;

  const _NotificationToastOverlay({
    required this.title,
    required this.body,
    this.type,
    required this.onDismiss,
    required this.onAppeared,
  });

  @override
  State<_NotificationToastOverlay> createState() =>
      _NotificationToastOverlayState();
}

class _NotificationToastOverlayState extends State<_NotificationToastOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.3, curve: Curves.easeIn),
    ));

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onAppeared();
      }
    });

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  IconData _iconForType(String? type) {
    switch (type) {
      case 'order_update':
        return Icons.receipt_long_rounded;
      case 'order_cancelled':
        return Icons.cancel_outlined;
      case 'promotion':
        return Icons.local_offer_rounded;
      case 'rider_declined':
      case 'rider_timeout':
      case 'reassignment_failed':
        return Icons.moped_rounded;
      case 'role_change':
        return Icons.swap_horiz_rounded;
      default:
        return Icons.notifications_active_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final theme = Theme.of(context);

    return Positioned(
      top: 0,
      left: 12,
      right: 12,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => Opacity(
          opacity: _fadeAnimation.value,
          child: Transform.translate(
            offset: Offset(
              0,
              _slideAnimation.value.dy * 100 + topPadding + 8,
            ),
            child: child,
          ),
        ),
        child: Material(
          elevation: 8,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(14),
          color: theme.brightness == Brightness.dark
              ? const Color(0xFF2C2C2E)
              : Colors.white,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: widget.onDismiss,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: theme.brightness == Brightness.dark
                      ? const Color(0xFF3A3A3C)
                      : const Color(0xFFE5E7EB),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Icon
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1F0),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _iconForType(widget.type),
                      size: 20,
                      color: const Color(0xFFBB0018),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A1C1C),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.body,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF5C5C5C),
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // Close button
                  GestureDetector(
                    onTap: widget.onDismiss,
                    child: Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F5F5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(
                        Icons.close_rounded,
                        size: 16,
                        color: Color(0xFF8E8E93),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
