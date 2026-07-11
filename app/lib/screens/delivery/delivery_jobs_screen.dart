import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import '../../models/order.dart';
import '../../core/services/api_service.dart';
import '../../core/services/storage_service.dart';
import '../../core/services/supabase_client_service.dart';
import '../../core/services/rider_location_service.dart';
import '../../widgets/rider_map_view.dart';
import '../../injection_container.dart' as di;
import '../../providers/auth_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/rider_notes_provider.dart';
import '../notifications_screen.dart';
import '../full_screen_map_screen.dart';


class DeliveryJobsScreen extends StatefulWidget {
  const DeliveryJobsScreen({super.key});

  @override
  State<DeliveryJobsScreen> createState() => _DeliveryJobsScreenState();
}

class _DeliveryJobsScreenState extends State<DeliveryJobsScreen>
    with TickerProviderStateMixin {
  List<Order> _jobs = [];
  bool _isLoading = true;
  String? _error;

  // Tab state
  int _selectedTab = 0; // 0 = Jobs, 1 = Earnings
  late final TabController _tabController;

  // Earnings tab state
  Map<String, dynamic> _riderStats = {};
  bool _isLoadingStats = false;

  // Job actions
  bool _isAccepting = false;
  bool _isDelivering = false;
  String? _isDecliningOrderId;  // tracks which order's decline is in progress

  // Track which order card has its map expanded
  String? _expandedOrderId;

  // Online/offline tracking
  bool _isOnline = false;
  bool _isTracking = false;
  sb.RealtimeChannel? _orderChannel;

  // Rider note controllers per order
  final Map<String, TextEditingController> _riderNoteCtrls = {};

  String? get _token => context.read<AuthProvider>().token;
  String? get _userId => SupabaseClientService.client.auth.currentUser?.id;
  RiderLocationService get _locationService => di.sl<RiderLocationService>();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _selectedTab = _tabController.index);
        if (_selectedTab == 1) _fetchRiderStats();
      }
    });
    // Set up Realtime subscription BEFORE the initial fetch
    // so no events are missed between the fetch and subscription start.
    _setupRealtimeSubscription();
    _fetchJobs();
    _initRiderTracking();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _unsubscribeFromOrders();
    _locationService.stopTracking();
    for (final ctrl in _riderNoteCtrls.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  // ── GPS Tracking ─────────────────────────────

  Future<void> _initRiderTracking() async {
    final token = _token;
    if (token == null) return;

    _locationService.setAuthToken(token);

    final userId = SupabaseClientService.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final data = await SupabaseClientService.client
          .from('users')
          .select('role')
          .eq('id', userId)
          .maybeSingle();
      final role = data?['role'] as String? ?? '';
      if (role != 'DELIVERY_BOY') return;
    } catch (_) {
      return;
    }

    final hasPermission = await _locationService.requestLocationPermission();
    if (hasPermission && mounted) {
      await _locationService.startTracking();
      setState(() {
        _isOnline = true;
        _isTracking = true;
      });
    }
  }

  Future<void> _toggleOnline() async {
    if (_isOnline) {
      await _locationService.stopTracking();
      setState(() {
        _isOnline = false;
        _isTracking = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You are now offline'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      final hasPermission = await _locationService.requestLocationPermission();
      if (!hasPermission) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permission is required to go online'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      _locationService.setAuthToken(_token);
      await _locationService.startTracking();
      if (mounted) {
        setState(() {
          _isOnline = true;
          _isTracking = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You are now online — sharing location'),
            backgroundColor: Color(0xFF52C41A),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ── Realtime Subscriptions ────────────────────

  /// Set up the Realtime channel immediately (before the initial fetch)
  /// to ensure no events are missed.
  void _setupRealtimeSubscription() {
    final userId = _userId;
    if (userId != null) _subscribeToOrders(userId);
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
          _silentRefreshJobs();
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
          _silentRefreshJobs();
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

  // ── Data Fetching ────────────────────────────

  /// Lightweight refresh triggered by Realtime events.
  /// Fetches jobs in the background WITHOUT showing a loading spinner
  /// or error state, so the UI doesn't flicker during live updates.
  Future<void> _silentRefreshJobs() async {
    final token = _token;
    if (token == null) return;

    // Ensure the Realtime subscription is active (idempotent —
    // _subscribeToOrders calls _unsubscribeFromOrders first).
    // Handles the edge case where auth wasn't ready in initState.
    _setupRealtimeSubscription();

    try {
      final api = di.sl<ApiService>();
      final rawOrders = await api.getMyDeliveryJobs(token: token);
      if (!mounted) return;

      // Dispose old rider note controllers since order list may have changed
      for (final ctrl in _riderNoteCtrls.values) {
        ctrl.dispose();
      }
      _riderNoteCtrls.clear();

      setState(() {
        _jobs = rawOrders.map((o) => Order.fromJson(o)).toList();
        _error = null;
      });
    } catch (_) {
      // Silently ignore — existing data stays as-is
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
      for (final ctrl in _riderNoteCtrls.values) {
        ctrl.dispose();
      }
      _riderNoteCtrls.clear();
      setState(() {
        _jobs = rawOrders.map((o) => Order.fromJson(o)).toList();
        _isLoading = false;
      });
      // Ensure Realtime subscription is active (idempotent).
      // This retries subscription setup on every pull-to-refresh,
      // handling the edge case where auth wasn't ready in initState.
      _setupRealtimeSubscription();
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

  Future<void> _fetchRiderStats() async {
    final token = _token;
    if (token == null) return;

    setState(() => _isLoadingStats = true);
    try {
      final api = di.sl<ApiService>();
      final stats = await api.getRiderStats(token: token);
      if (mounted) {
        setState(() {
          _riderStats = stats;
          _isLoadingStats = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingStats = false);
    }
  }

  // ── Job Actions ──────────────────────────────

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
            backgroundColor: Color(0xFF52C41A),
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

  /// Mark an order as delivered.
  /// Captures GPS snapshot + optionally a delivery photo as proof.
  Future<void> _markAsDelivered(Order order) async {
    final token = _token;
    if (token == null) return;

    // Step 1: Ask if rider wants to take a delivery photo
    final takePhoto = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.camera_alt_rounded, color: Color(0xFFF5222D), size: 24),
            SizedBox(width: 10),
            Expanded(
              child: Text('Delivery Photo',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        content: const Text(
          'Take a photo of the delivered order as proof of delivery.\n\n'
          'This helps resolve disputes and provides a complete delivery record.',
          style: TextStyle(fontSize: 14, color: Color(0xFF595959), height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Skip Photo',
                style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF8E8E93))),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.camera_alt, size: 18),
            label: const Text('Take Photo'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF5222D),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
          ),
        ],
      ),
    );

    if (takePhoto == null) return; // Cancelled

    setState(() => _isDelivering = true);

    String? deliveryPhotoUrl;

    // Step 2: If rider chose to take a photo, open camera and upload
    if (takePhoto) {
      try {
        final picker = ImagePicker();
        final pickedFile = await picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 75,
        );

        if (pickedFile != null) {
          // Show uploading snackbar
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Row(
                  children: [
                    SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    ),
                    SizedBox(width: 12),
                    Text('Uploading delivery photo...'),
                  ],
                ),
                duration: Duration(seconds: 30),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }

          // Upload to delivery-photos bucket
          final storage = di.sl<StorageService>();
          deliveryPhotoUrl = await storage.uploadDeliveryPhoto(
            filePath: pickedFile.path,
            token: token,
          );

          if (mounted) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          }
        }
      } catch (_) {
        // Photo upload failed — proceed without photo
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
        }
      }
    }

    // Step 3: Confirm delivery
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirm Delivery',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Mark this order as delivered?'),
            if (deliveryPhotoUrl != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF6FFED),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, size: 16, color: Color(0xFF52C41A)),
                    SizedBox(width: 6),
                    Text('Photo attached',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600,
                            color: Color(0xFF52C41A))),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF52C41A)),
            child: const Text('Delivered'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      setState(() => _isDelivering = false);
      return;
    }

    try {
      // Capture current GPS position as proof
      double? lat;
      double? lng;
      try {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 5),
        );
        lat = pos.latitude;
        lng = pos.longitude;
      } catch (_) {
        // GPS unavailable — proceed without snapshot
      }

      final api = di.sl<ApiService>();
      await api.markOrderAsDelivered(
        orderId: order.id,
        token: token,
        deliveryPhotoUrl: deliveryPhotoUrl,
        deliveryLat: lat,
        deliveryLng: lng,
      );

      // Release rider locally
      _locationService.stopTracking().then((_) => _locationService.startTracking());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Order delivered successfully!'),
            backgroundColor: Color(0xFF52C41A),
            behavior: SnackBarBehavior.floating,
          ),
        );
        _fetchJobs();
        _fetchRiderStats();
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
      if (mounted) setState(() => _isDelivering = false);
    }
  }

  /// Show "I'm Here" feedback.
  Future<void> _imHere(Order order) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('📍 Marked as arrived — customer notified'),
        backgroundColor: Color(0xFFFF5745),
        behavior: SnackBarBehavior.floating,
      ),
    );
    // In a future phase, this would send an FCM push to the customer
  }

  /// Decline an assigned job — clears assignment and notifies the owner.
  Future<void> _declineJob(Order order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Decline Delivery?'),
        content: Text(
          'Decline this delivery?\n\n'
          'The restaurant owner will be notified and can reassign another rider.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFF5222D)),
            child: const Text('Decline'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final token = _token;
    if (token == null) return;

    setState(() => _isDecliningOrderId = order.id);
    try {
      final api = di.sl<ApiService>();
      await api.declineOrder(orderId: order.id, token: token);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order declined. Owner has been notified.'),
            backgroundColor: Color(0xFFF5222D),
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
      if (mounted) setState(() => _isDecliningOrderId = null);
    }
  }

  /// Navigate to the dropoff location using the device's maps app.
  Future<void> _navigateToDropoff(Order order) async {
    final dropoff = order.deliveryAddress;
    if (dropoff?.latitude == null || dropoff?.longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No dropoff location available'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final lat = dropoff!.latitude!;
    final lng = dropoff.longitude!;
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open maps'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ── Call Customer via Phone App ──────────────

  Future<void> _callCustomer(Order order) async {
    final phone = order.customerPhone;
    if (phone == null || phone.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Customer phone number not available'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open phone app'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ── Formatting ───────────────────────────────

  String _formatCurrency(double amount) {
    return 'Rs. ${amount.toStringAsFixed(0)}';
  }

  String _timeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  // ── Build ────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      appBar: AppBar(
        title: const Text(
          'Delivery',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1A1A),
        elevation: 0.5,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFF5222D),
          labelColor: const Color(0xFFF5222D),
          unselectedLabelColor: const Color(0xFF8E8E93),
          labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          tabs: [
            Tab(text: 'Jobs (${_jobs.length})'),
            const Tab(text: 'Earnings'),
          ],
        ),
        actions: [
          // Bell icon for notifications
          Consumer<NotificationProvider>(
            builder: (context, notifProvider, _) => Padding(
              padding: const EdgeInsets.only(right: 4),
              child: IconButton(
                icon: Stack(
                  children: [
                    const Icon(Icons.notifications_outlined, size: 22),
                    if (notifProvider.hasUnread)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: const BoxDecoration(
                            color: Color(0xFFF5222D),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${notifProvider.unreadCount}',
                              style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const NotificationsScreen()),
                  );
                },
                tooltip: 'Notifications',
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: _isTracking ? _toggleOnline : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _isOnline
                      ? const Color(0xFFF6FFED)
                      : const Color(0xFFFFF1F0),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: _isOnline
                        ? const Color(0xFF52C41A)
                        : const Color(0xFFF5222D),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7, height: 7,
                      decoration: BoxDecoration(
                        color: _isOnline
                            ? const Color(0xFF52C41A)
                            : const Color(0xFFF5222D),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _isOnline ? 'Online' : 'Offline',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _isOnline
                            ? const Color(0xFF52C41A)
                            : const Color(0xFFF5222D),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildJobsTab(),
          _buildEarningsTab(),
        ],
      ),
    );
  }

  // ── Jobs Tab ─────────────────────────────────

  Widget _buildJobsTab() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFFF5222D)),
            SizedBox(height: 16),
            Text('Loading jobs...',
                style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14)),
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
              Text(_error!, textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 14)),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _fetchJobs,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF5222D),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
        color: const Color(0xFFF5222D),
        child: ListView(
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.5,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.moped_rounded, size: 56, color: Color(0xFFBFBFBF)),
                    SizedBox(height: 12),
                    Text('No jobs assigned',
                        style: TextStyle(
                            color: Color(0xFF8E8E93),
                            fontSize: 16,
                            fontWeight: FontWeight.w500)),
                    SizedBox(height: 4),
                    Text('New delivery jobs will appear here',
                        style: TextStyle(color: Color(0xFFBFBFBF), fontSize: 13)),
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
      color: const Color(0xFFF5222D),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _jobs.length,
        itemBuilder: (context, index) => _buildJobCard(_jobs[index]),
      ),
    );
  }

  // ── Job Card ─────────────────────────────────

  Widget _buildJobCard(Order order) {
    final dropoff = order.deliveryAddress;
    final canNavigate = dropoff?.latitude != null && dropoff?.longitude != null;
    final isActiveForActions = order.status == OrderStatus.pickedUp ||
        order.status == OrderStatus.outForDelivery;
    final isMapExpanded = _expandedOrderId == order.id;

    final bannerUrl = order.items.firstOrNull?.imageUrl;
    final hasBannerImage = bannerUrl != null && bannerUrl.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
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
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Full-width banner image (first item's image) ──
          if (hasBannerImage)
            SizedBox(
              width: double.infinity,
              height: 150,
              child: Image.network(
                bannerUrl,
                width: double.infinity,
                height: 150,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),

          // ── Content section ──
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ──
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.receipt_long_rounded,
                            size: 18, color: Color(0xFFF5222D)),
                        const SizedBox(width: 8),
                        const Text(
                          'Delivery',
                          style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        _buildStatusBadge(order.status),
                        const SizedBox(width: 8),
                        Text(_timeAgo(order.createdAt),
                            style: const TextStyle(
                                color: Color(0xFF595959), fontSize: 12)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // ── Restaurant name ──
                if (order.restaurantName.isNotEmpty) ...[
                  Row(
                    children: [
                      const Icon(Icons.store, color: Color(0xFF8E8E93), size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          order.restaurantName,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600,
                              color: Color(0xFF1A1A1A)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],

                // ── Items ──
                ...order.items.take(2).map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('${item.quantity}x ${item.name}',
                          style: const TextStyle(
                              fontSize: 14, color: Color(0xFF595959))),
                    )),
                if (order.items.length > 2)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('+${order.items.length - 2} more items',
                        style: const TextStyle(
                            color: Color(0xFFBFBFBF), fontSize: 12)),
                  ),

                const SizedBox(height: 12),

                // ── Dropoff address ──
                if (dropoff?.fullAddress != null) ...[
                  Row(
                    children: [
                      const Icon(Icons.location_on, color: Color(0xFFF5222D), size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          dropoff!.fullAddress!,
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFF595959)),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],

                // ── Total ──
                Row(
                  children: [
                    const Icon(Icons.receipt_outlined, color: Color(0xFF8E8E93), size: 18),
                    const SizedBox(width: 6),
                    Text('Total: ${_formatCurrency(order.total)}',
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600,
                            color: Color(0xFF1A1A1A))),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── Map toggle button ──
          // ── Map section (collapsible) ──
          if (canNavigate) ...[
            SizedBox(
              width: double.infinity,
              height: 36,
              child: TextButton.icon(
                onPressed: () {
                  setState(() {
                    _expandedOrderId = isMapExpanded ? null : order.id;
                  });
                },
                icon: Icon(
                  isMapExpanded ? Icons.expand_less : Icons.map_rounded,
                  size: 18,
                ),
                label: Text(isMapExpanded ? 'Hide Map' : 'Show Map'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFFF5745),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            if (isMapExpanded) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),                  child: RiderMapView(
                    riderLocation: RiderMapPoint(
                      latitude: dropoff!.latitude!,
                      longitude: dropoff.longitude!,
                      label: 'Dropoff',
                      type: RiderMapPointType.rider,
                    ),
                    dropoffLocation: RiderMapPoint(
                      latitude: dropoff.latitude!,
                      longitude: dropoff.longitude!,
                      label: dropoff.fullAddress ?? 'Customer',
                      type: RiderMapPointType.dropoff,
                    ),
                    showRoute: true,
                    showEtaBar: false,
                    height: 180,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FullScreenMapScreen(
                            riderLocation: RiderMapPoint(
                              latitude: dropoff.latitude!,
                              longitude: dropoff.longitude!,
                              label: 'You',
                              type: RiderMapPointType.rider,
                            ),
                            riderId: _userId ?? '',
                            dropoffLocation: RiderMapPoint(
                              latitude: dropoff.latitude!,
                              longitude: dropoff.longitude!,
                              label: dropoff.fullAddress ?? 'Customer',
                              type: RiderMapPointType.dropoff,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
            ],
            const SizedBox(height: 4),
          ],

          // ── Customer Note ──
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
                        const Text('Customer Note',
                            style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w600,
                                color: Color(0xFF795548))),
                        const SizedBox(height: 2),
                        Text(order.deliveryNotes!,
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF795548))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── Rider Note Input ──
          _buildRiderNoteInput(order),
          const SizedBox(height: 12),

          // ── Action Buttons ──
          if (order.status == OrderStatus.outForDelivery) ...[
            // Pending pickup: Accept + Navigate
            Row(
              children: [
                if (canNavigate)
                  Expanded(
                    child: _buildActionButton(
                      label: 'Navigate',
                      icon: Icons.navigation,
                      color: const Color(0xFFFF5745),
                      onPressed: () => _navigateToDropoff(order),
                    ),
                  ),
                if (canNavigate) const SizedBox(width: 8),
                Expanded(
                  flex: canNavigate ? 2 : 1,
                  child: _buildActionButton(
                    label: 'Accept (Pick Up)',
                    icon: Icons.assignment_turned_in,
                    color: const Color(0xFFF5222D),
                    isLoading: _isAccepting,
                    onPressed: () => _acceptJob(order),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 40,
              child: OutlinedButton.icon(
                onPressed: _isDecliningOrderId == order.id
                    ? null
                    : () => _declineJob(order),
                icon: _isDecliningOrderId == order.id
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFFF5222D)))
                    : const Icon(Icons.close_rounded, size: 18),
                label: Text(
                  _isDecliningOrderId == order.id
                      ? 'Declining...'
                      : 'Decline Delivery',
                  style: const TextStyle(fontSize: 13),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFF5222D),
                  side: const BorderSide(color: Color(0xFFF5222D)),
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],

          if (order.status == OrderStatus.pickedUp) ...[
            // Being delivered: Navigate + I'm Here + Deliver
            Column(
              children: [
                Row(
                  children: [
                    if (canNavigate)
                      Expanded(
                        child: _buildActionButton(
                          label: 'Navigate',
                          icon: Icons.navigation,
                          color: const Color(0xFFFF5745),
                          onPressed: () => _navigateToDropoff(order),
                        ),
                      ),
                    if (canNavigate) const SizedBox(width: 8),
                    Expanded(
                      child: _buildActionButton(
                        label: "I'm Here",
                        icon: Icons.location_on,
                        color: const Color(0xFFF9A825),
                        onPressed: () => _imHere(order),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _isDelivering
                        ? null
                        : () => _markAsDelivered(order),
                    icon: _isDelivering
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_circle, size: 20),
                    label: Text(
                      _isDelivering
                          ? 'Confirming...'
                          : 'Mark as Delivered',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF52C41A),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFFE0E0E0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ],

          // ── Call Customer (always available for active orders) ──
          if (order.userId.isNotEmpty && isActiveForActions) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 40,
              child: OutlinedButton.icon(
                onPressed: () => _callCustomer(order),
                icon: const Icon(Icons.phone_rounded, size: 16),
                label: const Text('Call Customer',
                    style: TextStyle(fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFF5745),
                  side: const BorderSide(color: Color(0xFFFF5745)),
                  backgroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    VoidCallback? onPressed,
    bool isLoading = false,
  }) {
    return SizedBox(
      height: 44,
      child: ElevatedButton.icon(
        onPressed: isLoading ? null : onPressed,
        icon: isLoading
            ? const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : Icon(icon, size: 18),
        label: Text(label,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFE0E0E0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
      ),
    );
  }

  // ── Rider Note Input ─────────────────────────

  Widget _buildRiderNoteInput(Order order) {
    final ctrl = _riderNoteCtrls.putIfAbsent(
      order.id,
      () => TextEditingController(text: order.riderNote ?? ''),
    );
    final notesProvider = context.read<RiderNotesProvider>();
    final isSending = notesProvider.isSending(order.id);
    final hasExistingNote = order.riderNote != null && order.riderNote!.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.chat_outlined, size: 16, color: Color(0xFFFF5745)),
            const SizedBox(width: 6),
            const Text('Quick Note to Customer',
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600,
                    color: Color(0xFFFF5745))),
          ],
        ),
        const SizedBox(height: 8),
        if (hasExistingNote) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F0),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: const Color(0xFFFF5745).withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle,
                    size: 14, color: Color(0xFFFF5745)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text('Sent: "${order.riderNote!}"',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFFFF5745),
                          fontWeight: FontWeight.w500)),
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
                    hintStyle: const TextStyle(
                        color: Color(0xFFBFBFBF), fontSize: 13),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE8E8E8)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFE8E8E8)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFFF5745)),
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
                              backgroundColor: Color(0xFFFF5745),
                              behavior: SnackBarBehavior.floating,
                              duration: Duration(seconds: 2),
                            ),
                          );
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF5745),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFE0E0E0),
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
                child: isSending
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded, size: 18),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Status Badge ─────────────────────────────

  Widget _buildStatusBadge(OrderStatus status) {
    Color bgColor;
    Color textColor;
    String label;

    switch (status) {
      case OrderStatus.outForDelivery:
        bgColor = const Color(0xFFF6FFED);
        textColor = const Color(0xFF52C41A);
        label = 'Ready';
      case OrderStatus.pickedUp:
        bgColor = const Color(0xFFFFF1F0);
        textColor = const Color(0xFFFF5745);
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

  // ── Earnings Tab ─────────────────────────────

  Widget _buildEarningsTab() {
    if (_isLoadingStats) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFFF5222D)),
            SizedBox(height: 16),
            Text('Loading stats...',
                style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14)),
          ],
        ),
      );
    }

    final deliveries = (_riderStats['total_deliveries'] as num?)?.toInt() ?? 0;
    final earnings = (_riderStats['total_earnings'] as num?)?.toDouble() ?? 0.0;
    final distance = (_riderStats['estimated_distance_km'] as num?)?.toDouble() ?? 0.0;

    return RefreshIndicator(
      onRefresh: _fetchRiderStats,
      color: const Color(0xFFF5222D),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Today's Summary Header ──
          const Text("Today's Summary",
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A1A))),
          const SizedBox(height: 4),
          const Text('Your delivery performance today',
              style: TextStyle(fontSize: 14, color: Color(0xFF8E8E93))),
          const SizedBox(height: 20),

          // ── Stats Cards Grid ──
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  icon: Icons.check_circle,
                  label: 'Deliveries',
                  value: '$deliveries',
                  color: const Color(0xFF52C41A),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStatCard(
                  icon: Icons.route,
                  label: 'Distance',
                  value: '${distance.toStringAsFixed(1)} km',
                  color: const Color(0xFFFF5745),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildStatCard(
            icon: Icons.account_balance_wallet,
            label: 'Estimated Earnings',
            value: _formatCurrency(earnings),
            color: const Color(0xFFF5222D),
            large: true,
          ),
          const SizedBox(height: 24),

          // ── Info text ──
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
                const Icon(Icons.info_outline,
                    size: 16, color: Color(0xFFF9A825)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Earnings shown are delivery fees only. '
                    'Distance is estimated from completed orders.',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF795548),
                        height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          // ── Active jobs count ──
          if (_jobs.isNotEmpty) ...[
            const Text('Active Jobs',
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A1A))),
            const SizedBox(height: 8),
            ..._jobs.map((order) => Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE8E8E8)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Color(0xFFF9A825),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child:                      Text(
                          _formatCurrency(order.total),
                          style: const TextStyle(
                              fontSize: 13, color: Color(0xFF1A1A1A)),
                        ),
                      ),
                      _buildStatusBadge(order.status),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    bool large = false,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(large ? 20 : 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8E8E8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: large ? 22 : 20),
          ),
          SizedBox(height: large ? 16 : 12),
          Text(label,
              style: TextStyle(
                  fontSize: large ? 14 : 13,
                  color: const Color(0xFF8E8E93),
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: large ? 28 : 22,
                  fontWeight: FontWeight.w700,
                  color: color)),
        ],
      ),
    );
  }
}
