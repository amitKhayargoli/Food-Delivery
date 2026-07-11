import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../../models/order.dart';
import '../../core/services/api_service.dart';
import '../../core/services/supabase_client_service.dart';
import '../../widgets/toggle_switch.dart';
import '../../widgets/rider_map_view.dart';
import '../../injection_container.dart' as di;
import '../../providers/auth_provider.dart';
import '../user/order_detail_screen.dart';
import '../full_screen_map_screen.dart';
import 'manage_restaurant_screen.dart';

class OwnerDashboardScreen extends StatefulWidget {
  const OwnerDashboardScreen({super.key});

  @override
  State<OwnerDashboardScreen> createState() => _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends State<OwnerDashboardScreen> {
  List<Order> _allOrders = [];
  List<Order> _searchResults = [];
  bool _isLoading = true;
  String? _error;
  bool _isAcceptingOrders = true;
  int _selectedTab = 0;
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  String? _searchError;
  Timer? _searchDebounce;
  sb.RealtimeChannel? _orderChannel;

  /// Problem reports for the owner's restaurant
  List<Map<String, dynamic>> _problems = [];
  bool _isLoadingProblems = false;

  /// The restaurant's lat/lng, used for getNearbyRiders queries.
  /// Fetched once from getMyApplication on init.
  double? _restaurantLat;
  double? _restaurantLng;
  bool _isAssigning = false;

  /// Live rider locations keyed by order ID (for riders assigned to orders).
  /// Updated via Realtime subscriptions to the rider_locations table.
  final Map<String, RiderMapPoint> _riderLocations = {};

  /// Realtime channels for each assigned rider, keyed by rider ID.
  final Map<String, sb.RealtimeChannel> _riderChannels = {};

  @override
  void initState() {
    super.initState();
    _fetchOrders();
    _fetchRestaurantSettings();
    _fetchRestaurantLocation();
    _fetchProblems();
  }

  /// Fetch the restaurant's stored lat/lng from the application record.
  Future<void> _fetchRestaurantLocation() async {
    final token = _token;
    if (token == null) return;
    try {
      final app = await di.sl<ApiService>().getMyApplication(token: token);
      if (app != null && mounted) {
        setState(() {
          _restaurantLat = (app['latitude'] as num?)?.toDouble();
          _restaurantLng = (app['longitude'] as num?)?.toDouble();
        });
      }
    } catch (_) {}
  }

  // ── Rider Live Location Tracking ──────────────

  /// Subscribe to live location updates for a rider assigned to an order.
  void _subscribeToRiderLocation(String orderId, String riderId) {
    // Each order gets its own channel (same rider on multiple orders is fine)
    if (_riderChannels.containsKey(orderId)) return;

    try {
      final channel = SupabaseClientService.client.channel('owner-rider-location-$riderId');

      channel.onPostgresChanges(
        event: sb.PostgresChangeEvent.update,
        schema: 'public',
        table: 'rider_locations',
        callback: (payload) {
          final record = payload.newRecord;
          if (record['user_id']?.toString() != riderId) return;
          final lat = record['latitude'] as num?;
          final lng = record['longitude'] as num?;
          if (lat == null || lng == null) return;

          if (mounted) {
            setState(() {
              _riderLocations[orderId] = RiderMapPoint(
                latitude: lat.toDouble(),
                longitude: lng.toDouble(),
                label: 'Rider',
                type: RiderMapPointType.rider,
              );
            });
          }
        },
      );

      channel.subscribe((status, [error]) {
        debugPrint('[RT-OwnerRider] Channel status: $status for rider $riderId');
        if (error != null) debugPrint('[RT-OwnerRider] Error: $error');
      });

      _riderChannels[orderId] = channel;

      // Fetch initial location immediately via REST
      _fetchRiderLocation(orderId, riderId);
    } catch (e) {
      debugPrint('[RT-OwnerRider] Setup error: $e');
    }
  }

  /// Fetch the rider's current location via REST (initial state before Realtime).
  Future<void> _fetchRiderLocation(String orderId, String riderId) async {
    final token = _token;
    if (token == null) return;

    try {
      final api = di.sl<ApiService>();
      final location = await api.getRiderLocation(riderId: riderId, token: token);
      if (location == null || !mounted) return;

      final lat = location['latitude'] as num?;
      final lng = location['longitude'] as num?;
      if (lat == null || lng == null) return;

      setState(() {
        _riderLocations[orderId] = RiderMapPoint(
          latitude: lat.toDouble(),
          longitude: lng.toDouble(),
          label: 'Rider',
          type: RiderMapPointType.rider,
        );
      });
    } catch (e) {
      debugPrint('[RT-OwnerRider] Fetch error: $e');
    }
  }

  /// Subscribe to all riders currently assigned to ready orders.
  void _subscribeToAllAssignedRiders() {
    for (final order in _readyOrders) {
      final riderId = order.deliveryBoyId;
      if (riderId != null && riderId.isNotEmpty) {
        _subscribeToRiderLocation(order.id, riderId);
      }
    }
  }

  /// Unsubscribe from all rider location channels.
  void _unsubscribeFromAllRiderLocations() {
    for (final channel in _riderChannels.values) {
      SupabaseClientService.client.removeChannel(channel);
    }
    _riderChannels.clear();
  }

  /// Estimate rider's ETA to the restaurant using Haversine distance.
  int? _estimateRiderEtaMinutes(String orderId) {
    final riderLoc = _riderLocations[orderId];
    if (riderLoc == null || _restaurantLat == null || _restaurantLng == null) {
      return null;
    }

    const double avgSpeedKmh = 20.0;
    const double R = 6371;

    // Convert all lat/lng to radians before trig functions
    final double lat1Rad = _deg2rad(riderLoc.latitude);
    final double lat2Rad = _deg2rad(_restaurantLat!);
    final double lng1Rad = _deg2rad(riderLoc.longitude);
    final double lng2Rad = _deg2rad(_restaurantLng!);
    final double dLat = lat2Rad - lat1Rad;
    final double dLon = lng2Rad - lng1Rad;

    // Haversine formula — clamp `a` to [0, 1] to prevent NaN from
    // floating-point rounding when coordinates are nearly identical.
    final double a = (sin(dLat / 2) * sin(dLat / 2) +
            cos(lat1Rad) * cos(lat2Rad) * sin(dLon / 2) * sin(dLon / 2))
        .clamp(0.0, 1.0);
    final double c = 2 * asin(sqrt(a));
    final int minutes = ((R * c) / avgSpeedKmh * 60).round();
    return minutes < 1 ? 1 : minutes;
  }

  double _deg2rad(double deg) => deg * (pi / 180.0);

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    _unsubscribeFromOrders();
    _unsubscribeFromAllRiderLocations();
    super.dispose();
  }

  void _subscribeToOrders(String restaurantId) {
    _unsubscribeFromOrders();
    _orderChannel = SupabaseClientService.client.channel('owner-orders-$restaurantId');

    _orderChannel!.onPostgresChanges(
      event: sb.PostgresChangeEvent.insert,
      schema: 'public',
      table: 'orders',
      callback: (payload) {
        final record = payload.newRecord;
        if (record['restaurant_id']?.toString() == restaurantId) {
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
        if (record['restaurant_id']?.toString() == restaurantId) {
          _fetchOrders();
        }
      },
    );

    _orderChannel!.subscribe((status, [error]) {
      debugPrint('[RT-OwnerOrders] Channel status: $status');
      if (error != null) debugPrint('[RT-OwnerOrders] Error: $error');
    });
  }

  void _unsubscribeFromOrders() {
    if (_orderChannel != null) {
      SupabaseClientService.client.removeChannel(_orderChannel!);
      _orderChannel = null;
    }
  }

  // ── Derived data ────────────────────────────

  String? get _token => context.read<AuthProvider>().token;

  List<Order> get _newOrders =>
      _allOrders.where((o) => o.status == OrderStatus.created).toList();

  List<Order> get _preparingOrders => _allOrders
      .where((o) =>
          o.status == OrderStatus.accepted ||
          o.status == OrderStatus.preparing)
      .toList();

  List<Order> get _readyOrders =>
      _allOrders.where((o) => o.status == OrderStatus.outForDelivery).toList();

  List<Order> get _currentOrders {
    if (_isSearching) return _searchResults;
    switch (_selectedTab) {
      case 0: return _newOrders;
      case 1: return _preparingOrders;
      case 2: return _readyOrders;
      default: return []; // Problems handled separately
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

      // Subscribe to real-time updates — get restaurantId from orders or fallback to DB query
      if (_allOrders.isNotEmpty) {
        _subscribeToOrders(_allOrders.first.restaurantId);
      } else {
        _subscribeWithRestaurantIdFallback();
      }

      // Clean up stale rider subscriptions and re-subscribe
      _unsubscribeFromAllRiderLocations();
      _riderLocations.clear();
      _subscribeToAllAssignedRiders();
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _isLoading = false;
      });
      // Still try to subscribe even on error, using DB fallback
      _subscribeWithRestaurantIdFallback();
    } catch (e) {
      setState(() {
        _error = 'Failed to load orders. Check your connection.';
        _isLoading = false;
      });
    }
  }

  /// Fetch the restaurant settings (is_accepting_orders) from the API.
  Future<void> _fetchRestaurantSettings() async {
    final token = _token;
    if (token == null) return;

    try {
      final api = di.sl<ApiService>();
      final app = await api.getMyApplication(token: token);
      if (app != null && mounted) {
        setState(() {
          _isAcceptingOrders = app['is_accepting_orders'] as bool? ?? true;
        });
      }
    } catch (_) {
      // Silently fail — local default is fine
    }
  }

  /// Toggle accepting orders via the API with optimistic UI.
  Future<void> _toggleAcceptingOrders(bool newValue) async {
    final token = _token;
    if (token == null) return;

    // Optimistic update
    setState(() => _isAcceptingOrders = newValue);

    try {
      final api = di.sl<ApiService>();
      await api.toggleAcceptingOrders(isAccepting: newValue, token: token);
    } on ApiException catch (e) {
      // Revert on failure
      if (mounted) setState(() => _isAcceptingOrders = !newValue);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _isAcceptingOrders = !newValue);
    }
  }

  /// Look up the restaurant ID from restaurant_applications and subscribe.
  Future<void> _subscribeWithRestaurantIdFallback() async {
    final userId = SupabaseClientService.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final data = await SupabaseClientService.client
          .from('restaurant_applications')
          .select('id')
          .eq('user_id', userId)
          .maybeSingle();
      if (data != null && data['id'] != null && mounted) {
        _subscribeToOrders(data['id'] as String);
      }
    } catch (_) {
      // Silently fail — user can pull-to-refresh
    }
  }

  // ── Delivery boy assignment ────────────────────

  /// Show a bottom sheet with available delivery boys, sorted by distance
  /// if the restaurant has a registered location, or alphabetically otherwise.
  Future<void> _showAssignDeliveryBoySheet(Order order) async {
    final token = _token;
    if (token == null) return;

    // Show a loading sheet first
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return _AssignDeliveryBoySheet(
          token: token,
          restaurantLat: _restaurantLat,
          restaurantLng: _restaurantLng,
          onAssign: (riderId, riderName) async {
            Navigator.pop(sheetContext);
            await _assignDeliveryBoy(order, riderId, riderName);
          },
        );
      },
    );
  }

  /// Assign a delivery boy to an order via the API.
  Future<void> _assignDeliveryBoy(Order order, String riderId, String riderName) async {
    final token = _token;
    if (token == null) return;

    setState(() => _isAssigning = true);

    try {
      final api = di.sl<ApiService>();
      await api.assignDeliveryBoy(
        orderId: order.id,
        deliveryBoyId: riderId,
        token: token,
      );

      setState(() => _isAssigning = false);
      _fetchOrders();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Delivery boy assigned: $riderName'),
            backgroundColor: const Color(0xFF1E8E3E),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } on ApiException catch (e) {
      setState(() => _isAssigning = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      setState(() => _isAssigning = false);
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

  // ── Problem Reports ─────────────────────────

  Future<void> _fetchProblems() async {
    final token = _token;
    if (token == null) return;

    setState(() => _isLoadingProblems = true);

    try {
      final api = di.sl<ApiService>();
      final problems = await api.getRestaurantProblems(token: token);
      if (!mounted) return;
      setState(() {
        _problems = problems;
        _isLoadingProblems = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingProblems = false);
    }
  }

  Future<void> _handleProblemStatus({
    required String problemId,
    required String status,
    String? adminNote,
    double? refundAmount,
  }) async {
    final token = _token;
    if (token == null) return;

    try {
      final api = di.sl<ApiService>();
      await api.updateProblemStatus(
        problemId: problemId,
        status: status,
        adminNote: adminNote,
        refundAmount: refundAmount,
        token: token,
      );
      if (!mounted) return;
      _fetchProblems();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Report ${status == 'APPROVED' ? 'approved' : 'rejected'}.'),
          backgroundColor: status == 'APPROVED'
              ? const Color(0xFF1E8E3E)
              : const Color(0xFFBB0018),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message), backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating),
      );
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

  // ── Search ───────────────────────────────────

  Future<void> _performSearch(String query) async {
    final token = _token;
    if (token == null || query.trim().isEmpty) {
      setState(() {
        _isSearching = false;
        _searchResults = [];
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _searchError = null;
    });

    try {
      final api = di.sl<ApiService>();
      final rawOrders = await api.searchOrders(query: query.trim(), token: token);
      if (!mounted) return;
      setState(() {
        _searchResults = rawOrders.map((o) => Order.fromJson(o)).toList();
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _searchError = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searchError = 'Search failed.';
      });
    }
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {
      _isSearching = false;
      _searchResults = [];
      _searchError = null;
    });
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
            _buildSearchBar(),
            if (!_isSearching) _buildTabChips(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  // ── Search bar ───────────────────────────────

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        controller: _searchController,
        onSubmitted: (value) => _performSearch(value),
        onChanged: (value) {
          _searchDebounce?.cancel();
          if (value.isEmpty && _isSearching) {
            _clearSearch();
            return;
          } else if (value.isEmpty) {
            return;
          }
          _searchDebounce = Timer(const Duration(milliseconds: 300), () {
            _performSearch(value);
          });
        },
        decoration: InputDecoration(
          hintText: 'Search by order #...',
          hintStyle: const TextStyle(color: Color(0xFF999999), fontSize: 14),
          prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Color(0xFF999999)),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18, color: Color(0xFF999999)),
                  onPressed: _clearSearch,
                )
              : null,
          filled: true,
          fillColor: const Color(0xFFF0F0F0),
          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFBB0018), width: 1.5),
          ),
        ),
        style: const TextStyle(fontSize: 14),
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
          Expanded(
            child: Row(
              children: [
                const Text(
                  'Live Orders',
                  style: TextStyle(
                    color: Color(0xFF1A1C1C),
                    fontSize: 18,
                    fontFamily: 'Inter',
                    fontWeight: FontWeight.w700,
                    height: 1.33,
                  ),
                ),
                const Spacer(),
                // Settings gear → Manage Restaurant
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ManageRestaurantScreen(),
                      ),
                    );
                  },
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F0F0),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.settings_rounded,
                      size: 20,
                      color: Color(0xFF5C5C5C),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
          _buildAcceptingIndicator(),
          const SizedBox(width: 8),
          ToggleSwitch(
            value: _isAcceptingOrders,
            onChanged: _toggleAcceptingOrders,
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
            : Colors.white,
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
          itemCount: 4,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (context, index) {
            final tabs = [
              ('New', _newOrders.length),
              ('Preparing', _preparingOrders.length),
              ('Ready', _readyOrders.length),
              ('Problems', _problems.length),
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

    if (_selectedTab == 3) return _buildProblemsTab();

    if (_currentOrders.isEmpty) {
      return RefreshIndicator(
        onRefresh: _isSearching ? () async {} : _fetchOrders,
        color: const Color(0xFFBB0018),
        child: ListView(
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.4,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isSearching) ...[
                      const Icon(Icons.search_off_rounded,
                          size: 48, color: Color(0xFFD9D9D9)),
                      const SizedBox(height: 12),
                      Text(
                        _searchError ??
                            'No orders found for "${_searchController.text}"',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF8E8E93),
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: _clearSearch,
                        child: const Text(
                          'Clear search',
                          style: TextStyle(
                            color: Color(0xFFBB0018),
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ] else ...[
                      Icon(
                        _selectedTab == 0
                            ? Icons.inbox_rounded
                            : _selectedTab == 1
                                ? Icons.kitchen_rounded
                                : Icons.check_circle_outline_rounded,
                        size: 48,
                        color: const Color(0xFFD9D9D9),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _selectedTab == 0
                            ? 'No new orders yet'
                            : _selectedTab == 1
                                ? 'No orders in preparation'
                                : 'No ready orders',
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
        itemBuilder: (context, index) => _buildOrderCard(_currentOrders[index]),
      ),
    );
  }

  // ── Order card ───────────────────────────────

  Widget _buildOrderCard(Order order) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => OrderDetailScreen(
              order: order,
              isOwner: true,
            ),
          ),
        );
      },
      child: Container(
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
    ),
    );
  }

  // ── Status pill badge ────────────────────────

  Widget _buildStatusPillBadge(OrderStatus status) {
    Color bgColor;
    Color textColor;
    String label;

    switch (status) {
      case OrderStatus.created:
        bgColor = Colors.white;
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
        final bool isAssigned = order.deliveryBoyId != null && order.deliveryBoyId!.isNotEmpty;
        final String? riderName = order.deliveryBoyName;
        final hasRiderLocation =
            isAssigned && _riderLocations.containsKey(order.id);
        final riderLoc = _riderLocations[order.id];
        final etaMinutes = isAssigned ? _estimateRiderEtaMinutes(order.id) : null;

        // Build map points once, reused by both RiderMapView and FullScreenMapScreen
        final pickupLoc = RiderMapPoint(
          latitude: _restaurantLat ?? 0,
          longitude: _restaurantLng ?? 0,
          label: 'Restaurant',
          type: RiderMapPointType.pickup,
        );
        final dropoffLoc = order.deliveryAddress?.latitude != null &&
                order.deliveryAddress?.longitude != null
            ? RiderMapPoint(
                latitude: order.deliveryAddress!.latitude!,
                longitude: order.deliveryAddress!.longitude!,
                label: 'Delivery',
                type: RiderMapPointType.dropoff,
              )
            : null;

        return Column(
          children: [
            // ── Status card ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              decoration: BoxDecoration(
                color: isAssigned
                    ? const Color(0xFFE8F0FE)
                    : const Color(0xFFE6F4EA),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isAssigned
                      ? const Color(0xFF1967D2)
                      : const Color(0xFF1E8E3E),
                  width: 0.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isAssigned ? Icons.moped_rounded : Icons.check_circle,
                    color: isAssigned ? const Color(0xFF1967D2) : const Color(0xFF1E8E3E),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isAssigned && riderName != null
                          ? 'Assigned to $riderName'
                          : 'Ready for pickup / delivery',
                      style: const TextStyle(
                        color: Color(0xFF1A1C1C),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        height: 1.29,
                      ),
                    ),
                  ),
                  Text(
                    order.readyAt != null
                        ? _timeAgo(order.readyAt!)
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
            ),

            // ── Rider Live Location (only when rider is assigned) ──
            if (isAssigned) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F8FF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF1967D2).withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Rider info header ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                      child: Row(
                        children: [
                          const Icon(Icons.my_location_rounded,
                              size: 16, color: Color(0xFF1967D2)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              hasRiderLocation
                                  ? etaMinutes != null
                                      ? 'Rider ~$etaMinutes min away'
                                      : 'Rider nearby'
                                  : 'Loading rider location...',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1967D2),
                              ),
                            ),
                          ),
                          if (hasRiderLocation)
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFF34C759),
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                    ),

                    // ── Mini map ──
                    if (hasRiderLocation &&
                        _restaurantLat != null &&
                        _restaurantLng != null &&
                        riderLoc != null)
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(12)),
                        child: SizedBox(
                          height: 130,
                          child: RiderMapView(
                            riderLocation: riderLoc,
                            pickupLocation: pickupLoc,
                            dropoffLocation: dropoffLoc,
                            height: 130,
                            showEtaBar: false,
                            etaText: etaMinutes != null
                                ? '$etaMinutes min'
                                : null,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => FullScreenMapScreen(
                                    riderLocation: riderLoc,
                                    riderId: order.deliveryBoyId ?? '',
                                    pickupLocation: pickupLoc,
                                    dropoffLocation: dropoffLoc,
                                    etaText: etaMinutes != null
                                        ? '$etaMinutes min'
                                        : null,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),

                    // ── ETA bar at bottom if map is shown ──
                    if (hasRiderLocation && etaMinutes != null &&
                        _restaurantLat != null && _restaurantLng != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: const BoxDecoration(
                          color: Color(0xFFE8F0FE),
                          borderRadius: BorderRadius.vertical(
                              bottom: Radius.circular(12)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.access_time_rounded,
                                size: 14, color: Color(0xFF1967D2)),
                            const SizedBox(width: 4),
                            Text(
                              etaMinutes <= 1
                                  ? 'Arriving now'
                                  : 'Rider arriving in $etaMinutes min',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1A1C1C),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 12),

            // ── Assign / Reassign button ──
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _isAssigning
                    ? null
                    : () => _showAssignDeliveryBoySheet(order),
                icon: _isAssigning
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        isAssigned
                            ? Icons.swap_horiz_rounded
                            : Icons.person_add_alt_1_rounded,
                        size: 20,
                      ),
                label: Text(
                  isAssigned ? 'Reassign Delivery Boy' : 'Assign Delivery Boy',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    height: 1.29,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1967D2),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFEFEDED),
                  disabledForegroundColor: const Color(0xFFBFBFBF),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        );

      default:
        return const SizedBox.shrink();
    }
  }

  // ── Problems Tab ─────────────────────────────

  Widget _buildProblemsTab() {
    if (_isLoadingProblems) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFFBB0018)),
            SizedBox(height: 16),
            Text('Loading reports...',
                style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14)),
          ],
        ),
      );
    }

    if (_problems.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.flag_outlined, size: 48, color: Color(0xFFD9D9D9)),
            const SizedBox(height: 12),
            const Text('No problem reports yet',
                style: TextStyle(color: Color(0xFF8E8E93), fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            const Text('Customer issues will appear here',
                style: TextStyle(color: Color(0xFFBFBFBF), fontSize: 13)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchProblems,
      color: const Color(0xFFBB0018),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _problems.length,
        itemBuilder: (context, index) => _buildProblemCard(_problems[index]),
      ),
    );
  }

  Widget _buildProblemCard(Map<String, dynamic> problem) {
    final status = problem['status'] as String? ?? 'PENDING';
    final issueType = problem['issue_type'] as String? ?? '';
    final description = problem['description'] as String? ?? '';
    final customerName = problem['customer_name'] as String? ?? 'Unknown';
    final orderNumber = problem['order_number'] as String? ?? '';
    final isPending = status == 'PENDING';

    final typeLabels = {
      'wrong_item': 'Wrong Item',
      'missing_item': 'Missing Item',
      'quality': 'Food Quality',
      'other': 'Other Issue',
    };
    final typeIcons = {
      'wrong_item': Icons.fastfood_outlined,
      'missing_item': Icons.inventory_2_outlined,
      'quality': Icons.thumb_down_outlined,
      'other': Icons.more_horiz,
    };

    Color statusColor;
    String statusLabel;
    switch (status) {
      case 'APPROVED':
        statusColor = const Color(0xFF1E8E3E);
        statusLabel = 'Approved';
      case 'REJECTED':
        statusColor = const Color(0xFFBB0018);
        statusLabel = 'Rejected';
      default:
        statusColor = const Color(0xFFF9A825);
        statusLabel = 'Pending';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: isPending
            ? Border.all(color: const Color(0xFFF9A825).withValues(alpha: 0.3))
            : null,
        boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 8, offset: const Offset(0, 3),
        )],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: isPending ? const Color(0xFFFFF8E1) : const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  typeIcons[issueType] ?? Icons.flag_outlined,
                  size: 20,
                  color: isPending ? const Color(0xFFF9A825) : const Color(0xFF8E8E93),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(typeLabels[issueType] ?? issueType,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                                color: Color(0xFF1A1C1C))),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(statusLabel,
                              style: TextStyle(
                                  fontSize: 10, fontWeight: FontWeight.w600,
                                  color: statusColor)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text('$customerName • Order $orderNumber',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93))),
                  ],
                ),
              ),
            ],
          ),

          if (description.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(description,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF5C5C5C))),
            ),
          ],

          // Action buttons (only for pending)
          if (isPending) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: OutlinedButton.icon(
                      onPressed: () => _showRejectDialog(problem),
                      icon: const Icon(Icons.close_rounded, size: 16),
                      label: const Text('Reject',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFBB0018),
                        side: const BorderSide(color: Color(0xFFBB0018)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 40,
                    child: ElevatedButton.icon(
                      onPressed: () => _showApproveDialog(problem),
                      icon: const Icon(Icons.check_circle, size: 16),
                      label: const Text('Approve Refund',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E8E3E),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
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

  Future<void> _showApproveDialog(Map<String, dynamic> problem) async {
    final noteCtrl = TextEditingController();
    final refundCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Approve Refund',
              style: TextStyle(fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Approve the refund for this problem report?',
                  style: TextStyle(fontSize: 14, color: Color(0xFF5C5C5C))),
              const SizedBox(height: 12),
              TextField(
                controller: refundCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: 'Refund amount (e.g. 250)',
                  hintStyle: const TextStyle(color: Color(0xFFBFBFBF), fontSize: 13),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.all(10),
                  isDense: true,
                  prefixText: 'Rs. ',
                  prefixStyle: const TextStyle(color: Color(0xFF1A1C1C), fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: noteCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'Add a note (optional)',
                  hintStyle: const TextStyle(color: Color(0xFFBFBFBF), fontSize: 13),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.all(10),
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF8E8E93))),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E8E3E),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
              child: const Text('Approve', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      final refundText = refundCtrl.text.trim();
      await _handleProblemStatus(
        problemId: problem['id'] as String? ?? '',
        status: 'APPROVED',
        adminNote: noteCtrl.text.trim().isNotEmpty ? noteCtrl.text.trim() : null,
        refundAmount: refundText.isNotEmpty ? double.tryParse(refundText) : null,
      );
    }
    noteCtrl.dispose();
    refundCtrl.dispose();
  }

  Future<void> _showRejectDialog(Map<String, dynamic> problem) async {
    final noteCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reject Report',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Reject this problem report? The customer will be notified.',
                style: TextStyle(fontSize: 14, color: Color(0xFF5C5C5C))),
            const SizedBox(height: 12),
            TextField(
              controller: noteCtrl,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'Reason for rejection (optional)',
                hintStyle: const TextStyle(color: Color(0xFFBFBFBF), fontSize: 13),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.all(10),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF8E8E93))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFBB0018),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            child: const Text('Reject', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _handleProblemStatus(
        problemId: problem['id'] as String? ?? '',
        status: 'REJECTED',
        adminNote: noteCtrl.text.trim().isNotEmpty ? noteCtrl.text.trim() : null,
      );
    }
    noteCtrl.dispose();
  }
}

// ──────────────────────────────────────────────
//  Assign Delivery Boy — bottom sheet widget
// ──────────────────────────────────────────────

/// Modal bottom sheet that fetches nearby/available delivery boys and
/// lets the owner pick one to assign to an order.
class _AssignDeliveryBoySheet extends StatefulWidget {
  final String token;
  final double? restaurantLat;
  final double? restaurantLng;
  final Future<void> Function(String riderId, String riderName) onAssign;

  const _AssignDeliveryBoySheet({
    required this.token,
    this.restaurantLat,
    this.restaurantLng,
    required this.onAssign,
  });

  @override
  State<_AssignDeliveryBoySheet> createState() => _AssignDeliveryBoySheetState();
}

class _AssignDeliveryBoySheetState extends State<_AssignDeliveryBoySheet> {
  List<Map<String, dynamic>> _riders = [];
  bool _isLoading = true;
  String? _error;
  bool _isAssigning = false;

  @override
  void initState() {
    super.initState();
    _fetchRiders();
  }

  Future<void> _fetchRiders() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = di.sl<ApiService>();
      List<Map<String, dynamic>> riders;

      // Prefer nearby (geo-sorted) if we have restaurant location
      if (widget.restaurantLat != null && widget.restaurantLng != null) {
        riders = await api.getNearbyRiders(
          latitude: widget.restaurantLat!,
          longitude: widget.restaurantLng!,
          limit: 10,
          token: widget.token,
        );
      } else {
        // Fall back to listing all active delivery boys
        riders = await api.getDeliveryBoys(token: widget.token);
      }

      if (!mounted) return;
      setState(() {
        _riders = riders;
        _isLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load delivery boys.';
        _isLoading = false;
      });
    }
  }

  String _riderDisplayName(Map<String, dynamic> rider) {
    return (rider['username'] as String? ?? '').isNotEmpty
        ? rider['username'] as String
        : 'Rider ${rider['user_id']?.toString().substring(0, 8) ?? ''}';
  }

  String _riderInfo(Map<String, dynamic> rider) {
    final parts = <String>[];
    final phone = rider['phone'] as String?;
    if (phone != null && phone.isNotEmpty) parts.add(phone);
    final distance = rider['distance_km'] as num?;
    if (distance != null) {
      parts.add('${distance.toStringAsFixed(1)} km away');
    }
    return parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.65,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Handle ──
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // ── Title ──
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Icon(Icons.moped_rounded, size: 20, color: Color(0xFFBB0018)),
                  SizedBox(width: 8),
                  Text(
                    'Assign Delivery Boy',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1C1C),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                widget.restaurantLat != null
                    ? 'Nearest available riders'
                    : 'All available riders',
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF8E8E93),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),

            // ── Body ──
            Flexible(
              child: _buildBody(),
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(48),
        child: Center(
          child: Column(
            children: [
              CircularProgressIndicator(color: Color(0xFFBB0018)),
              SizedBox(height: 16),
              Text(
                'Finding nearby riders...',
                style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            const Icon(Icons.error_outline, size: 40, color: Color(0xFF8E8E93)),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: _fetchRiders,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_riders.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            const Icon(Icons.person_off_outlined, size: 40, color: Color(0xFFD9D9D9)),
            const SizedBox(height: 12),
            const Text(
              'No riders available',
              style: TextStyle(
                color: Color(0xFF8E8E93),
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Ask riders to go online',
              style: TextStyle(color: Color(0xFFBFBFBF), fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shrinkWrap: true,
      itemCount: _riders.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 60),
      itemBuilder: (context, index) {
        final rider = _riders[index];
        final riderId = rider['user_id'] as String? ?? rider['id'] as String? ?? '';
        final displayName = _riderDisplayName(rider);
        final info = _riderInfo(rider);

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          leading: CircleAvatar(
            backgroundColor: Colors.white,
            radius: 22,
            child: const Icon(Icons.person, color: Color(0xFFBB0018), size: 22),
          ),
          title: Text(
            displayName,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1C1C),
            ),
          ),
          subtitle: info.isNotEmpty
              ? Text(
                  info,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF8E8E93)),
                )
              : null,
          trailing: _isAssigning
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add_circle_outline,
                  color: Color(0xFF1967D2), size: 22),
          onTap: _isAssigning
              ? null
              : () async {
                  setState(() => _isAssigning = true);
                  await widget.onAssign(riderId, displayName);
                },
        );
      },
    );
  }
}
