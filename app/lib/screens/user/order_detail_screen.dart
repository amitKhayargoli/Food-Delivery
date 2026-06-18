import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../../models/order.dart';
import '../../core/services/api_service.dart';
import '../../core/services/supabase_client_service.dart';
import '../../injection_container.dart' as di;
import '../../providers/auth_provider.dart';

/// A shared order detail screen that works in two modes:\n/// - `isOwner = false` (default): read-only timeline, items, pricing, delivery info\n/// - `isOwner = true`: adds action buttons (accept/reject/prepare/ready) and delivery partner assignment
class OrderDetailScreen extends StatefulWidget {
  final Order order;
  final bool isOwner;

  const OrderDetailScreen({
    super.key,
    required this.order,
    this.isOwner = false,
  });

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  late Order _order;
  bool _isLoadingAction = false;
  Timer? _debounce;
  sb.RealtimeChannel? _orderChannel;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
    _subscribeToOrder();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _unsubscribeFromOrder();
    super.dispose();
  }

  void _subscribeToOrder() {
    _unsubscribeFromOrder();
    _orderChannel = SupabaseClientService.client.channel('order-detail-${_order.id}');

    _orderChannel!.onPostgresChanges(
      event: sb.PostgresChangeEvent.update,
      schema: 'public',
      table: 'orders',
      callback: (payload) {
        final record = payload.newRecord;
        if (record['id']?.toString() == _order.id) {
          // Re-fetch the order details using the appropriate API
          _refreshOrder();
        }
      },
    );

    _orderChannel!.subscribe((status, [error]) {
      debugPrint('[RT-OrderDetail] Channel status: $status');
      if (error != null) debugPrint('[RT-OrderDetail] Error: $error');
    });
  }

  void _unsubscribeFromOrder() {
    if (_orderChannel != null) {
      SupabaseClientService.client.removeChannel(_orderChannel!);
      _orderChannel = null;
    }
  }

  String? get _token => context.read<AuthProvider>().token;

  String _formatCurrency(double amount) {
    return 'Rs. ${amount.toStringAsFixed(0)}';
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return '';
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _refreshOrder() async {
    final token = _token;
    if (token == null) return;

    try {
      final api = di.sl<ApiService>();
      final rawOrders = widget.isOwner
          ? await api.getRestaurantOrders(token: token)
          : await api.getMyOrders(token: token);
      final updated = rawOrders
          .map((o) => Order.fromJson(o))
          .where((o) => o.id == _order.id)
          .firstOrNull;
      if (updated != null && mounted) {
        setState(() => _order = updated);
      }
    } catch (_) {}
  }

  // ── Owner actions ──

  Future<void> _acceptOrder() async {
    final token = _token;
    if (token == null) return;
    setState(() => _isLoadingAction = true);
    try {
      await di.sl<ApiService>().acceptOrder(orderId: _order.id, token: token);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order accepted!'), behavior: SnackBarBehavior.floating),
        );
        _refreshOrder();
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingAction = false);
    }
  }

  Future<void> _rejectOrder() async {
    final token = _token;
    if (token == null) return;
    setState(() => _isLoadingAction = true);
    try {
      await di.sl<ApiService>().rejectOrder(orderId: _order.id, token: token);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order rejected.'), behavior: SnackBarBehavior.floating),
        );
        _refreshOrder();
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingAction = false);
    }
  }

  Future<void> _markAsPreparing() async {
    final token = _token;
    if (token == null) return;
    setState(() => _isLoadingAction = true);
    try {
      await di.sl<ApiService>().markOrderAsPreparing(orderId: _order.id, token: token);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Preparing!'), behavior: SnackBarBehavior.floating),
        );
        _refreshOrder();
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingAction = false);
    }
  }

  Future<void> _markAsReady() async {
    final token = _token;
    if (token == null) return;
    setState(() => _isLoadingAction = true);
    try {
      await di.sl<ApiService>().markOrderAsReady(orderId: _order.id, token: token);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order ready!'), behavior: SnackBarBehavior.floating),
        );
        _refreshOrder();
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingAction = false);
    }
  }

  // ── Assign delivery boy ──

  Future<void> _showAssignDeliveryBoySheet() async {
    final token = _token;
    if (token == null) return;

    try {
      final api = di.sl<ApiService>();
      final boys = await api.getDeliveryBoys(token: token);

      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD9D9D9),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Assign Delivery Partner',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              if (boys.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      'No delivery partners available',
                      style: TextStyle(color: Color(0xFF8E8E93)),
                    ),
                  ),
                ),
              ...boys.map((boy) => ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFFE8F0FE),
                      child: const Icon(Icons.person, color: Color(0xFF1967D2)),
                    ),
                    title: Text(
                      boy['username'] as String? ?? 'Delivery Boy',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      '${boy['phone'] as String? ?? ''}  •  ${boy['email'] as String? ?? ''}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _assignDeliveryBoy(
                          _order.id,
                          boy['id'] as String,
                          boy['username'] as String? ?? 'Partner',
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFBB0018),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                      child: const Text('Assign', style: TextStyle(fontSize: 13)),
                    ),
                  )),
            ],
          ),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  Future<void> _assignDeliveryBoy(String orderId, String boyId, String boyName) async {
    final token = _token;
    if (token == null) return;
    setState(() => _isLoadingAction = true);
    try {
      await di.sl<ApiService>().assignDeliveryBoy(
        orderId: orderId,
        deliveryBoyId: boyId,
        token: token,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$boyName assigned to this order!'),
            backgroundColor: const Color(0xFF1E8E3E),
            behavior: SnackBarBehavior.floating,
          ),
        );
        _refreshOrder();
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingAction = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F9),
      appBar: AppBar(
        title: Text('#${_order.orderNumber}'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1C1C),
        elevation: 0.5,
      ),
      body: _isLoadingAction
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFBB0018)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Status Timeline ──
                  _buildTimeline(),
                  const SizedBox(height: 20),

                  // ── Items ──
                  _buildSectionTitle('Order Items'),
                  const SizedBox(height: 8),
                  ..._order.items.map((item) => _buildOrderItemRow(item)),

                  const Divider(height: 24),

                  // ── Pricing Summary ──
                  _buildPriceRow('Subtotal', _order.subtotal),
                  _buildPriceRow('Delivery Fee', _order.deliveryFee),
                  const SizedBox(height: 4),
                  _buildPriceRow('Total', _order.total, isBold: true, color: const Color(0xFFBB0018)),

                  const SizedBox(height: 20),

                  // ── Delivery Info ──
                  if (_order.deliveryAddress?.fullAddress != null) ...[
                    _buildInfoCard(
                      icon: Icons.location_on_outlined,
                      iconColor: const Color(0xFFF5222D),
                      title: 'Delivery Address',
                      subtitle: _order.deliveryAddress!.fullAddress!,
                    ),
                    const SizedBox(height: 12),
                  ],

                  if (_order.specialInstructions != null && _order.specialInstructions!.isNotEmpty) ...[
                    _buildInfoCard(
                      icon: Icons.info_outline,
                      iconColor: const Color(0xFFF9A825),
                      title: 'Special Instructions',
                      subtitle: _order.specialInstructions!,
                    ),
                    const SizedBox(height: 12),
                  ],

                  // ── Delivery Partner Info ──
                  if (_order.deliveryBoyId != null)
                    _buildInfoCard(
                      icon: Icons.moped_rounded,
                      iconColor: const Color(0xFF1967D2),
                      title: 'Delivery Partner',
                      subtitle: 'Assigned',
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE6F4EA),
                          borderRadius: BorderRadius.circular(9999),
                        ),
                        child: const Text(
                          'Active',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E8E3E),
                          ),
                        ),
                      ),
                    ),

                  const SizedBox(height: 24),

                  // ── Action Buttons (owner only) ──
                  if (widget.isOwner) _buildOwnerActions(),
                ],
              ),
            ),
    );
  }

  // ── Timeline ──

  Widget _buildTimeline() {
    final steps = <StepData>[];

    steps.add(StepData(
      icon: Icons.receipt_long_rounded,
      label: 'Order Placed',
      timestamp: _formatDateTime(_order.createdAt),
      isCompleted: true,
    ));

    if (_order.acceptedAt != null || _order.status.index <= OrderStatus.accepted.index) {
      steps.add(StepData(
        icon: Icons.check_circle_outline,
        label: _order.status == OrderStatus.rejected ? 'Order Rejected' : 'Order Accepted',
        timestamp: _formatDateTime(_order.acceptedAt),
        isCompleted: _order.acceptedAt != null,
        isError: _order.status == OrderStatus.rejected,
      ));
    }

    if (_order.status == OrderStatus.preparing || _order.preparingAt != null ||
        _order.status.index >= OrderStatus.ready.index) {
      steps.add(StepData(
        icon: Icons.kitchen_rounded,
        label: 'Preparing',
        timestamp: _formatDateTime(_order.preparingAt),
        isCompleted: _order.preparingAt != null || _order.status == OrderStatus.preparing,
      ));
    }

    if (_order.readyAt != null || _order.status.index >= OrderStatus.ready.index) {
      steps.add(StepData(
        icon: Icons.check_circle_outline,
        label: 'Ready',
        timestamp: _formatDateTime(_order.readyAt),
        isCompleted: _order.readyAt != null || _order.status == OrderStatus.ready,
      ));
    }

    if (_order.pickedUpAt != null || _order.status.index >= OrderStatus.pickedUp.index) {
      steps.add(StepData(
        icon: Icons.moped_rounded,
        label: 'Picked Up',
        timestamp: _formatDateTime(_order.pickedUpAt),
        isCompleted: _order.pickedUpAt != null || _order.status == OrderStatus.pickedUp,
      ));
    }

    if (_order.deliveredAt != null || _order.status == OrderStatus.delivered) {
      steps.add(StepData(
        icon: Icons.location_on_rounded,
        label: 'Delivered',
        timestamp: _formatDateTime(_order.deliveredAt),
        isCompleted: _order.deliveredAt != null || _order.status == OrderStatus.delivered,
      ));
    }

    if (_order.status == OrderStatus.cancelled) {
      steps.add(StepData(
        icon: Icons.cancel_rounded,
        label: 'Cancelled',
        timestamp: _formatDateTime(_order.cancelledAt),
        isCompleted: true,
        isError: true,
      ));
    }

    return Container(
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
        children: steps.asMap().entries.map((entry) {
          final i = entry.key;
          final step = entry.value;
          final isLast = i == steps.length - 1;
          return _buildTimelineStep(step, isLast);
        }).toList(),
      ),
    );
  }

  Widget _buildTimelineStep(StepData step, bool isLast) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline indicator column
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: step.isError
                        ? const Color(0xFFFFF1F0)
                        : step.isCompleted
                            ? const Color(0xFFE6F4EA)
                            : const Color(0xFFEFEDED),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    step.icon,
                    size: 14,
                    color: step.isError
                        ? const Color(0xFFBB0018)
                        : step.isCompleted
                            ? const Color(0xFF1E8E3E)
                            : const Color(0xFFBFBFBF),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: step.isCompleted
                          ? const Color(0xFF1E8E3E)
                          : const Color(0xFFE8E8E8),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    step.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: step.isCompleted
                          ? const Color(0xFF1A1C1C)
                          : const Color(0xFFBFBFBF),
                    ),
                  ),
                  if (step.timestamp.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      step.timestamp,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF8E8E93),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section title ──

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: Color(0xFF1A1C1C),
      ),
    );
  }

  Widget _buildOrderItemRow(OrderItem item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${item.quantity}x ${item.name}',
              style: const TextStyle(fontSize: 14, color: Color(0xFF1A1C1C)),
            ),
          ),
          Text(
            _formatCurrency(item.price * item.quantity),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1C1C),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPriceRow(String label, double value, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isBold ? FontWeight.w600 : FontWeight.w400,
              color: isBold ? const Color(0xFF1A1C1C) : const Color(0xFF5C5C5C),
            ),
          ),
          Text(
            _formatCurrency(value),
            style: TextStyle(
              fontSize: 14,
              fontWeight: isBold ? FontWeight.w700 : FontWeight.w600,
              color: color ?? const Color(0xFF1A1C1C),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF0F0F0)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93))),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  // ── Owner actions ──

  Widget _buildOwnerActions() {
    if (_order.status == OrderStatus.delivered ||
        _order.status == OrderStatus.cancelled ||
        _order.status == OrderStatus.rejected) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Actions'),
        const SizedBox(height: 12),
        // Accept / Reject for PENDING
        if (_order.status == OrderStatus.pending)
          Row(
            children: [
              Expanded(
                child: _buildActionButton(
                  label: 'Reject',
                  color: const Color(0xFF5E3F3C),
                  bgColor: Colors.white,
                  borderColor: const Color(0xFFEFEDED),
                  onTap: _rejectOrder,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _buildActionButton(
                  label: 'Accept Order',
                  color: Colors.white,
                  bgColor: const Color(0xFFBB0018),
                  onTap: _acceptOrder,
                ),
              ),
            ],
          ),

        // Start Preparing for ACCEPTED
        if (_order.status == OrderStatus.accepted)
          SizedBox(
            width: double.infinity,
            child: _buildActionButton(
              label: 'Start Preparing',
              color: Colors.white,
              bgColor: const Color(0xFF1967D2),
              icon: Icons.kitchen_rounded,
              onTap: _markAsPreparing,
            ),
          ),

        // Mark as Ready for PREPARING
        if (_order.status == OrderStatus.preparing)
          SizedBox(
            width: double.infinity,
            child: _buildActionButton(
              label: 'Mark as Ready',
              color: Colors.white,
              bgColor: const Color(0xFF1E8E3E),
              icon: Icons.check_circle_outline,
              onTap: _markAsReady,
            ),
          ),

        // Assign Delivery Partner for READY or PREPARING (if not already assigned)
        if ((_order.status == OrderStatus.ready || _order.status == OrderStatus.preparing) &&
            _order.deliveryBoyId == null) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: _buildActionButton(
              label: 'Assign Delivery Partner',
              color: Colors.white,
              bgColor: const Color(0xFFF9A825),
              icon: Icons.moped_rounded,
              onTap: _showAssignDeliveryBoySheet,
            ),
          ),
        ],

        // Show assigned delivery partner info
        if (_order.deliveryBoyId != null && _order.status != OrderStatus.ready && _order.status != OrderStatus.preparing)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFE6F4EA),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF1E8E3E)),
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle, color: Color(0xFF1E8E3E), size: 20),
                SizedBox(width: 8),
                Text(
                  'Delivery partner assigned',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildActionButton({
    required String label,
    required Color color,
    required Color bgColor,
    Color? borderColor,
    IconData? icon,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 44,
      child: bgColor == Colors.white
          ? OutlinedButton(
              onPressed: onTap,
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                side: BorderSide(color: borderColor ?? const Color(0xFFEFEDED)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            )
          : ElevatedButton.icon(
              onPressed: onTap,
              icon: icon != null ? Icon(icon, size: 18) : const SizedBox.shrink(),
              label: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              style: ElevatedButton.styleFrom(
                backgroundColor: bgColor,
                foregroundColor: color,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
            ),
    );
  }
}

class StepData {
  final IconData icon;
  final String label;
  final String timestamp;
  final bool isCompleted;
  final bool isError;

  StepData({
    required this.icon,
    required this.label,
    this.timestamp = '',
    this.isCompleted = false,
    this.isError = false,
  });
}
