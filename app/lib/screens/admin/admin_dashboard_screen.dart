import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/api_service.dart';
import '../../widgets/rider_map_view.dart';
import '../../injection_container.dart' as di;
import '../../providers/auth_provider.dart';

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchRiders();
    _fetchPerformance();
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
          tabs: const [
            Tab(text: 'Riders'),
            Tab(text: 'Performance'),
            Tab(text: 'Add Rider'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildRidersTab(),
          _buildPerformanceTab(),
          _buildAddRiderTab(),
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
}
