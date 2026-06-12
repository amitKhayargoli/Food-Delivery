import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/order.dart';
import '../../core/services/api_service.dart';
import '../../widgets/toggle_switch.dart';
import '../../injection_container.dart' as di;
import '../../providers/auth_provider.dart';
import 'order_detail_screen.dart';

class OwnerDashboardScreen extends StatefulWidget {
  const OwnerDashboardScreen({super.key});

  @override
  State<OwnerDashboardScreen> createState() => _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends State<OwnerDashboardScreen> {
  List<Order> _allOrders = [];
  bool _isLoading = true;
  String? _error;
  bool _isAcceptingOrders = true;
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _fetchOrders();
  }

  // ── Derived data ────────────────────────────

  String? get _token => context.read<AuthProvider>().token;

  List<Order> get _newOrders =>
      _allOrders.where((o) => o.status == OrderStatus.pending).toList();

  List<Order> get _preparingOrders => _allOrders
      .where((o) =>
          o.status == OrderStatus.accepted ||
          o.status == OrderStatus.preparing)
      .toList();

  List<Order> get _readyOrders =>
      _allOrders.where((o) => o.status == OrderStatus.ready).toList();

  List<Order> get _outForDeliveryOrders =>
      _allOrders.where((o) => o.status == OrderStatus.pickedUp).toList();

  List<Order> get _deliveredOrders =>
      _allOrders.where((o) => o.status == OrderStatus.delivered).toList();

  List<Order> get _currentOrders {
    switch (_selectedTab) {
      case 0: return _newOrders;
      case 1: return _preparingOrders;
      case 2: return _readyOrders;
      case 3: return _outForDeliveryOrders;
      case 4: return _deliveredOrders;
      default: return _newOrders;
    }
  }

  // ── Data fetching ────────────────────────────

  Future<void> _fetchOrders() async {
    final token = _token;
    if (token == null) {
      setState(() {
        _isLoading = false;
        _error = 'Not authenticated. Please log in.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = di.sl<ApiService>();
      final rawOrders = await api.getRestaurantOrders(token: token);
      setState(() {
        _allOrders = rawOrders.map((o) => Order.fromJson(o)).toList();
        _isLoading = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load orders. Check your connection.';
        _isLoading = false;
      });
    }
  }

  // ── Order actions ────────────────────────────

  Future<void> _acceptOrder(Order order) async {
    final token = _token;
    if (token == null) return;

    try {
      final api = di.sl<ApiService>();
      await api.acceptOrder(orderId: order.id, token: token);
      _fetchOrders();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order accepted!'),
            backgroundColor: Color(0xFF1E8E3E),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _rejectOrder(Order order) async {
    final token = _token;
    if (token == null) return;

    try {
      final api = di.sl<ApiService>();
      await api.rejectOrder(orderId: order.id, token: token);
      _fetchOrders();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order rejected.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _markAsPreparing(Order order) async {
    final token = _token;
    if (token == null) return;

    try {
      final api = di.sl<ApiService>();
      await api.markOrderAsPreparing(orderId: order.id, token: token);
      _fetchOrders();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order is now preparing!'),
            backgroundColor: Color(0xFF1967D2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _markAsReady(Order order) async {
    final token = _token;
    if (token == null) return;

    try {
      final api = di.sl<ApiService>();
      await api.markOrderAsReady(orderId: order.id, token: token);
      _fetchOrders();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order ready for pickup!'),
            backgroundColor:          Color(0xFF1E8E3E),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _markAsPickedUp(Order order) async {
    final token = _token;
    if (token == null) return;

    try {
      final api = di.sl<ApiService>();
      await api.markOrderAsPickedUp(orderId: order.id, token: token);
      _fetchOrders();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order is out for delivery!'),
            backgroundColor: Color(0xFF1967D2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _markAsDelivered(Order order) async {
    final token = _token;
    if (token == null) return;

    try {
      final api = di.sl<ApiService>();
      await api.markOrderAsDelivered(orderId: order.id, token: token);
      _fetchOrders();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order delivered!'),
            backgroundColor: Color(0xFF1E8E3E),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ── Time formatting ──────────────────────────

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

  // ── Build ────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F9),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildTabChips(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  // ── Header ───────────────────────────────────

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Color(0xFFFAF9F9),
        border: Border(
          bottom: BorderSide(color: Color(0xFFE5E7EB), width: 1),
        ),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Live Orders',
              style: TextStyle(
                color: Color(0xFF1A1C1C),
                fontSize: 18,
                fontFamily: 'Inter',
                fontWeight: FontWeight.w700,
                height: 1.33,
              ),
            ),
          ),
          _buildAcceptingIndicator(),
          const SizedBox(width: 8),
          ToggleSwitch(
            value: _isAcceptingOrders,
            onChanged: (v) => setState(() => _isAcceptingOrders = v),
          ),
        ],
      ),
    );
  }

  Widget _buildAcceptingIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _isAcceptingOrders
            ? const Color(0xFFE6F4EA)
            : const Color(0xFFFFF1F0),
        borderRadius: BorderRadius.circular(9999),
        border: Border.all(
          color: _isAcceptingOrders
              ? const Color(0xFF1E8E3E)
              : const Color(0xFFD93025),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: _isAcceptingOrders
                  ? const Color(0xFF1E8E3E)
                  : const Color(0xFFD93025),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            _isAcceptingOrders ? 'Accepting' : 'Paused',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _isAcceptingOrders
                  ? const Color(0xFF1E8E3E)
                  : const Color(0xFFD93025),
              height: 1.29,
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab chips ────────────────────────────────

  Widget _buildTabChips() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: SizedBox(
        height: 30,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: 5,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final tabs = [
              ('New', _newOrders.length),
              ('Preparing', _preparingOrders.length),
              ('Ready', _readyOrders.length),
              ('Out for Delivery', _outForDeliveryOrders.length),
              ('Delivered', _deliveredOrders.length),
            ];
            final (label, count) = tabs[index];
            final isActive = _selectedTab == index;

            return GestureDetector(
              onTap: () => setState(() => _selectedTab = index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: isActive ? const Color(0xFFBB0018) : const Color(0xFFEFEDED),
                  borderRadius: BorderRadius.circular(9999),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$label ($count)',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isActive ? Colors.white : const Color(0xFF5E3F3C),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    height: 1.29,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  // ── Body ─────────────────────────────────────

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

    if (_currentOrders.isEmpty) {
      return RefreshIndicator(
        onRefresh: _fetchOrders,
        color: const Color(0xFFBB0018),
        child: ListView(
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.4,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _selectedTab == 0
                      ? Icons.inbox_rounded
                      : _selectedTab == 1
                          ? Icons.kitchen_rounded
                          : _selectedTab == 2
                              ? Icons.check_circle_outline_rounded
                              : _selectedTab == 3
                                  ? Icons.delivery_dining_rounded
                                  : Icons.task_alt_rounded,
                      size: 48,
                      color: const Color(0xFFD9D9D9),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _selectedTab == 0
                      ? 'No new orders yet'
                      : _selectedTab == 1
                          ? 'No orders in preparation'
                          : _selectedTab == 2
                              ? 'No ready orders'
                              : _selectedTab == 3
                                  ? 'No orders out for delivery'
                                  : 'No delivered orders',
                      style: const TextStyle(
                        color: Color(0xFF8E8E93),
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Pull down to refresh',
                      style: TextStyle(
                        color: Color(0xFFBFBFBF),
                        fontSize: 12,
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
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: _currentOrders.length,
        itemBuilder: (context, index) => GestureDetector(
          onTap: () async {
            final changed = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => OrderDetailScreen(
                  order: _currentOrders[index],
                ),
              ),
            );
            if (changed == true && mounted) {
              _fetchOrders();
            }
          },
          child: _buildOrderCard(_currentOrders[index]),
        ),
      ),
    );
  }

  // ── Order card ───────────────────────────────

  Widget _buildOrderCard(Order order) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
          // ── Header: Order # + status badge + time ──
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
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1C1C),
                      height: 1.25,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  _buildStatusPillBadge(order.status),
                  const SizedBox(width: 8),
                  Text(
                    _timeAgo(order.createdAt),
                    style: const TextStyle(
                      color: Color(0xFF5C5C5C),
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      height: 1.38,
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ── Items ─────────────────────────────
          ...order.items.take(3).map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (item.imageUrl != null && item.imageUrl!.isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          item.imageUrl!,
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                      ),
                    if (item.imageUrl != null && item.imageUrl!.isNotEmpty)
                      const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${item.quantity}x ${item.name}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF1A1C1C),
                          fontWeight: FontWeight.w500,
                          height: 1.29,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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

          if (order.items.length > 3)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '+${order.items.length - 3} more items',
                style: const TextStyle(
                  color: Color(0xFF5C5C5C),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  height: 1.38,
                ),
              ),
            ),

          // ── Total ─────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1C1C),
                  height: 1.25,
                ),
              ),
              Text(
                _formatCurrency(order.total),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFBB0018),
                  height: 1.25,
                ),
              ),
            ],
          ),

          // ── Special instructions ──────────────
          if (order.specialInstructions != null &&
              order.specialInstructions!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFFE082)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 14, color: Color(0xFFF9A825)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      order.specialInstructions!,
                      style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF795548),
                          fontWeight: FontWeight.w400,
                          height: 1.38),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ── Delivery address ──────────────────
          if (order.deliveryAddress?.fullAddress != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.location_on_outlined,
                    size: 14, color: Color(0xFF5C5C5C)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    order.deliveryAddress!.fullAddress!,
                    style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF5C5C5C),
                        fontWeight: FontWeight.w400,
                        height: 1.38),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],

          // ── Estimated prep time ───────────────
          if (order.estimatedPrepTime != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.timer_outlined,
                    size: 14, color: Color(0xFF5C5C5C)),
                const SizedBox(width: 4),
                Text(
                  'Est. ${order.estimatedPrepTime} min',
                  style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF5C5C5C),
                      fontWeight: FontWeight.w400,
                      height: 1.38),
                ),
              ],
            ),
          ],

          const SizedBox(height: 16),

          // ── Action buttons ────────────────────
          _buildActionButtons(order),
        ],
      ),
    );
  }

  // ── Status pill badge ────────────────────────

  Widget _buildStatusPillBadge(OrderStatus status) {
    Color bgColor;
    Color textColor;
    String label;

    switch (status) {
      case OrderStatus.pending:
        bgColor = const Color(0xFFFFF1F0);
        textColor = const Color(0xFFBB0018);
        label = 'New';
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
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: textColor,
          height: 1.29,
        ),
      ),
    );
  }

  // ── Action buttons ───────────────────────────

  Widget _buildActionButtons(Order order) {
    switch (_selectedTab) {
      case 0: // New
        return Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 44,
                child: OutlinedButton(
                  onPressed: () => _rejectOrder(order),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF5E3F3C),
                    side: const BorderSide(color: Color(0xFFEFEDED)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Reject',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        height: 1.29),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 44,
                child: ElevatedButton(
                  onPressed: () => _acceptOrder(order),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFBB0018),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Accept Order',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        height: 1.29),
                  ),
                ),
              ),
            ),
          ],
        );

      case 1: // Preparing
        final isAccepted = order.status == OrderStatus.accepted;
        return Column(
          children: [
            if (isAccepted)
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: () => _markAsPreparing(order),
                  icon: const Icon(Icons.kitchen_rounded, size: 18),
                  label: const Text(
                    'Start Preparing',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        height: 1.29),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1967D2),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            if (!isAccepted) ...[
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: () => _markAsReady(order),
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text(
                    'Mark as Ready',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        height: 1.29),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor:          Color(0xFF1E8E3E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ],
        );

      case 2: // Ready
        return SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton.icon(
            onPressed: () => _markAsPickedUp(order),
            icon: const Icon(Icons.delivery_dining_rounded, size: 18),
            label: const Text(
              'Out for Delivery',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  height: 1.29),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1967D2),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
          ),
        );

      case 3: // Out for Delivery
        return SizedBox(
          width: double.infinity,
          height: 44,
          child: ElevatedButton.icon(
            onPressed: () => _markAsDelivered(order),
            icon: const Icon(Icons.task_alt_rounded, size: 18),
            label: const Text(
              'Mark as Delivered',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  height: 1.29),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E8E3E),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 0,
            ),
          ),
        );

      case 4: // Delivered — read-only, no action needed
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFE6F4EA),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color:          Color(0xFF1E8E3E), width: 0.5),
          ),
          child: Row(
            children: [
              const Icon(Icons.task_alt_rounded,
                  color: Color(0xFF1E8E3E), size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Order delivered',
                  style: TextStyle(
                    color: Color(0xFF1A1C1C),
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    height: 1.29,
                  ),
                ),
              ),
              Text(
                order.deliveredAt != null
                    ? _timeAgo(order.deliveredAt!)
                    : 'Just now',
                style: const TextStyle(
                  color: Color(0xFF5C5C5C),
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  height: 1.38,
                ),
              ),
            ],
          ),
        );

      default:
        return const SizedBox.shrink();
    }
  }
