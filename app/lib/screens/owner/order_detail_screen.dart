import 'package:flutter/material.dart';
import '../../models/order.dart';
import '../../core/services/api_service.dart';
import '../../injection_container.dart' as di;
import '../../providers/auth_provider.dart';
import 'package:provider/provider.dart';

class OrderDetailScreen extends StatefulWidget {
  final Order order;

  const OrderDetailScreen({super.key, required this.order});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  late Order _order;
  bool _isLoading = true;
  bool _isUpdating = false;
  @override
  void initState() {
    super.initState();
    _order = widget.order;
    _refreshOrder();
  }

  String? get _token => context.read<AuthProvider>().token;

  Future<void> _refreshOrder() async {
    final token = _token;
    if (token == null) return;

    try {
      final api = di.sl<ApiService>();
      final raw = await api.getOrderById(orderId: _order.id, token: token);
      if (raw.isNotEmpty && mounted) {
        setState(() {
          _order = Order.fromJson(raw);
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          // Keep the passed order if refresh fails
        });
      }
    }
  }

  Future<void> _acceptOrder() async {
    final token = _token;
    if (token == null || _isUpdating) return;

    setState(() => _isUpdating = true);
    try {
      final api = di.sl<ApiService>();
      final raw = await api.acceptOrder(orderId: _order.id, token: token);
      if (raw.isNotEmpty && mounted) {
        setState(() => _order = Order.fromJson(raw));
        _showSnack('Order accepted!', const Color(0xFF1E8E3E));
      }
    } on ApiException catch (e) {
      if (mounted) _showSnack(e.message, Colors.red);
    } catch (_) {
      if (mounted) _showSnack('Failed to accept order', Colors.red);
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _rejectOrder() async {
    final token = _token;
    if (token == null || _isUpdating) return;

    setState(() => _isUpdating = true);
    try {
      final api = di.sl<ApiService>();
      final raw = await api.rejectOrder(orderId: _order.id, token: token);
      if (raw.isNotEmpty && mounted) {
        setState(() => _order = Order.fromJson(raw));
        _showSnack('Order rejected.', const Color(0xFF5E3F3C));
      }
    } on ApiException catch (e) {
      if (mounted) _showSnack(e.message, Colors.red);
    } catch (_) {
      if (mounted) _showSnack('Failed to reject order', Colors.red);
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _markAsPreparing() async {
    final token = _token;
    if (token == null || _isUpdating) return;

    setState(() => _isUpdating = true);
    try {
      final api = di.sl<ApiService>();
      final raw = await api.markOrderAsPreparing(orderId: _order.id, token: token);
      if (raw.isNotEmpty && mounted) {
        setState(() => _order = Order.fromJson(raw));
        _showSnack('Started preparing!', const Color(0xFF1967D2));
      }
    } on ApiException catch (e) {
      if (mounted) _showSnack(e.message, Colors.red);
    } catch (_) {
      if (mounted) _showSnack('Failed to update order', Colors.red);
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _markAsPickedUp() async {
    final token = _token;
    if (token == null || _isUpdating) return;

    setState(() => _isUpdating = true);
    try {
      final api = di.sl<ApiService>();
      final raw = await api.markOrderAsPickedUp(orderId: _order.id, token: token);
      if (raw.isNotEmpty && mounted) {
        setState(() => _order = Order.fromJson(raw));
        _showSnack('Order is out for delivery!', const Color(0xFF1967D2));
      }
    } on ApiException catch (e) {
      if (mounted) _showSnack(e.message, Colors.red);
    } catch (_) {
      if (mounted) _showSnack('Failed to update order', Colors.red);
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _markAsDelivered() async {
    final token = _token;
    if (token == null || _isUpdating) return;

    setState(() => _isUpdating = true);
    try {
      final api = di.sl<ApiService>();
      final raw = await api.markOrderAsDelivered(orderId: _order.id, token: token);
      if (raw.isNotEmpty && mounted) {
        setState(() => _order = Order.fromJson(raw));
        _showSnack('Order delivered!', const Color(0xFF1E8E3E));
      }
    } on ApiException catch (e) {
      if (mounted) _showSnack(e.message, Colors.red);
    } catch (_) {
      if (mounted) _showSnack('Failed to update order', Colors.red);
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _markAsReady() async {
    final token = _token;
    if (token == null || _isUpdating) return;

    setState(() => _isUpdating = true);
    try {
      final api = di.sl<ApiService>();
      final raw = await api.markOrderAsReady(orderId: _order.id, token: token);
      if (raw.isNotEmpty && mounted) {
        setState(() => _order = Order.fromJson(raw));
        _showSnack('Order is ready!', const Color(0xFF1E8E3E));
      }
    } on ApiException catch (e) {
      if (mounted) _showSnack(e.message, Colors.red);
    } catch (_) {
      if (mounted) _showSnack('Failed to update order', Colors.red);
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  void _showSnack(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _formatCurrency(double amount) => 'Rs. ${amount.toStringAsFixed(0)}';

  String _formatTime(DateTime? dt) {
    if (dt == null) return '';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '';
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]}, ${_formatTime(dt)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF1A1C1C)),
          onPressed: () => Navigator.pop(context, true),
        ),
        title: Text(
          '#${_order.orderNumber}',
          style: const TextStyle(
            color: Color(0xFF1A1C1C),
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: false,
        actions: [
          TextButton.icon(
            onPressed: _isLoading ? null : _refreshOrder,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Refresh'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFBB0018),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFBB0018)))
          : RefreshIndicator(
              onRefresh: _refreshOrder,
              color: const Color(0xFFBB0018),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildStatusHeader(),
                    const SizedBox(height: 20),
                    _buildTimeline(),
                    const SizedBox(height: 24),
                    _buildOrderItemsCard(),
                    const SizedBox(height: 16),
                    _buildDeliveryCard(),
                    const SizedBox(height: 16),
                    _buildPaymentCard(),
                    if (_order.specialInstructions != null &&
                        _order.specialInstructions!.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildSpecialInstructionsCard(),
                    ],
                  ],
                ),
              ),
            ),
      bottomSheet: _order.status == OrderStatus.pending ||
              _order.status == OrderStatus.accepted ||
              _order.status == OrderStatus.preparing ||
              _order.status == OrderStatus.ready ||
              _order.status == OrderStatus.pickedUp
          ? _buildBottomActions()
          : null,
    );
  }

  // ── Status Header ────────────────────────────

  Widget _buildStatusHeader() {
    final statusColors = _getStatusColors(_order.status);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            statusColors.$1.withValues(alpha: 0.12),
            statusColors.$1.withValues(alpha: 0.04),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColors.$1.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: statusColors.$1.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              _statusIcon(_order.status),
              color: statusColors.$1,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _statusTitle(_order.status),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: statusColors.$1,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _order.status == OrderStatus.pending
                      ? 'Awaiting your action'
                      : 'Updated ${_formatDate(_order.updatedAt)}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF5C5C5C),
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          _buildStatusBadge(_order.status),
        ],
      ),
    );
  }

  // ── Status Timeline ──────────────────────────

  Widget _buildTimeline() {
    final steps = _buildTimelineSteps();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C1B1C1C),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.timeline_rounded, size: 18, color: Color(0xFFBB0018)),
              SizedBox(width: 8),
              Text(
                'Order Timeline',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1C1C),
                  height: 1.25,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ...steps.asMap().entries.map((entry) {
            final index = entry.key;
            final step = entry.value;
            final isLast = index == steps.length - 1;
            return _buildTimelineStep(
              icon: step.icon,
              label: step.label,
              time: step.time,
              isActive: step.isActive,
              isCompleted: step.isCompleted,
              isLast: isLast,
              isCancelled: step.isCancelled,
            );
          }),
        ],
      ),
    );
  }

  List<_TimelineStep> _buildTimelineSteps() {
    final status = _order.status;

    // Cancelled / Rejected — show the timeline up to the cancellation point
    if (status == OrderStatus.cancelled || status == OrderStatus.rejected) {
      return [
        _TimelineStep(
          icon: Icons.check_circle_rounded,
          label: 'Order Placed',
          time: _formatDate(_order.createdAt),
          isCompleted: true,
          isActive: true,
        ),
        _TimelineStep(
          icon: Icons.cancel_rounded,
          label: status == OrderStatus.cancelled ? 'Cancelled' : 'Rejected',
          time: _formatDate(_order.cancelledAt),
          isCompleted: false,
          isActive: false,
          isCancelled: true,
        ),
      ];
    }

    return [
      _TimelineStep(
        icon: Icons.check_circle_rounded,
        label: 'Order Placed',
        time: _formatDate(_order.createdAt),
        isCompleted: true,
        isActive: true,
      ),
      _TimelineStep(
        icon: status == OrderStatus.pending
            ? Icons.radio_button_unchecked_rounded
            : Icons.check_circle_rounded,
        label: 'Order Accepted',
        time: _formatDate(_order.acceptedAt),
        isCompleted: _order.acceptedAt != null,
        isActive: status == OrderStatus.pending,
      ),
      _TimelineStep(
        icon: _order.acceptedAt == null &&
                (status == OrderStatus.pending)
            ? Icons.radio_button_unchecked_rounded
            : _order.preparingAt != null
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
        label: 'Preparing',
        time: _formatDate(_order.preparingAt),
        isCompleted: _order.preparingAt != null,
        isActive: status == OrderStatus.accepted,
      ),
      _TimelineStep(
        icon: _order.preparingAt == null &&
                (status == OrderStatus.pending || status == OrderStatus.accepted)
            ? Icons.radio_button_unchecked_rounded
            : _order.readyAt != null
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
        label: 'Ready',
        time: _formatDate(_order.readyAt),
        isCompleted: _order.readyAt != null,
        isActive: status == OrderStatus.preparing,
      ),
      _TimelineStep(
        icon: _order.readyAt == null &&
                (status == OrderStatus.pending ||
                    status == OrderStatus.accepted ||
                    status == OrderStatus.preparing)
            ? Icons.radio_button_unchecked_rounded
            : _order.pickedUpAt != null
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
        label: 'Picked Up',
        time: _formatDate(_order.pickedUpAt),
        isCompleted: _order.pickedUpAt != null,
        isActive: status == OrderStatus.ready,
      ),
      _TimelineStep(
        icon: _order.pickedUpAt == null &&
                (status == OrderStatus.pending ||
                    status == OrderStatus.accepted ||
                    status == OrderStatus.preparing ||
                    status == OrderStatus.ready)
            ? Icons.radio_button_unchecked_rounded
            : _order.deliveredAt != null
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
        label: 'Delivered',
        time: _formatDate(_order.deliveredAt),
        isCompleted: _order.deliveredAt != null,
        isActive: status == OrderStatus.pickedUp,
      ),
    ];
  }

  Widget _buildTimelineStep({
    required IconData icon,
    required String label,
    required String time,
    required bool isCompleted,
    required bool isActive,
    required bool isLast,
    bool isCancelled = false,
  }) {
    Color iconColor;
    Color lineColor;
    Color textColor;

    if (isCancelled) {
      iconColor = const Color(0xFFD93025);
      lineColor = const Color(0xFFE5E7EB);
      textColor = const Color(0xFFD93025);
    } else if (isCompleted) {
      iconColor = const Color(0xFF1E8E3E);
      lineColor = const Color(0xFF1E8E3E);
      textColor = const Color(0xFF1A1C1C);
    } else if (isActive) {
      iconColor = const Color(0xFFBB0018);
      lineColor = const Color(0xFFE5E7EB);
      textColor = const Color(0xFFBB0018);
    } else {
      iconColor = const Color(0xFFD9D9D9);
      lineColor = const Color(0xFFE5E7EB);
      textColor = const Color(0xFFBFBFBF);
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline line + icon
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Icon(icon, size: 22, color: iconColor),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: lineColor,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Content
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight:
                          isCompleted || isActive ? FontWeight.w600 : FontWeight.w400,
                      color: textColor,
                      height: 1.3,
                    ),
                  ),
                  if (time.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      time,
                      style: TextStyle(
                        fontSize: 12,
                        color: isCompleted || isActive
                            ? const Color(0xFF5C5C5C)
                            : const Color(0xFFBFBFBF),
                        fontWeight: FontWeight.w400,
                        height: 1.38,
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

  // ── Order Items Card ─────────────────────────

  Widget _buildOrderItemsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C1B1C1C),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.restaurant_menu_rounded,
                  size: 18, color: Color(0xFFBB0018)),
              const SizedBox(width: 8),
              const Text(
                'Order Items',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1C1C),
                  height: 1.25,
                ),
              ),
              const Spacer(),
              Text(
                '${_order.items.length} item${_order.items.length == 1 ? '' : 's'}',
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF5C5C5C),
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ..._order.items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (item.imageUrl != null && item.imageUrl!.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          item.imageUrl!,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F5F5),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.fastfood_outlined,
                                size: 20, color: Color(0xFFBFBFBF)),
                          ),
                        ),
                      ),
                    if (item.imageUrl != null && item.imageUrl!.isNotEmpty)
                      const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFAF9F9),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${item.quantity}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFFBB0018),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  item.name,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF1A1C1C),
                                    height: 1.29,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          if (item.size != null || (item.addOns != null && item.addOns!.isNotEmpty)) ...[
                            const SizedBox(height: 4),
                            if (item.size != null)
                              Text(
                                'Size: ${item.size}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF5C5C5C),
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            if (item.addOns != null && item.addOns!.isNotEmpty)
                              Text(
                                'Add-ons: ${item.addOns!.map((a) => a.name).join(', ')}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF5C5C5C),
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatCurrency(item.price * item.quantity),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1C1C),
                        height: 1.29,
                      ),
                    ),
                  ],
                ),
              )),
          const Divider(color: Color(0xFFF0F0F0), height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Subtotal',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF5C5C5C),
                  fontWeight: FontWeight.w400,
                ),
              ),
              Text(
                _formatCurrency(_order.subtotal),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1C1C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Delivery Fee',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF5C5C5C),
                  fontWeight: FontWeight.w400,
                ),
              ),
              Text(
                _order.deliveryFee > 0
                    ? _formatCurrency(_order.deliveryFee)
                    : 'Free',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _order.deliveryFee > 0
                      ? const Color(0xFF1A1C1C)
                      : const Color(0xFF1E8E3E),
                ),
              ),
            ],
          ),
          const Divider(color: Color(0xFFF0F0F0), height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1C1C),
                  height: 1.25,
                ),
              ),
              Text(
                _formatCurrency(_order.total),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFBB0018),
                  height: 1.25,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Delivery Card ────────────────────────────

  Widget _buildDeliveryCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C1B1C1C),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.delivery_dining_rounded,
                  size: 18, color: Color(0xFFBB0018)),
              SizedBox(width: 8),
              Text(
                'Delivery',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1C1C),
                  height: 1.25,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_order.deliveryAddress?.fullAddress != null) ...[
            _buildInfoRow(
              Icons.location_on_outlined,
              'Delivery Address',
              _order.deliveryAddress!.fullAddress!,
            ),
            const SizedBox(height: 12),
          ],
          if (_order.deliveryNotes != null &&
              _order.deliveryNotes!.isNotEmpty) ...[
            _buildInfoRow(
              Icons.note_outlined,
              'Delivery Notes',
              _order.deliveryNotes!,
            ),
            const SizedBox(height: 12),
          ],
          if (_order.estimatedPrepTime != null) ...[
            _buildInfoRow(
              Icons.timer_outlined,
              'Estimated Prep Time',
              '${_order.estimatedPrepTime} minutes',
            ),
            const SizedBox(height: 12),
          ],
          if (_order.deliveryBoyId != null) ...[
            const Divider(color: Color(0xFFF0F0F0)),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F0FE),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.person_rounded,
                      size: 18, color: Color(0xFF1967D2)),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Delivery Partner Assigned',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1A1C1C),
                      height: 1.29,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
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
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFFFAF9F9),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: const Color(0xFF5C5C5C)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF5C5C5C),
                  fontWeight: FontWeight.w400,
                  height: 1.38,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1A1C1C),
                  height: 1.29,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Payment Card ─────────────────────────────

  Widget _buildPaymentCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C1B1C1C),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.receipt_long_rounded,
                  size: 18, color: Color(0xFFBB0018)),
              SizedBox(width: 8),
              Text(
                'Payment',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1C1C),
                  height: 1.25,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Order #',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF5C5C5C),
                  fontWeight: FontWeight.w400,
                ),
              ),
              Text(
                _order.orderNumber,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1A1C1C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Placed at',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF5C5C5C),
                  fontWeight: FontWeight.w400,
                ),
              ),
              Text(
                _formatDate(_order.createdAt),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1A1C1C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Status',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF5C5C5C),
                  fontWeight: FontWeight.w400,
                ),
              ),
              _buildStatusBadge(_order.status),
            ],
          ),
        ],
      ),
    );
  }

  // ── Special Instructions Card ────────────────

  Widget _buildSpecialInstructionsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline,
              size: 20, color: Color(0xFFF9A825)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Special Instructions',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF795548),
                    height: 1.29,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _order.specialInstructions!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF5D4037),
                    fontWeight: FontWeight.w400,
                    height: 1.38,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom Actions ───────────────────────────

  Widget _buildBottomActions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x141B1C1C),
            blurRadius: 12,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: _isUpdating
            ? const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Color(0xFFBB0018),
                  ),
                ),
              )
            : Row(
                children: _buildActionButtons(),
              ),
      ),
    );
  }

  List<Widget> _buildActionButtons() {
    switch (_order.status) {
      case OrderStatus.pending:
        return [
          Expanded(
            child: SizedBox(
              height: 48,
              child: OutlinedButton(
                onPressed: _rejectOrder,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF5E3F3C),
                  side: const BorderSide(color: Color(0xFFEFEDED)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'Reject',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      height: 1.29),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _acceptOrder,
                icon: const Icon(Icons.check_circle_outline, size: 20),
                label: const Text(
                  'Accept Order',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      height: 1.29),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFBB0018),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ),
        ];

      case OrderStatus.accepted:
        return [
          Expanded(
            child: SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _markAsPreparing,
                icon: const Icon(Icons.kitchen_rounded, size: 20),
                label: const Text(
                  'Start Preparing',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      height: 1.29),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1967D2),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ),
        ];

      case OrderStatus.preparing:
        return [
          Expanded(
            child: SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _markAsReady,
                icon: const Icon(Icons.check_circle_outline, size: 20),
                label: const Text(
                  'Mark as Ready',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      height: 1.29),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E8E3E),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ),
        ];

      case OrderStatus.ready:
        return [
          Expanded(
            child: SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _markAsPickedUp,
                icon: const Icon(Icons.delivery_dining_rounded, size: 20),
                label: const Text(
                  'Out for Delivery',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      height: 1.29),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1967D2),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ),
        ];

      case OrderStatus.pickedUp:
        return [
          Expanded(
            child: SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _markAsDelivered,
                icon: const Icon(Icons.task_alt_rounded, size: 20),
                label: const Text(
                  'Mark as Delivered',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      height: 1.29),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E8E3E),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ),
        ];

      default:
        return [];
    }
  }

  // ── Helpers ──────────────────────────────────

  Widget _buildStatusBadge(OrderStatus status) {
    final colors = _getStatusColors(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.$1.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(9999),
        border: Border.all(color: colors.$1.withValues(alpha: 0.3)),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: colors.$1,
          height: 1.29,
        ),
      ),
    );
  }

  (Color, Color) _getStatusColors(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return (const Color(0xFFBB0018), const Color(0xFFFFF1F0));
      case OrderStatus.accepted:
        return (const Color(0xFF1967D2), const Color(0xFFE8F0FE));
      case OrderStatus.preparing:
        return (const Color(0xFFF9A825), const Color(0xFFFFF8E1));
      case OrderStatus.ready:
        return (const Color(0xFF1E8E3E), const Color(0xFFE6F4EA));
      case OrderStatus.pickedUp:
        return (const Color(0xFF1967D2), const Color(0xFFE8F0FE));
      case OrderStatus.delivered:
        return (const Color(0xFF1E8E3E), const Color(0xFFE6F4EA));
      case OrderStatus.cancelled:
        return (const Color(0xFF5E3F3C), const Color(0xFFEFEDED));
      case OrderStatus.rejected:
        return (const Color(0xFFBB0018), const Color(0xFFFFF1F0));
    }
  }

  IconData _statusIcon(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return Icons.hourglass_empty_rounded;
      case OrderStatus.accepted:
        return Icons.check_circle_outline_rounded;
      case OrderStatus.preparing:
        return Icons.kitchen_rounded;
      case OrderStatus.ready:
        return Icons.check_circle_rounded;
      case OrderStatus.pickedUp:
        return Icons.delivery_dining_rounded;
      case OrderStatus.delivered:
        return Icons.task_alt_rounded;
      case OrderStatus.cancelled:
        return Icons.cancel_outlined;
      case OrderStatus.rejected:
        return Icons.block_rounded;
    }
  }

  String _statusTitle(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return 'New Order';
      case OrderStatus.accepted:
        return 'Order Accepted';
      case OrderStatus.preparing:
        return 'Preparing';
      case OrderStatus.ready:
        return 'Ready for Pickup';
      case OrderStatus.pickedUp:
        return 'Picked Up';
      case OrderStatus.delivered:
        return 'Delivered';
      case OrderStatus.cancelled:
        return 'Cancelled';
      case OrderStatus.rejected:
        return 'Rejected';
    }
  }

  String _statusLabel(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return 'New';
      case OrderStatus.accepted:
        return 'Accepted';
      case OrderStatus.preparing:
        return 'Preparing';
      case OrderStatus.ready:
        return 'Ready';
      case OrderStatus.pickedUp:
        return 'Picked Up';
      case OrderStatus.delivered:
        return 'Delivered';
      case OrderStatus.cancelled:
        return 'Cancelled';
      case OrderStatus.rejected:
        return 'Rejected';
    }
  }
}

class _TimelineStep {
  final IconData icon;
  final String label;
  final String time;
  final bool isCompleted;
  final bool isActive;
  final bool isCancelled;

  _TimelineStep({
    required this.icon,
    required this.label,
    required this.time,
    this.isCompleted = false,
    this.isActive = false,
    this.isCancelled = false,
  });
}
