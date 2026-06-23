import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../../models/order.dart';
import '../../core/services/api_service.dart';
import '../../core/services/supabase_client_service.dart';
import '../../injection_container.dart' as di;
import '../../providers/auth_provider.dart';
import '../../providers/rider_notes_provider.dart';

class DeliveryJobsScreen extends StatefulWidget {
  const DeliveryJobsScreen({super.key});

  @override
  State<DeliveryJobsScreen> createState() => _DeliveryJobsScreenState();
}

class _DeliveryJobsScreenState extends State<DeliveryJobsScreen> {
  List<Order> _jobs = [];
  bool _isLoading = true;
  String? _error;
  bool _isAccepting = false;
  sb.RealtimeChannel? _orderChannel;
  // Rider note controllers per order
  final Map<String, TextEditingController> _riderNoteCtrls = {};
  final Map<String, String> _lastSentNotes = {};

  String? get _token => context.read<AuthProvider>().token;
  String? get _userId => SupabaseClientService.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _fetchJobs();
  }

  @override
  void dispose() {
    _unsubscribeFromOrders();
    for (final ctrl in _riderNoteCtrls.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _subscribeToOrders(String userId) {
    _unsubscribeFromOrders();
    _orderChannel = SupabaseClientService.client.channel('delivery-jobs-$userId');

    _orderChannel!.onPostgresChanges(
      event: sb.PostgresChangeEvent.update,
      schema: 'public',
      table: 'orders',
      callback: (payload) {
        final record = payload.newRecord;
        if (record['delivery_boy_id']?.toString() == userId) {
          _fetchJobs();
        }
      },
    );

    _orderChannel!.onPostgresChanges(
      event: sb.PostgresChangeEvent.insert,
      schema: 'public',
      table: 'orders',
      callback: (payload) {
        final record = payload.newRecord;
        if (record['delivery_boy_id']?.toString() == userId) {
          _fetchJobs();
        }
      },
    );

    _orderChannel!.subscribe((status, [error]) {
      debugPrint('[RT-DeliveryJobs] Channel status: $status');
      if (error != null) debugPrint('[RT-DeliveryJobs] Error: $error');
    });
  }

  void _unsubscribeFromOrders() {
    if (_orderChannel != null) {
      SupabaseClientService.client.removeChannel(_orderChannel!);
      _orderChannel = null;
    }
  }

  Future<void> _fetchJobs() async {
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
      final rawOrders = await api.getMyDeliveryJobs(token: token);
      if (!mounted) return;
      // Clear old rider note controllers so fresh data is reflected
      for (final ctrl in _riderNoteCtrls.values) {
        ctrl.dispose();
      }
      _riderNoteCtrls.clear();
      setState(() {
        _jobs = rawOrders.map((o) => Order.fromJson(o)).toList();
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
        _error = 'Failed to load jobs. Check your connection.';
        _isLoading = false;
      });
    }
  }

  Future<void> _acceptJob(Order order) async {
    final token = _token;
    if (token == null) return;

    setState(() => _isAccepting = true);
    try {
      final api = di.sl<ApiService>();
      await api.markOrderAsPickedUp(orderId: order.id, token: token);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Job accepted! Order picked up.'),
            backgroundColor: Color(0xFF1E8E3E),
            behavior: SnackBarBehavior.floating,
          ),
        );
        _fetchJobs();
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
    } finally {
      if (mounted) setState(() => _isAccepting = false);
    }
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
          'Assigned Jobs',
          style: TextStyle(fontWeight: FontWeight.w700),
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
              'Loading jobs...',
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
                onPressed: _fetchJobs,
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

    if (_jobs.isEmpty) {
      return RefreshIndicator(
        onRefresh: _fetchJobs,
        color: const Color(0xFFBB0018),
        child: ListView(
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.5,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.moped_rounded,
                        size: 56, color: Color(0xFFD9D9D9)),
                    const SizedBox(height: 12),
                    const Text(
                      'No jobs assigned',
                      style: TextStyle(
                        color: Color(0xFF8E8E93),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'New delivery jobs will appear here',
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
      onRefresh: _fetchJobs,
      color: const Color(0xFFBB0018),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _jobs.length,
        itemBuilder: (context, index) => _buildJobCard(_jobs[index]),
      ),
    );
  }

  Widget _buildJobCard(Order order) {
    // Determine pickup (restaurant) and dropoff (customer) addresses
    final pickupAddress = order.items.isNotEmpty
        ? 'Restaurant'
        : 'Pickup point';
    final dropoffAddress = order.deliveryAddress?.fullAddress ?? 'Customer address';

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
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
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                ],
              ),
              _buildStatusBadge(order.status),
            ],
          ),
          const SizedBox(height: 16),

          // ── Order items ──
          ...order.items.take(2).map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${item.quantity}x ${item.name}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF5C5C5C),
                  ),
                ),
              )),
          if (order.items.length > 2)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                '+${order.items.length - 2} more items',
                style: const TextStyle(
                  color: Color(0xFFBFBFBF),
                  fontSize: 12,
                ),
              ),
            ),

          const SizedBox(height: 12),

          // ── Pickup ──
          Row(
            children: [
              const Icon(Icons.store, color: Color(0xFF8E8E93), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Pickup: $pickupAddress',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // ── Dropoff ──
          Row(
            children: [
              const Icon(Icons.location_on, color: Color(0xFF8E8E93), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Dropoff: $dropoffAddress',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // ── Total ──
          Row(
            children: [
              const Icon(Icons.receipt_outlined, color: Color(0xFF8E8E93), size: 20),
              const SizedBox(width: 8),
              Text(
                'Total: ${_formatCurrency(order.total)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A),
                ),
              ),
            ],
          ),

          // ── Customer Landmark / Delivery Notes ──
          if (order.deliveryNotes != null && order.deliveryNotes!.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFFE082)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline,
                      size: 14, color: Color(0xFFF9A825)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Customer Note',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF795548)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          order.deliveryNotes!,
                          style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF795548)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── Rider Quick Note Input ──
          _buildRiderNoteInput(order),

          const SizedBox(height: 16),

          // ── Accept Job button ──
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: order.status == OrderStatus.ready && !_isAccepting
                  ? () => _acceptJob(order)
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFBB0018),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFEFEDED),
                disabledForegroundColor: const Color(0xFFBFBFBF),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: _isAccepting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      order.status == OrderStatus.ready
                          ? 'Accept Job (Picked Up)'
                          : 'Status: ${order.status.name.toUpperCase()}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRiderNoteInput(Order order) {
    // Get or create a controller for this order
    final ctrl = _riderNoteCtrls.putIfAbsent(
      order.id,
      () => TextEditingController(
        text: order.riderNote ?? '',
      ),
    );
    final notesProvider = context.read<RiderNotesProvider>();
    final isSending = notesProvider.isSending(order.id);
    final hasExistingNote = order.riderNote != null && order.riderNote!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.chat_outlined,
                size: 16, color: Color(0xFF1967D2)),
            const SizedBox(width: 6),
            const Text(
              'Quick Note to Customer',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1967D2),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (hasExistingNote) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F0FE),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFF1967D2).withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle,
                    size: 14, color: Color(0xFF1967D2)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Sent: "${order.riderNote!}"',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF1967D2),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 40,
                child: TextField(
                  controller: ctrl,
                  enabled: !isSending,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'e.g. "I have arrived!"',
                    hintStyle: const TextStyle(color: Color(0xFFBFBFBF), fontSize: 13),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF1967D2)),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                    isDense: true,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 40,
              width: 40,
              child: ElevatedButton(
                onPressed: ctrl.text.trim().isEmpty || isSending
                    ? null
                    : () {
                        final token = _token;
                        if (token == null) return;
                        notesProvider.sendRiderNote(
                          orderId: order.id,
                          note: ctrl.text.trim(),
                          token: token,
                        );
                        ctrl.clear();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Note sent to customer!'),
                              backgroundColor: Color(0xFF1967D2),
                              behavior: SnackBarBehavior.floating,
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1967D2),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFEFEDED),
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
                child: isSending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusBadge(OrderStatus status) {
    Color bgColor;
    Color textColor;
    String label;

    switch (status) {
      case OrderStatus.ready:
        bgColor = const Color(0xFFE6F4EA);
        textColor = const Color(0xFF1E8E3E);
        label = 'Ready';
      case OrderStatus.pickedUp:
        bgColor = const Color(0xFFE8F0FE);
        textColor = const Color(0xFF1967D2);
        label = 'Picked Up';
      default:
        bgColor = const Color(0xFFFFF8E1);
        textColor = const Color(0xFFF9A825);
        label = status.name.toUpperCase();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}
