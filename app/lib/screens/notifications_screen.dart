import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/notification_provider.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  String? get _token => context.read<AuthProvider>().token;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetch();
    });
  }

  Future<void> _fetch() async {
    final token = _token;
    if (token == null) return;
    context.read<NotificationProvider>().fetchNotifications(token);
  }

  @override
  Widget build(BuildContext context) {
    final notifProvider = context.watch<NotificationProvider>();
    final notifications = notifProvider.notifications;

    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F9),
      appBar: AppBar(
        title: const Text(
          'Notifications',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1C1C),
        elevation: 0.5,
        actions: [
          if (notifProvider.hasUnread)
            TextButton(
              onPressed: () {
                final token = _token;
                if (token != null) {
                  notifProvider.markAllAsRead(token);
                }
              },
              child: const Text(
                'Mark all read',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFBB0018),
                ),
              ),
            ),
        ],
      ),
      body: notifProvider.isLoading && notifications.isEmpty
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFBB0018)),
            )
          : notifications.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _fetch,
                  color: const Color(0xFFBB0018),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: notifications.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final notification = notifications[index];
                      return _buildNotificationCard(notification, notifProvider);
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F0),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.notifications_off_rounded,
              size: 36,
              color: Color(0xFFBB0018),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'No notifications yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1C1C),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'We\'ll notify you when something happens',
            style: TextStyle(
              fontSize: 14,
              color: Color(0xFF8E8E93),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationCard(
    AppNotification notification,
    NotificationProvider provider,
  ) {
    final token = _token;

    return GestureDetector(
      onTap: () {
        if (token != null && !notification.isRead) {
          provider.markAsRead(notification.id, token);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: notification.isRead ? Colors.white : const Color(0xFFFFF8F8),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: notification.isRead
                ? const Color(0xFFF0F0F0)
                : const Color(0xFFFFE0E0),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: notification.isRead
                    ? const Color(0xFFF5F5F5)
                    : const Color(0xFFFFF1F0),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _iconForType(notification.type),
                size: 22,
                color: notification.isRead
                    ? const Color(0xFF8E8E93)
                    : const Color(0xFFBB0018),
              ),
            ),
            const SizedBox(width: 12),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: notification.isRead
                                ? FontWeight.w500
                                : FontWeight.w700,
                            color: notification.isRead
                                ? const Color(0xFF5C5C5C)
                                : const Color(0xFF1A1C1C),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!notification.isRead)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(left: 6),
                          decoration: const BoxDecoration(
                            color: Color(0xFFF5222D),
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification.body,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF8E8E93),
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _timeAgo(notification.createdAt),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFBFBFBF),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconForType(String type) {
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

  String _timeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
  }
}
