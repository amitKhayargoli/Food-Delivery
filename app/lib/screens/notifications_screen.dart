import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../injection_container.dart' as di;
import '../../models/order.dart';
import '../../core/services/api_service.dart';
import '../providers/auth_provider.dart';
import '../providers/notification_provider.dart';
import 'user/order_detail_screen.dart';
import 'user/support_chat_screen.dart';

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
      onTap: () => _onNotificationTap(notification, token),
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

  /// Standard notification icon used for all notification types.
  IconData _iconForType(String type) {
    return Icons.notifications_active_rounded;
  }

  /// Handle tapping a notification — navigate to the relevant screen.
  Future<void> _onNotificationTap(
    AppNotification notification,
    String? token,
  ) async {
    // Mark as read first
    if (token != null && !notification.isRead) {
      context.read<NotificationProvider>().markAsRead(notification.id, token);
    }

    // Extract navigation data
    final data = notification.data;
    final orderId = data['order_id'] as String?;
    final conversationId = data['conversation_id'] as String?;
    final problemId = data['problem_id'] as String?;
    // Priority 1: Navigate to support chat if we have a conversation_id
    if (conversationId != null && conversationId.isNotEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SupportChatScreen(
            conversationId: conversationId,
            subject: notification.title,
            restaurantName: data['restaurant_name'] as String?,
          ),
        ),
      );
      return;
    }

    // Priority 2: Navigate to order detail if we have an order_id
    if (orderId != null && orderId.isNotEmpty) {
      await _navigateToOrder(orderId, type: notification.type);
      return;
    }

    // Priority 3: Navigate to order detail with problem_id
    if (problemId != null && problemId.isNotEmpty && orderId != null) {
      await _navigateToOrder(orderId, type: notification.type);
      return;
    }
  }

  /// Fetch an order by ID and navigate to [OrderDetailScreen].
  /// Falls back silently if the order can't be fetched.
  Future<void> _navigateToOrder(String orderId, {String? type}) async {
    if (_token == null) return;

    try {
      final api = di.sl<ApiService>();
      final orderData = await api.getOrderById(
        orderId: orderId,
        token: _token!,
      );

      if (orderData == null || !mounted) return;

      final order = Order.fromJson(orderData);

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => OrderDetailScreen(
            order: order,
            isOwner: type == 'rider_declined' ||
                type == 'rider_timeout' ||
                type == 'reassignment_failed',
          ),
        ),
      );
    } catch (_) {
      // Silently handle — user can still navigate manually
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
