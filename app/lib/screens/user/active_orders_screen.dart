import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../../models/order.dart';
import '../../core/services/api_service.dart';
import '../../core/services/supabase_client_service.dart';
import '../../injection_container.dart' as di;
import '../../providers/auth_provider.dart';
import 'order_detail_screen.dart';

class ActiveOrdersScreen extends StatefulWidget {
  const ActiveOrdersScreen({super.key});

  @override
  State<ActiveOrdersScreen> createState() => _ActiveOrdersScreenState();
}

class _ActiveOrdersScreenState extends State<ActiveOrdersScreen> {
  List<Order> _orders = [];
  bool _isLoading = true;
  String? _error;
  sb.RealtimeChannel? _orderChannel;

  String? get _token => context.read<AuthProvider>().token;
  String? get _userId => context.read<AuthProvider>().token != null
      ? SupabaseClientService.client.auth.currentUser?.id
      : null;

  @override
  void initState() {
    super.initState();
    _fetchOrders();
  }

  @override
  void dispose() {
    _unsubscribeFromOrders();
    super.dispose();
  }

  void _subscribeToOrders(String userId) {
    _unsubscribeFromOrders();
    _orderChannel = SupabaseClientService.client.channel('customer-orders-$userId');

    _orderChannel!.onPostgresChanges(
      event: sb.PostgresChangeEvent.insert,
      schema: 'public',
      table: 'orders',
      callback: (payload) {
        final record = payload.newRecord;
        if (record['user_id']?.toString() == userId) {
          _fetchOrders();
        }
      },
    );

    _orderChannel!.onPostgresChanges(
      event: sb.PostgresChangeEvent.update,
      schema: 'public',
      table: 'orders',
      callback: (payload) {
        final record = payload.newRecord;
        // Only re-fetch if this update is for the current user
        // We check if any of our displayed orders matches the updated order
        if (_orders.any((o) => o.id == record['id']?.toString())) {
          _fetchOrders();
        } else if (record['user_id']?.toString() == userId) {
          _fetchOrders();
        }
      },
    );

    _orderChannel!.subscribe((status, [error]) {
      debugPrint('[RT-CustomerOrders] Channel status: $status');
      if (error != null) debugPrint('[RT-CustomerOrders] Error: $error');
    });
  }

  void _unsubscribeFromOrders() {
    if (_orderChannel != null) {
      SupabaseClientService.client.removeChannel(_orderChannel!);
      _orderChannel = null;
    }
  }

  Future<void> _fetchOrders() async {
    final token = _token;
    if (token == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Not authenticated. Please log in.';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = di.sl<ApiService>();
      final rawOrders = await api.getMyOrders(token: token);
      if (!mounted) return;
      setState(() {
        _orders = rawOrders.map((o) => Order.fromJson(o)).toList();
        _isLoading = false;
      });
      // Subscribe to real-time updates after successful fetch
      final userId = _userId;
      if (userId != null) _subscribeToOrders(userId);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load orders. Check your connection.';
        _isLoading = false;
      });
    }
  }

  String _timeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _formatCurrency(double amount) {
    return 'Rs. ${amount.toStringAsFixed(0)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F9),
      appBar: AppBar(
        title: const Text(
          'My Orders',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1C1C),
        elevation: 0.5,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFFBB0018)),
            SizedBox(height: 16),
            Text(
              'Loading orders...',
              style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Color(0xFF8E8E93)),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 14),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _fetchOrders,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFBB0018),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_orders.isEmpty) {
      return RefreshIndicator(
        onRefresh: _fetchOrders,
        color: const Color(0xFFBB0018),
        child: ListView(
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.5,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.receipt_long_rounded,
                        size: 56, color: Color(0xFFD9D9D9)),
                    const SizedBox(height: 12),
                    const Text(
                      'No orders yet',
                      style: TextStyle(
                        color: Color(0xFF8E8E93),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Your orders will appear here once you place one',
                      style: TextStyle(
                        color: Color(0xFFBFBFBF),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchOrders,
      color: const Color(0xFFBB0018),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _orders.length,
        itemBuilder: (context, index) => _buildOrderCard(_orders[index]),
      ),
    );
  }

  Widget _buildOrderCard(Order order) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => OrderDetailScreen(
              order: order,
              isOwner: false,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x141B1C1C),
              blurRadius: 12,
              offset: Offset(0, 4),
              spreadRadius: 0,
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.receipt_long_rounded,
                        size: 18, color: Color(0xFFBB0018)),
                    const SizedBox(width: 8),
                    Text(
                      '#${order.orderNumber}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1C1C),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    _buildStatusBadge(order.status),
                    const SizedBox(width: 8),
                    Text(
                      _timeAgo(order.createdAt),
                      style: const TextStyle(
                        color: Color(0xFF5C5C5C),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...order.items.take(2).map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${item.quantity}x ${item.name}',
                          style: const TextStyle(fontSize: 13, color: Color(0xFF5C5C5C)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        _formatCurrency(item.price * item.quantity),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1C1C)),
                      ),
                    ],
                  ),
                )),
            if (order.items.length > 2)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '+${order.items.length - 2} more items',
                  style: const TextStyle(color: Color(0xFF5C5C5C), fontSize: 12),
                ),
              ),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF1A1C1C))),
                Text(
                  _formatCurrency(order.total),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFFBB0018)),
                ),
              ],
            ),
            if (order.deliveryAddress?.fullAddress != null)
              Row(
                children: [
                  const Icon(Icons.location_on_outlined, size: 14, color: Color(0xFF5C5C5C)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      order.deliveryAddress!.fullAddress!,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF5C5C5C)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(OrderStatus status) {
    Color bgColor;
    Color textColor;
    String label;

    switch (status) {
      case OrderStatus.pending:
        bgColor = const Color(0xFFFFF1F0);
        textColor = const Color(0xFFBB0018);
        label = 'Pending';
      case OrderStatus.accepted:
        bgColor = const Color(0xFFE8F0FE);
        textColor = const Color(0xFF1967D2);
        label = 'Accepted';
      case OrderStatus.preparing:
        bgColor = const Color(0xFFFFF8E1);
        textColor = const Color(0xFFF9A825);
        label = 'Preparing';
      case OrderStatus.ready:
        bgColor = const Color(0xFFE6F4EA);
        textColor = const Color(0xFF1E8E3E);
        label = 'Ready';
      case OrderStatus.pickedUp:
        bgColor = const Color(0xFFE8F0FE);
        textColor = const Color(0xFF1967D2);
        label = 'Picked Up';
      case OrderStatus.delivered:
        bgColor = const Color(0xFFE6F4EA);
        textColor = const Color(0xFF1E8E3E);
        label = 'Delivered';
      case OrderStatus.cancelled:
        bgColor = const Color(0xFFEFEDED);
        textColor = const Color(0xFF5E3F3C);
        label = 'Cancelled';
      case OrderStatus.rejected:
        bgColor = const Color(0xFFFFF1F0);
        textColor = const Color(0xFFBB0018);
        label = 'Rejected';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(9999),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textColor),
      ),
    );
  }
}
