import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/order.dart';
import '../../core/services/api_service.dart';
import '../../widgets/rider_map_view.dart';
import '../../injection_container.dart' as di;
import '../../providers/auth_provider.dart';
import '../user/support_chat_screen.dart';
import 'admin_coupon_management_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // Riders tab
  List<Map<String, dynamic>> _riders = [];
  bool _isLoadingRiders = true;
  String? _ridersError;

  // Performance tab
  List<Map<String, dynamic>> _leaderboard = [];
  bool _isLoadingPerformance = true;

  // Add Rider form
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _isCreating = false;
  String? _createError;
  String? _createSuccess;

  // Dashboard summary
  int _totalRiders = 0;
  int _onlineRiders = 0;
  int _onDeliveryRiders = 0;

  // Orders tab
  List<Order> _deliveredOrders = [];
  bool _isLoadingOrders = false;
  String? _ordersFilter;

  // Rider Applications tab
  List<Map<String, dynamic>> _riderApplications = [];
  bool _isLoadingApplications = true;
  String? _applicationsError;

  // Support tab
  List<Map<String, dynamic>> _supportConversations = [];
  bool _isLoadingSupport = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
    _fetchRiders();
    _fetchPerformance();
    _fetchDeliveredOrders();
    _fetchRiderApplications();
    _fetchSupportConversations();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  String? get _token => context.read<AuthProvider>().token;

  // ── Data Fetching ────────────────────────────

  Future<void> _fetchRiders() async {
    final token = _token;
    if (token == null) return;

    setState(() {
      _isLoadingRiders = true;
      _ridersError = null;
    });

    try {
      final api = di.sl<ApiService>();
      final riders = await api.getAllRiders(token: token);
      if (!mounted) return;
      setState(() {
        _riders = riders;
        _totalRiders = riders.length;
        _onlineRiders = riders.where((r) => r['is_online'] == true).length;
        _onDeliveryRiders = riders.where((r) => r['is_on_delivery'] == true).length;
        _isLoadingRiders = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _ridersError = e.message;
        _isLoadingRiders = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ridersError = 'Failed to load riders.';
        _isLoadingRiders = false;
      });
    }
  }

  Future<void> _fetchPerformance() async {
    final token = _token;
    if (token == null) return;

    setState(() => _isLoadingPerformance = true);

    try {
      final api = di.sl<ApiService>();
      final leaderboard = await api.getRiderPerformance(token: token);
      if (!mounted) return;
      setState(() {
        _leaderboard = leaderboard;
        _isLoadingPerformance = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingPerformance = false);
    }
  }

  /// Fetch all delivered orders for dispute resolution purposes.
  Future<void> _fetchDeliveredOrders() async {
    final token = _token;
    if (token == null) return;

    setState(() => _isLoadingOrders = true);

    try {
      final api = di.sl<ApiService>();
      final rawOrders = await api.getAllOrders(token: token);
      if (!mounted) return;
      setState(() {
        _deliveredOrders = rawOrders
            .map((o) => Order.fromJson(o))
            .where((o) => o.status == OrderStatus.delivered)
            .toList();
        _isLoadingOrders = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingOrders = false);
    }
  }

  // ── Create Rider ─────────────────────────────

  Future<void> _createRider() async {
    final token = _token;
    if (token == null) return;

    final username = _usernameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (username.isEmpty || phone.isEmpty || password.isEmpty) {
      setState(() => _createError = 'Username, phone, and password are required.');
      return;
    }

    if (password.length < 6) {
      setState(() => _createError = 'Password must be at least 6 characters.');
      return;
    }

    setState(() {
      _isCreating = true;
      _createError = null;
      _createSuccess = null;
    });

    try {
      final api = di.sl<ApiService>();
      await api.createRider(
        username: username,
        email: _emailCtrl.text.trim().isNotEmpty ? _emailCtrl.text.trim() : null,
        phone: phone,
        password: password,
        token: token,
      );
      if (!mounted) return;
      setState(() {
        _isCreating = false;
        _createSuccess = 'Rider "$username" created successfully!';
        _createError = null;
      });
      _usernameCtrl.clear();
      _emailCtrl.clear();
      _phoneCtrl.clear();
      _passwordCtrl.clear();
      _fetchRiders();
      _fetchPerformance();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isCreating = false;
        _createError = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCreating = false;
        _createError = 'Failed to create rider.';
      });
    }
  }

  /// Fetch all pending rider applications for admin review.
  Future<void> _fetchRiderApplications() async {
    final token = _token;
    if (token == null) return;

    setState(() {
      _isLoadingApplications = true;
      _applicationsError = null;
    });

    try {
      final api = di.sl<ApiService>();
      final apps = await api.getAllRiderApplications(token: token);
      if (!mounted) return;
      setState(() {
        _riderApplications = apps;
        _isLoadingApplications = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _applicationsError = e.message;
        _isLoadingApplications = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _applicationsError = 'Failed to load applications.';
        _isLoadingApplications = false;
      });
    }
  }

  /// Approve a rider application.
  Future<void> _approveRiderApplication(Map<String, dynamic> app) async {
    final token = _token;
    if (token == null) return;

    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve Rider'),
        content: Text(
          'Approve "${app['full_name'] as String? ?? 'Unknown'}" as a delivery partner?\n\n'
          'They will receive rider access and be able to accept delivery jobs.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Approve',
              style: TextStyle(color: Color(0xFF1E8E3E)),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final api = di.sl<ApiService>();
      await api.updateRiderApplicationStatus(
        applicationId: app['id'] as String,
        status: 'APPROVED',
        token: token,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('${app['full_name']} approved as delivery partner!'),
          backgroundColor: const Color(0xFF1E8E3E),
        ),
      );
      _fetchRiderApplications();
      _fetchRiders();
      _fetchPerformance();
    } on ApiException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: const Color(0xFFF5222D),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Failed to approve application.'),
          backgroundColor: Color(0xFFF5222D),
        ),
      );
    }
  }

  /// Reject a rider application.
  Future<void> _rejectRiderApplication(Map<String, dynamic> app) async {
    final token = _token;
    if (token == null) return;

    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Rider'),
        content: Text(
          'Reject "${app['full_name'] as String? ?? 'Unknown'}" as a delivery partner?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Reject',
              style: TextStyle(color: Color(0xFFF5222D)),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final api = di.sl<ApiService>();
      await api.updateRiderApplicationStatus(
        applicationId: app['id'] as String,
        status: 'REJECTED',
        token: token,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Application rejected.'),
          backgroundColor: Color(0xFF8E8E93),
        ),
      );
      _fetchRiderApplications();
    } on ApiException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: const Color(0xFFF5222D),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Failed to reject application.'),
          backgroundColor: Color(0xFFF5222D),
        ),
      );
    }
  }

  /// Fetch all support conversations for admin reply.
  Future<void> _fetchSupportConversations() async {
    final token = _token;
    if (token == null) return;

    setState(() => _isLoadingSupport = true);

    try {
      final api = di.sl<ApiService>();
      final conversations = await api.getAllSupportConversations(token: token);
      if (!mounted) return;
      setState(() {
        _supportConversations = conversations;
        _isLoadingSupport = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingSupport = false);
    }
  }

  // ── Formatting ───────────────────────────────

  String _timeAgo(String? dt) {
    if (dt == null) return 'Never';
    final dateTime = DateTime.tryParse(dt);
    if (dateTime == null) return 'Unknown';
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return dateTime.toString().substring(0, 10);
  }

  IconData _statusIcon(bool isOnline, bool isOnDelivery) {
    if (isOnDelivery) return Icons.moped_rounded;
    if (isOnline) return Icons.check_circle;
    return Icons.cancel_rounded;
  }

  Color _statusColor(bool isOnline, bool isOnDelivery) {
    if (isOnDelivery) return const Color(0xFF1967D2);
    if (isOnline) return const Color(0xFF1E8E3E);
    return const Color(0xFFBFBFBF);
  }

  String _statusLabel(bool isOnline, bool isOnDelivery) {
    if (isOnDelivery) return 'On Delivery';
    if (isOnline) return 'Online';
    return 'Offline';
  }

  // ── Build ────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F9),
      appBar: AppBar(
        title: const Text(
          'Admin Dashboard',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1C1C),
        elevation: 0.5,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFBB0018),
          labelColor: const Color(0xFFBB0018),
          unselectedLabelColor: const Color(0xFF8E8E93),
          labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          tabs: [
            const Tab(text: 'Riders'),
            const Tab(text: 'Performance'),
            const Tab(text: 'Add Rider'),
            const Tab(text: 'Coupons'),
            const Tab(text: 'Orders'),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Applications'),
                  if (_riderApplications.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFBB0018),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_riderApplications.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Tab(text: 'Support'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildRidersTab(),
          _buildPerformanceTab(),
          _buildAddRiderTab(),
          const AdminCouponManagementScreen(embedded: true),
          _buildOrdersTab(),
          _buildRiderApplicationsTab(),
          _buildSupportTab(),
        ],
      ),
    );
  }

  // ── Riders Tab ───────────────────────────────

  Widget _buildRidersTab() {
    return Column(
      children: [
        // Summary cards
        Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildSummaryCard(
                      icon: Icons.people_rounded,
                      label: 'Total',
                      value: '$_totalRiders',
                      color: const Color(0xFF1967D2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSummaryCard(
                      icon: Icons.check_circle_rounded,
                      label: 'Online',
                      value: '$_onlineRiders',
                      color: const Color(0xFF1E8E3E),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildSummaryCard(
                      icon: Icons.moped_rounded,
                      label: 'Delivering',
                      value: '$_onDeliveryRiders',
                      color: const Color(0xFFF9A825),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // View on Map button
              if (_onlineRiders > 0)
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: OutlinedButton.icon(
                    onPressed: () => _showOnlineRidersMap(),
                    icon: const Icon(Icons.map_rounded, size: 18),
                    label: const Text('View Online Riders on Map'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1967D2),
                      side: const BorderSide(color: Color(0xFF1967D2)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),

        // Riders list
        Expanded(child: _buildRidersList()),
      ],
    );
  }

  /// Show a full-screen dialog with a Baato map displaying all online riders.
  void _showOnlineRidersMap() {
    final onlineRiders = _riders.where((r) => r['is_online'] == true).toList();
    if (onlineRiders.isEmpty) return;

    // Build rider points from all online riders (skip riders without coords)
    final riderPoints = <RiderMapPoint>[];
    for (final rider in onlineRiders) {
      final lat = (rider['latitude'] as num?)?.toDouble();
      final lng = (rider['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;
      riderPoints.add(RiderMapPoint(
        latitude: lat,
        longitude: lng,
        label: rider['username'] as String? ?? 'Rider',
        type: RiderMapPointType.rider,
      ));
    }

    if (riderPoints.isEmpty) return;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.all(12),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.7,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: const BoxDecoration(
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFE5E7EB)),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.map_rounded, color: Color(0xFFBB0018), size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Online Riders',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: Color(0xFF1A1C1C),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: const Icon(Icons.close_rounded, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                // Rider count badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: const Color(0xFFF0F9FF),
                  width: double.infinity,
                  child: Text(
                    '${riderPoints.length} rider${riderPoints.length == 1 ? '' : 's'} currently online',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF1967D2),
                    ),
                  ),
                ),
                // Rider info strip
                SizedBox(
                  height: 48,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: riderPoints.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final point = riderPoints[index];
                      final onDelivery =
                          onlineRiders[index]['is_on_delivery'] == true;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: onDelivery
                              ? const Color(0xFFE8F0FE)
                              : const Color(0xFFE6F4EA),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.circle,
                              size: 8,
                              color: onDelivery
                                  ? const Color(0xFF1967D2)
                                  : const Color(0xFF1E8E3E),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              point.label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: onDelivery
                                    ? const Color(0xFF1967D2)
                                    : const Color(0xFF1E8E3E),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                // Map with all rider markers
                Expanded(
                  child: RiderMapView(
                    riderLocation: riderPoints.first,
                    riderLocations: riderPoints,
                    showEtaBar: false,
                    height: double.infinity,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSummaryCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF8E8E93),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRidersList() {
    if (_isLoadingRiders) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFFBB0018)),
            SizedBox(height: 16),
            Text('Loading riders...',
                style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14)),
          ],
        ),
      );
    }

    if (_ridersError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Color(0xFF8E8E93)),
              const SizedBox(height: 16),
              Text(_ridersError!, textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 14)),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _fetchRiders,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFBB0018),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_riders.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_off_outlined, size: 56, color: Color(0xFFD9D9D9)),
            const SizedBox(height: 12),
            const Text('No riders registered yet',
                style: TextStyle(color: Color(0xFF8E8E93), fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            const Text('Add riders from the "Add Rider" tab',
                style: TextStyle(color: Color(0xFFBFBFBF), fontSize: 13)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchRiders,
      color: const Color(0xFFBB0018),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: _riders.length,
        itemBuilder: (context, index) {
          final rider = _riders[index];
          return _buildRiderCard(rider);
        },
      ),
    );
  }

  Widget _buildRiderCard(Map<String, dynamic> rider) {
    final isOnline = rider['is_online'] == true;
    final isOnDelivery = rider['is_on_delivery'] == true;
    final totalDeliveries = (rider['total_deliveries'] as num?)?.toInt() ?? 0;
    final avgRating = (rider['average_rating'] as num?)?.toDouble() ?? 0.0;
    final totalRatings = (rider['total_ratings'] as num?)?.toInt() ?? 0;
    final lastActive = rider['last_active_at'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Status icon
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _statusColor(isOnline, isOnDelivery).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _statusIcon(isOnline, isOnDelivery),
              color: _statusColor(isOnline, isOnDelivery),
              size: 22,
            ),
          ),
          const SizedBox(width: 14),

          // Rider info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      rider['username'] as String? ?? 'Unknown',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: Color(0xFF1A1C1C),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _statusColor(isOnline, isOnDelivery).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _statusLabel(isOnline, isOnDelivery),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: _statusColor(isOnline, isOnDelivery),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (rider['phone'] != null && (rider['phone'] as String).isNotEmpty) ...[
                      Text(rider['phone'] as String,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93))),
                      const SizedBox(width: 12),
                    ],
                    Text('$totalDeliveries deliveries',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93))),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (avgRating > 0) ...[
                      const Icon(Icons.star_rounded, size: 14, color: Color(0xFFF9A825)),
                      const SizedBox(width: 2),
                      Text('$avgRating',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1A1C1C))),
                      if (totalRatings > 0) ...[
                        const SizedBox(width: 2),
                        Text('($totalRatings)',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93))),
                      ],
                      const SizedBox(width: 12),
                    ],
                    Icon(Icons.access_time_rounded, size: 12, color: const Color(0xFFBFBFBF)),
                    const SizedBox(width: 3),
                    Text(_timeAgo(lastActive),
                        style: const TextStyle(fontSize: 11, color: Color(0xFFBFBFBF))),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Performance Tab ──────────────────────────

  Widget _buildPerformanceTab() {
    if (_isLoadingPerformance) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFFBB0018)),
            SizedBox(height: 16),
            Text('Loading leaderboard...',
                style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14)),
          ],
        ),
      );
    }

    if (_leaderboard.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.emoji_events_outlined, size: 56, color: Color(0xFFD9D9D9)),
            const SizedBox(height: 12),
            const Text('No performance data yet',
                style: TextStyle(color: Color(0xFF8E8E93), fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            const Text('Data appears after riders complete deliveries',
                style: TextStyle(color: Color(0xFFBFBFBF), fontSize: 13)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchPerformance,
      color: const Color(0xFFBB0018),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.emoji_events_rounded, color: Color(0xFFF9A825), size: 22),
              const SizedBox(width: 8),
              const Text('Rider Leaderboard (Last 30 Days)',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1A1C1C))),
            ],
          ),
          const SizedBox(height: 16),

          ...List.generate(_leaderboard.length, (index) {
            final entry = _leaderboard[index];
            final deliveries = (entry['total_deliveries'] as num?)?.toInt() ?? 0;
            final onTimePct = (entry['on_time_percentage'] as num?)?.toInt() ?? 0;
            final onTimeDeliveries = (entry['on_time_deliveries'] as num?)?.toInt() ?? 0;
            final rating = (entry['average_rating'] as num?)?.toDouble() ?? 0.0;
            final totalRatings = (entry['total_ratings'] as num?)?.toInt() ?? 0;

            Color medalColor;
            IconData? medalIcon;
            if (index == 0) {
              medalColor = const Color(0xFFFFD700);
              medalIcon = Icons.emoji_events_rounded;
            } else if (index == 1) {
              medalColor = const Color(0xFFC0C0C0);
              medalIcon = Icons.emoji_events_rounded;
            } else if (index == 2) {
              medalColor = const Color(0xFFCD7F32);
              medalIcon = Icons.emoji_events_rounded;
            } else {
              medalColor = const Color(0xFFBFBFBF);
              medalIcon = null;
            }

            // Color the on-time percentage badge
            final bool hasDeliveryData = deliveries > 0;
            Color pctColor;
            if (!hasDeliveryData) {
              pctColor = const Color(0xFFBFBFBF);
            } else if (onTimePct >= 90) {
              pctColor = const Color(0xFF1E8E3E);
            } else if (onTimePct >= 75) {
              pctColor = const Color(0xFFF9A825);
            } else {
              pctColor = const Color(0xFFBB0018);
            }

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: index < 3 ? medalColor.withValues(alpha: 0.3) : const Color(0xFFE5E7EB),
                ),
              ),
              child: Row(
                children: [
                  // Rank
                  SizedBox(
                    width: 32,
                    child: medalIcon != null
                        ? Icon(medalIcon, color: medalColor, size: 24)
                        : Text(
                            '${index + 1}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF8E8E93),
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),

                  // Avatar
                  CircleAvatar(
                    backgroundColor: const Color(0xFFFFF1F0),
                    radius: 18,
                    child: Text(
                      (entry['username'] as String? ?? 'R').substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                        color: Color(0xFFBB0018),
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Name + Rating + On-time badge
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry['username'] as String? ?? 'Unknown',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                            color: Color(0xFF1A1C1C),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.star_rounded, size: 13, color: Color(0xFFF9A825)),
                            const SizedBox(width: 2),
                            Text(
                              rating > 0 ? '$rating' : 'No ratings',
                              style: TextStyle(
                                fontSize: 12,
                                color: rating > 0 ? const Color(0xFF1A1C1C) : const Color(0xFFBFBFBF),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (totalRatings > 0) ...[
                              const SizedBox(width: 2),
                              Text('($totalRatings)',
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E93))),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        // On-time percentage bar
                        Row(
                          children: [
                            Container(
                              width: 60,
                              height: 6,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE5E7EB),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: FractionallySizedBox(
                                alignment: Alignment.centerLeft,
                                widthFactor: hasDeliveryData ? onTimePct / 100.0 : 0,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: pctColor,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              Icons.access_time_rounded,
                              size: 12,
                              color: pctColor,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              hasDeliveryData ? '$onTimePct% on-time' : 'No data',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: hasDeliveryData ? pctColor : const Color(0xFFBFBFBF),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Deliveries count + on-time breakdown
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$deliveries',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: index < 3 ? medalColor : const Color(0xFF1A1C1C),
                        ),
                      ),
                      Text('deliveries',
                          style: TextStyle(fontSize: 11, color: Color(0xFF8E8E93))),
                      if (hasDeliveryData) ...[
                        const SizedBox(height: 2),
                        Text('$onTimeDeliveries on-time',
                            style: const TextStyle(fontSize: 10, color: Color(0xFFBFBFBF))),
                      ],
                    ],
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Add Rider Tab ────────────────────────────

  Widget _buildAddRiderTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFFBB0018), size: 24),
              const SizedBox(width: 10),
              const Text('Create New Delivery Rider',
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF1A1C1C))),
            ],
          ),
          const SizedBox(height: 4),
          const Text('Add a new delivery boy account to the platform',
              style: TextStyle(fontSize: 14, color: Color(0xFF8E8E93))),
          const SizedBox(height: 24),

          // Success message
          if (_createSuccess != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFE6F4EA),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF1E8E3E).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, color: Color(0xFF1E8E3E), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_createSuccess!,
                        style: const TextStyle(color: Color(0xFF1E8E3E), fontWeight: FontWeight.w500, fontSize: 13)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16, color: Color(0xFF1E8E3E)),
                    onPressed: () => setState(() => _createSuccess = null),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
          ],

          // Error message
          if (_createError != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F0),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFBB0018).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Color(0xFFBB0018), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_createError!,
                        style: const TextStyle(color: Color(0xFFBB0018), fontSize: 13)),
                  ),
                ],
              ),
            ),
          ],

          // Form
          _buildFormField('Username', _usernameCtrl, hint: 'e.g. ram_delivery', required: true),
          const SizedBox(height: 16),
          _buildFormField('Email (optional)', _emailCtrl,
              hint: 'e.g. ram@example.com', keyboardType: TextInputType.emailAddress),
          const SizedBox(height: 16),
          _buildFormField('Phone', _phoneCtrl,
              hint: 'e.g. 98XXXXXXXX',
              keyboardType: TextInputType.phone,
              required: true),
          const SizedBox(height: 16),
          _buildFormField('Password', _passwordCtrl,
              hint: 'Minimum 6 characters', obscureText: true, required: true),

          const SizedBox(height: 24),

          // Submit button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isCreating ? null : _createRider,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFBB0018),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFEFEDED),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: _isCreating
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white),
                    )
                  : const Text('Create Rider',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),

          const SizedBox(height: 32),

          // Info card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFFE082)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, size: 16, color: Color(0xFFF9A825)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'New riders will receive their login credentials via the provided phone number. '
                    'They can log in and start accepting deliveries immediately.',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF795548), height: 1.4),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormField(
    String label,
    TextEditingController controller, {
    String? hint,
    bool required = false,
    bool obscureText = false,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF262626))),
            if (required)
              const Text(' *',
                  style: TextStyle(color: Color(0xFFBB0018), fontSize: 14)),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: TextField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: keyboardType,
            style: const TextStyle(fontSize: 15, color: Color(0xFF1A1C1C)),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Color(0xFFBFBFBF), fontSize: 14),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }

  // ── Orders Tab (Dispute Resolution) ──────────

  Widget _buildOrdersTab() {
    if (_isLoadingOrders) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFFBB0018)),
            SizedBox(height: 16),
            Text('Loading orders...',
                style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14)),
          ],
        ),
      );
    }

    if (_deliveredOrders.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.receipt_long_rounded, size: 56, color: Color(0xFFD9D9D9)),
            const SizedBox(height: 12),
            const Text('No completed deliveries yet',
                style: TextStyle(color: Color(0xFF8E8E93), fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            const Text('Delivered orders with photos will appear here',
                style: TextStyle(color: Color(0xFFBFBFBF), fontSize: 13)),
          ],
        ),
      );
    }

    // Summary stats
    final withPhoto = _deliveredOrders.where((o) => o.deliveryPhotoUrl != null && o.deliveryPhotoUrl!.isNotEmpty).length;
    final withoutPhoto = _deliveredOrders.length - withPhoto;

    return Column(
      children: [
        // Summary + filter
        Container(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildSummaryCard(
                      icon: Icons.check_circle,
                      label: 'Delivered',
                      value: '${_deliveredOrders.length}',
                      color: const Color(0xFF1E8E3E),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildSummaryCard(
                      icon: Icons.camera_alt,
                      label: 'With Photo',
                      value: '$withPhoto',
                      color: const Color(0xFF1967D2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildSummaryCard(
                      icon: Icons.no_photography,
                      label: 'No Photo',
                      value: '$withoutPhoto',
                      color: const Color(0xFFF9A825),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Filter chips
              Row(
                children: [
                  _buildFilterChip('All', _ordersFilter == null, () {
                    setState(() => _ordersFilter = null);
                  }),
                  const SizedBox(width: 8),
                  _buildFilterChip('Has Photo', _ordersFilter == 'with_photo', () {
                    setState(() => _ordersFilter = 'with_photo');
                  }),
                  const SizedBox(width: 8),
                  _buildFilterChip('No Photo', _ordersFilter == 'without_photo', () {
                    setState(() => _ordersFilter = 'without_photo');
                  }),
                ],
              ),
            ],
          ),
        ),

        // Orders list
        Expanded(
          child: RefreshIndicator(
            onRefresh: _fetchDeliveredOrders,
            color: const Color(0xFFBB0018),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: _filteredOrders.length,
              itemBuilder: (context, index) => _buildDeliveredOrderCard(_filteredOrders[index]),
            ),
          ),
        ),
      ],
    );
  }

  List<Order> get _filteredOrders {
    if (_ordersFilter == 'with_photo') {
      return _deliveredOrders.where((o) => o.deliveryPhotoUrl != null && o.deliveryPhotoUrl!.isNotEmpty).toList();
    }
    if (_ordersFilter == 'without_photo') {
      return _deliveredOrders.where((o) => o.deliveryPhotoUrl == null || o.deliveryPhotoUrl!.isEmpty).toList();
    }
    return _deliveredOrders;
  }

  Widget _buildFilterChip(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFBB0018) : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isSelected ? const Color(0xFFBB0018) : const Color(0xFFE5E7EB),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : const Color(0xFF8E8E93),
          ),
        ),
      ),
    );
  }

  Widget _buildDeliveredOrderCard(Order order) {
    final hasPhoto = order.deliveryPhotoUrl != null && order.deliveryPhotoUrl!.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Photo status indicator
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: hasPhoto
                      ? const Color(0xFFE6F4EA)
                      : const Color(0xFFFFF1F0),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  hasPhoto ? Icons.camera_alt_rounded : Icons.no_photography_outlined,
                  color: hasPhoto ? const Color(0xFF1E8E3E) : const Color(0xFFF5222D),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Order',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: Color(0xFF1A1C1C),
                      ),
                    ),
                    if (order.restaurantName.isNotEmpty)
                      Text(
                        order.restaurantName,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF8E8E93),
                        ),
                      ),
                  ],
                ),
              ),
              // Photo badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: hasPhoto
                      ? const Color(0xFFE6F4EA)
                      : const Color(0xFFFFF1F0),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  hasPhoto ? 'Has Photo' : 'No Photo',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: hasPhoto ? const Color(0xFF1E8E3E) : const Color(0xFFF5222D),
                  ),
                ),
              ),
            ],
          ),

          // Delivery photo thumbnail (if available)
          if (hasPhoto) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => _showDeliveryPhotoFullScreen(order.deliveryPhotoUrl!),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: double.infinity,
                  height: 160,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        order.deliveryPhotoUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          color: const Color(0xFFF5F5F5),
                          child: const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.broken_image_outlined,
                                    size: 28, color: Color(0xFFBFBFBF)),
                                SizedBox(height: 4),
                                Text('Photo unavailable',
                                    style: TextStyle(
                                        fontSize: 12, color: Color(0xFFBFBFBF))),
                              ],
                            ),
                          ),
                        ),
                        loadingBuilder: (_, child, progress) {
                          if (progress == null) return child;
                          return Container(
                            color: const Color(0xFFF5F5F5),
                            child: const Center(
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Color(0xFFBB0018)),
                            ),
                          );
                        },
                      ),
                      // Tap overlay
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.center,
                              colors: [
                                Colors.black.withValues(alpha: 0.5),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.touch_app, size: 14, color: Colors.white),
                              SizedBox(width: 4),
                              Text('Tap to expand',
                                  style: TextStyle(
                                      fontSize: 11, color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: 8),

          // Order info row
          Row(
            children: [
              const Icon(Icons.person_outline, size: 14, color: Color(0xFF8E8E93)),
              const SizedBox(width: 4),
              Text(
                order.deliveryBoyName ?? 'Unknown rider',
                style: const TextStyle(fontSize: 12, color: Color(0xFF5C5C5C)),
              ),
              const Spacer(),
              Text(
                'Rs. ${order.total.toStringAsFixed(0)}',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1C1C)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Rider Applications Tab ──────────────────

  Widget _buildRiderApplicationsTab() {
    if (_isLoadingApplications) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFFBB0018)),
            SizedBox(height: 16),
            Text('Loading applications...',
                style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14)),
          ],
        ),
      );
    }

    if (_applicationsError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Color(0xFF8E8E93)),
              const SizedBox(height: 16),
              Text(_applicationsError!, textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 14)),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _fetchRiderApplications,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFBB0018),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_riderApplications.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_add_disabled_outlined, size: 56, color: Color(0xFFD9D9D9)),
            const SizedBox(height: 12),
            const Text('No pending applications',
                style: TextStyle(color: Color(0xFF8E8E93), fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            const Text('New delivery partner applications will appear here',
                style: TextStyle(color: Color(0xFFBFBFBF), fontSize: 13)),
          ],
        ),
      );
    }

    // Applications count header
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.person_add_alt_1_rounded, color: Color(0xFFBB0018), size: 22),
              const SizedBox(width: 10),
              Text(
                '${_riderApplications.length} Pending Application${_riderApplications.length == 1 ? '' : 's'}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1C1C),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _fetchRiderApplications,
            color: const Color(0xFFBB0018),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              itemCount: _riderApplications.length,
              itemBuilder: (context, index) {
                final app = _riderApplications[index];
                return _buildRiderApplicationCard(app);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRiderApplicationCard(Map<String, dynamic> app) {
    final fullName = app['full_name'] as String? ?? 'Unknown';
    final email = app['email'] as String? ?? '';
    final phone = app['phone'] as String? ?? '';
    final vehicleType = app['vehicle_type'] as String? ?? '';
    final vehicleNumber = app['vehicle_number'] as String? ?? '';
    final licenseUrl = app['license_url'] as String? ?? '';
    final profileImageUrl = app['profile_image_url'] as String?;
    final createdAt = app['created_at'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row with profile + name
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar
              CircleAvatar(
                radius: 24,
                backgroundColor: const Color(0xFFFFF1F0),
                foregroundImage: profileImageUrl != null && profileImageUrl.isNotEmpty
                    ? NetworkImage(profileImageUrl)
                    : null,
                child: profileImageUrl == null || profileImageUrl.isEmpty
                    ? Text(
                        fullName.isNotEmpty ? fullName[0].toUpperCase() : '?',
                        style: const TextStyle(
                          color: Color(0xFFBB0018),
                          fontWeight: FontWeight.w700,
                          fontSize: 20,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              // Name + contact
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fullName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1C1C),
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (email.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Row(
                          children: [
                            const Icon(Icons.email_outlined, size: 13, color: Color(0xFF8E8E93)),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                email,
                                style: const TextStyle(fontSize: 13, color: Color(0xFF5C5C5C)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (phone.isNotEmpty)
                      Row(
                        children: [
                          const Icon(Icons.phone_outlined, size: 13, color: Color(0xFF8E8E93)),
                          const SizedBox(width: 4),
                          Text(
                            phone,
                            style: const TextStyle(fontSize: 13, color: Color(0xFF5C5C5C)),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              // Time ago badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _timeAgo(createdAt),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF8E8E93),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),
          const Divider(height: 1, color: Color(0xFFF0F0F0)),
          const SizedBox(height: 14),

          // Vehicle info
          Row(
            children: [
              Icon(
                vehicleType.contains('Bicycle')
                    ? Icons.directions_bike
                    : vehicleType.contains('Motor') || vehicleType.contains('Scooter')
                        ? Icons.motorcycle
                        : vehicleType.contains('Car')
                            ? Icons.directions_car
                            : Icons.directions_walk,
                size: 16,
                color: const Color(0xFF595959),
              ),
              const SizedBox(width: 8),
              Text(
                vehicleType,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1A1C1C)),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('|', style: TextStyle(color: Color(0xFFE5E7EB))),
              ),
              Text(
                vehicleNumber,
                style: const TextStyle(fontSize: 13, color: Color(0xFF5C5C5C)),
              ),
            ],
          ),

          // License photo (if available)
          if (licenseUrl.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.badge_outlined, size: 14, color: Color(0xFF8E8E93)),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => _showLicensePhoto(licenseUrl),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F9FF),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.image_outlined, size: 14, color: Color(0xFF1967D2)),
                        SizedBox(width: 4),
                        Text(
                          "View License",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1967D2),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 14),

          // Approve / Reject buttons
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: () => _rejectRiderApplication(app),
                    icon: const Icon(Icons.close_rounded, size: 18),
                    label: const Text('Reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFF5222D),
                      side: const BorderSide(color: Color(0xFFF5222D)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: () => _approveRiderApplication(app),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Approve'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1E8E3E),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Show license photo in a dialog.
  void _showLicensePhoto(String licenseUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                licenseUrl,
                width: double.infinity,
                height: MediaQuery.of(context).size.height * 0.5,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Center(
                    child: Text('Failed to load image',
                        style: TextStyle(color: Colors.white)),
                  ),
                ),
                loadingBuilder: (_, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    height: MediaQuery.of(context).size.height * 0.5,
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Center(
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black38,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Support Tab (Admin agent replies) ───────

  Widget _buildSupportTab() {
    final openCount = _supportConversations.where((c) => c['status'] == 'OPEN').length;

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.headset_mic_rounded, color: Color(0xFFBB0018), size: 22),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Support Conversations',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1A1C1C))),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F0),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text('$openCount',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFBB0018))),
              ),
            ],
          ),
        ),

        Expanded(child: _buildSupportList()),
      ],
    );
  }

  Widget _buildSupportList() {
    if (_isLoadingSupport) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFFBB0018)),
            SizedBox(height: 16),
            Text('Loading conversations...',
                style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14)),
          ],
        ),
      );
    }

    if (_supportConversations.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.headset_mic_rounded, size: 56, color: Color(0xFFD9D9D9)),
            const SizedBox(height: 12),
            const Text('No support conversations yet',
                style: TextStyle(color: Color(0xFF8E8E93), fontSize: 16, fontWeight: FontWeight.w500)),
          ],
        ),
      );
    }

    final openFirst = List<Map<String, dynamic>>.from(_supportConversations)
      ..sort((a, b) {
        final aOpen = a['status'] == 'OPEN' ? 0 : 1;
        final bOpen = b['status'] == 'OPEN' ? 0 : 1;
        if (aOpen != bOpen) return aOpen.compareTo(bOpen);
        return (b['updated_at'] as String? ?? '').compareTo(a['updated_at'] as String? ?? '');
      });

    return RefreshIndicator(
      onRefresh: _fetchSupportConversations,
      color: const Color(0xFFBB0018),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: openFirst.length,
        itemBuilder: (context, index) => _buildSupportCard(openFirst[index]),
      ),
    );
  }

  Widget _buildSupportCard(Map<String, dynamic> conv) {
    final status = conv['status'] as String? ?? 'OPEN';
    final subject = conv['subject'] as String? ?? '';
    final lastMsg = conv['last_message'] as Map<String, dynamic>?;
    final msgCount = (conv['message_count'] as num?)?.toInt() ?? 0;
    final userInfo = conv['user'] as Map<String, dynamic>?;
    final userName = userInfo?['username'] as String? ?? 'Unknown';
    final isOpen = status == 'OPEN';

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => SupportChatScreen(
              conversationId: conv['id'] as String? ?? '',
              subject: subject,
              isAdmin: true,
            ),
          ),
        ).then((_) => _fetchSupportConversations());
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: isOpen
              ? Border.all(color: const Color(0xFFBB0018).withValues(alpha: 0.2))
              : null,
          boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8, offset: const Offset(0, 3),
          )],
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: isOpen ? const Color(0xFFFFF1F0) : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isOpen ? Icons.chat_rounded : Icons.check_circle_outlined,
                color: isOpen ? const Color(0xFFBB0018) : const Color(0xFF8E8E93),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(subject,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600,
                                color: Color(0xFF1A1C1C)),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isOpen ? const Color(0xFFFFF1F0) : const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(isOpen ? 'Open' : 'Closed',
                            style: TextStyle(
                                fontSize: 10, fontWeight: FontWeight.w600,
                                color: isOpen ? const Color(0xFFBB0018) : const Color(0xFF8E8E93))),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.person_outline, size: 13, color: const Color(0xFF8E8E93)),
                      const SizedBox(width: 4),
                      Text(userName,
                          style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93))),
                      const SizedBox(width: 12),
                      Icon(Icons.chat_bubble_outline, size: 12, color: const Color(0xFFBFBFBF)),
                      const SizedBox(width: 3),
                      Text('$msgCount msgs',
                          style: const TextStyle(fontSize: 11, color: Color(0xFFBFBFBF))),
                    ],
                  ),
                  if (lastMsg != null) ...[
                    const SizedBox(height: 4),
                    Text(lastMsg['message'] as String? ?? '',
                        style: const TextStyle(fontSize: 12, color: Color(0xFF5C5C5C)),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Color(0xFFBFBFBF)),
          ],
        ),
      ),
    );
  }

  /// Show a delivery photo in a full-screen dialog.
  void _showDeliveryPhotoFullScreen(String photoUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                photoUrl,
                width: double.infinity,
                height: MediaQuery.of(context).size.height * 0.5,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Center(
                    child: Text('Failed to load photo',
                        style: TextStyle(color: Colors.white)),
                  ),
                ),
                loadingBuilder: (_, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    height: MediaQuery.of(context).size.height * 0.5,
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Center(
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black38,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
