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

  // Track which order IDs have been rated so we can show "Rated" state
  final Set<String> _ratedOrderIds = {};
  bool _isFetchingRatings = false;
  bool _isSubmittingRating = false;

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

  /// Fetch the user's existing ratings to pre-fill [ratedOrderIds].
  Future<void> _fetchMyRatings() async {
    final token = _token;
    if (token == null || _isFetchingRatings) return;
    _isFetchingRatings = true;

    try {
      final api = di.sl<ApiService>();
      final ratings = await api.getMyRatings(token: token);
      _ratedOrderIds.addAll(ratings.map((r) => r['order_id'] as String? ?? '').where((id) => id.isNotEmpty));
    } catch (_) {
      // Non-fatal — user can still rate
    } finally {
      _isFetchingRatings = false;
    }
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
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _isLoading = false;
      });
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load orders. Check your connection.';
        _isLoading = false;
      });
      return;
    }

    // Fetch existing ratings so we know which orders are already rated
    await _fetchMyRatings();

    // Subscribe to real-time updates — separate from the fetch try-catch
    // so a subscription error never hides a successful order load.
    if (!mounted) return;
    try {
      final userId = _userId;
      if (userId != null) _subscribeToOrders(userId);
    } catch (_) {
      // Non-fatal — user can still see their orders
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
                    const Text(
                      'Order',
                      style: TextStyle(
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

            // ── Rate Delivery Button (only for delivered orders with a rider) ──
            if (order.status == OrderStatus.delivered &&
                order.deliveryBoyId != null &&
                order.deliveryBoyId!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: _ratedOrderIds.contains(order.id)
                      ? Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE6F4EA),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle, size: 16, color: Color(0xFF1E8E3E)),
                              SizedBox(width: 6),
                              Text(
                                'You rated this delivery',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1E8E3E),
                                ),
                              ),
                            ],
                          ),
                        )
                      : ElevatedButton.icon(
                          onPressed: () => _showRatingSheet(order),
                          icon: const Icon(Icons.star_rounded, size: 18),
                          label: const Text('Rate Delivery'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF9A825),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            elevation: 0,
                          ),
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Inline Rating Sheet ──────────────────────

  Future<void> _showRatingSheet(Order order) async {
    if (!mounted) return;

    int selectedRating = 0;
    String? comment;
    final TextEditingController commentCtrl = TextEditingController();

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD9D9D9),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'How was your delivery?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1A1C1C)),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  final starNum = index + 1;
                  return GestureDetector(
                    onTap: () => setSheetState(() => selectedRating = starNum),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        starNum <= selectedRating ? Icons.star_rounded : Icons.star_border_rounded,
                        size: 44,
                        color: starNum <= selectedRating
                            ? const Color(0xFFF9A825)
                            : const Color(0xFFD9D9D9),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: commentCtrl,
                maxLines: 3,
                maxLength: 200,
                decoration: InputDecoration(
                  hintText: 'Share your experience (optional)',
                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFBB0018))),
                  filled: true,
                  fillColor: const Color(0xFFFAF9F9),
                  contentPadding: const EdgeInsets.all(14),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: selectedRating == 0 || _isSubmittingRating
                      ? null
                      : () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFBB0018),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFEFEDED),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: _isSubmittingRating
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Submit Rating', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (result == true && selectedRating > 0) {
      comment = commentCtrl.text.trim();
      await _submitRating(order, selectedRating, comment.isEmpty ? null : comment);
    }
    commentCtrl.dispose();
  }

  Future<void> _submitRating(Order order, int rating, String? comment) async {
    final token = _token;
    final riderId = order.deliveryBoyId;
    if (token == null || riderId == null) return;

    setState(() => _isSubmittingRating = true);
    try {
      final api = di.sl<ApiService>();
      await api.submitRiderRating(
        orderId: order.id,
        riderId: riderId,
        rating: rating,
        comment: comment,
        token: token,
      );
      if (mounted) {
        setState(() {
          _ratedOrderIds.add(order.id);
          _isSubmittingRating = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.thumb_up_alt_rounded, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('Thanks for your feedback!'),
              ],
            ),
            backgroundColor: Color(0xFF1E8E3E),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _isSubmittingRating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _isSubmittingRating = false);
    }
  }

  Widget _buildStatusBadge(OrderStatus status) {
    Color bgColor;
    Color textColor;
    String label;

    switch (status) {
      case OrderStatus.created:
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
      case OrderStatus.outForDelivery:
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
