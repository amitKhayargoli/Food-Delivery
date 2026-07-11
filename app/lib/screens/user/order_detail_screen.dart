import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:url_launcher/url_launcher.dart';
import '../../models/order.dart';
import '../../core/services/api_service.dart';
import '../../core/services/supabase_client_service.dart';
import '../../widgets/rider_map_view.dart';
import '../../providers/auth_provider.dart';
import '../../injection_container.dart' as di;
import '../full_screen_map_screen.dart';
import 'support_conversation_list_screen.dart';
import 'report_problem_screen.dart';

/// Displays the full details of an order for the customer.
/// Includes live rider tracking via Baato Map when a rider is assigned,
/// and a rating prompt after delivery.
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
  bool _hasRated = false;
  bool _isSubmittingRating = false;

  // Problem report
  Map<String, dynamic>? _problemReport;

  // Live rider tracking
  sb.RealtimeChannel? _riderLocationChannel;
  RiderMapPoint? _liveRiderLocation;
  RiderMapPoint? _restaurantLocation;  // pickup marker
  bool _isSubscribed = false;
  Timer? _riderPollingTimer;
  DateTime? _lastRealtimeUpdate;

  /// Max time without a Realtime update before falling back to polling.
  static const _pollingInterval = Duration(seconds: 15);

  @override
  void initState() {
    super.initState();
    _order = widget.order;
    _initRiderTracking();
    _fetchRestaurantLocation();
    _checkIfAlreadyRated();
    _fetchProblemReport();
  }

  @override
  void dispose() {
    _unsubscribeFromRiderLocation();
    _riderPollingTimer?.cancel();
    super.dispose();
  }

  /// Fetch existing problem report for this order, if any.
  Future<void> _fetchProblemReport() async {
    if (_order.status != OrderStatus.delivered) return;

    final token = context.read<AuthProvider>().token;
    if (token == null) return;

    try {
      final api = di.sl<ApiService>();
      final problem = await api.getProblemByOrder(
        orderId: _order.id,
        token: token,
      );
      if (!mounted) return;
      setState(() {
        _problemReport = problem;
      });
    } catch (_) {
      if (!mounted) return;
    }
  }

  /// Check if the current user has already rated this order.
  Future<void> _checkIfAlreadyRated() async {
    final token = context.read<AuthProvider>().token;
    if (token == null) return;

    try {
      final api = di.sl<ApiService>();
      final ratings = await api.getMyRatings(token: token);
      final hasRated = ratings.any((r) => r['order_id']?.toString() == _order.id);
      if (mounted && hasRated != _hasRated) {
        setState(() => _hasRated = hasRated);
      }
    } catch (_) {
      // Non-fatal — user can still rate; if duplicate, API returns 409
    }
  }

  // ── Live Rider Tracking ──────────────────────

  /// Subscribe to the rider's live location via Supabase Realtime.
  /// Only subscribes when a rider is assigned and the order is active.
  void _initRiderTracking() {
    final riderId = _order.deliveryBoyId;
    if (riderId == null || riderId.isEmpty) return;

    final isActive = _order.status == OrderStatus.pickedUp ||
        _order.status == OrderStatus.outForDelivery;
    if (!isActive) return;

    // Fetch initial rider position via REST
    _fetchInitialRiderLocation(riderId);

    // Subscribe to live updates
    _subscribeToRiderLocation(riderId);
  }

  /// Fetch the restaurant's lat/lng from the restaurant_applications table.
  /// This provides the pickup marker location on the live tracking map.
  Future<void> _fetchRestaurantLocation() async {
    final restaurantId = _order.restaurantId;
    if (restaurantId.isEmpty) return;

    try {
      final rows = await SupabaseClientService.client
          .from('restaurant_applications')
          .select('latitude, longitude, restaurant_name')
          .eq('id', restaurantId)
          .limit(1);

      if (rows.isEmpty || !mounted) return;

      final row = rows.first;
      final lat = (row['latitude'] as num?)?.toDouble();
      final lng = (row['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) return;

      setState(() {
        _restaurantLocation = RiderMapPoint(
          latitude: lat,
          longitude: lng,
          label: row['restaurant_name'] as String? ?? _order.restaurantName,
          type: RiderMapPointType.pickup,
        );
      });
    } catch (e) {
      debugPrint('[OrderDetail] Failed to fetch restaurant location: $e');
    }
  }

  /// Fetch the rider's current location via REST (one-time initial fetch).
  Future<void> _fetchInitialRiderLocation(String riderId) async {
    try {
      final token = context.read<AuthProvider>().token;
      if (token == null) return;

      final api = di.sl<ApiService>();
      final location = await api.getRiderLocation(
        riderId: riderId,
        token: token,
      );

      if (location == null || !mounted) return;

      final lat = location['latitude'] as num?;
      final lng = location['longitude'] as num?;
      if (lat == null || lng == null) return;

      setState(() {
        _liveRiderLocation = RiderMapPoint(
          latitude: lat.toDouble(),
          longitude: lng.toDouble(),
          label: 'Rider',
          type: RiderMapPointType.rider,
        );
      });
    } catch (e) {
      debugPrint('[RT-RiderLocation] Initial fetch failed: $e');
    }
  }

  void _subscribeToRiderLocation(String riderId) {
    if (_isSubscribed) return;
    _isSubscribed = true;

    try {
      _riderLocationChannel =
          SupabaseClientService.client.channel('rider-location-$riderId');

      _riderLocationChannel!.onPostgresChanges(
        event: sb.PostgresChangeEvent.update,
        schema: 'public',
        table: 'rider_locations',
        callback: (payload) {
          final record = payload.newRecord;
          // Filter to this specific rider
          if (record['user_id']?.toString() != riderId) return;
          final lat = record['latitude'] as num?;
          final lng = record['longitude'] as num?;
          if (lat == null || lng == null) return;

          _lastRealtimeUpdate = DateTime.now();

          if (mounted) {
            setState(() {
              _liveRiderLocation = RiderMapPoint(
                latitude: lat.toDouble(),
                longitude: lng.toDouble(),
                label: 'Rider',
                type: RiderMapPointType.rider,
              );
            });
          }
        },
      );

      _riderLocationChannel!.subscribe((status, [error]) {
        debugPrint('[RT-RiderLocation] Channel status: $status');
        if (error != null) {
          debugPrint('[RT-RiderLocation] Error: $error');
        }
      });

      // Start polling fallback: if Realtime goes silent for 15s, fall back to REST polling
      _startPollingFallback(riderId);
    } catch (e) {
      debugPrint('[RT-RiderLocation] Setup error: $e');
      // If Realtime setup fails, start polling immediately
      _startPollingFallback(riderId);
    }
  }

  /// Poll rider location via REST as a fallback when Realtime isn't available.
  /// Only fires if no Realtime update was received within [_pollingInterval].
  void _startPollingFallback(String riderId) {
    _riderPollingTimer?.cancel();
    _riderPollingTimer = Timer.periodic(_pollingInterval, (_) async {
      // Skip polling if we got a Realtime update within the last interval
      if (_lastRealtimeUpdate != null &&
          DateTime.now().difference(_lastRealtimeUpdate!) < _pollingInterval) {
        return;
      }

      final token = context.read<AuthProvider>().token;
      if (token == null) return;
      if (!mounted) return;

      try {
        final api = di.sl<ApiService>();
        final location = await api.getRiderLocation(
          riderId: riderId,
          token: token,
        );
        if (location == null || !mounted) return;
        final lat = location['latitude'] as num?;
        final lng = location['longitude'] as num?;
        if (lat == null || lng == null) return;

        setState(() {
          _liveRiderLocation = RiderMapPoint(
            latitude: lat.toDouble(),
            longitude: lng.toDouble(),
            label: 'Rider',
            type: RiderMapPointType.rider,
          );
        });
      } catch (e) {
        debugPrint('[RT-RiderLocation] Polling fetch failed: $e');
      }
    });
  }

  void _unsubscribeFromRiderLocation() {
    if (_riderLocationChannel != null) {
      SupabaseClientService.client.removeChannel(_riderLocationChannel!);
      _riderLocationChannel = null;
    }
    _isSubscribed = false;
  }

  /// Build the rider's avatar — shows uploaded photo or a letter fallback.
  Widget _buildRiderAvatar({double size = 28}) {
    final avatarUrl = _order.deliveryBoyAvatarUrl;

    if (avatarUrl != null && avatarUrl.isNotEmpty) {
      return Image.network(
        avatarUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _defaultRiderAvatar(size: size),
      );
    }

    return _defaultRiderAvatar(size: size);
  }

  Widget _defaultRiderAvatar({double size = 28}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F0),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Icon(Icons.person_outline,
          size: 16, color: Color(0xFFBB0018)),
    );
  }

  /// Estimate ETA text based on rough distance (placeholder — real ETA
  /// requires Baato Directions API call).
  String? _estimatedEtaText() {
    if (_liveRiderLocation == null) return null;
    if (_order.deliveryAddress?.latitude == null ||
        _order.deliveryAddress?.longitude == null) {
      return null;
    }

    // Rough Haversine-based time estimate: assume avg speed 20 km/h
    const double avgSpeedKmh = 20.0;
    final double lat1 = _liveRiderLocation!.latitude;
    final double lon1 = _liveRiderLocation!.longitude;
    final double lat2 = _order.deliveryAddress!.latitude!;
    final double lon2 = _order.deliveryAddress!.longitude!;

    // Convert all lat/lng to radians before trig functions
    const double R = 6371; // Earth radius in km
    final double lat1Rad = _deg2rad(lat1);
    final double lon1Rad = _deg2rad(lon1);
    final double lat2Rad = _deg2rad(lat2);
    final double lon2Rad = _deg2rad(lon2);
    final double dLat = lat2Rad - lat1Rad;
    final double dLon = lon2Rad - lon1Rad;

    // Haversine formula — clamp `a` to [0, 1] to prevent NaN from
    // floating-point rounding when coordinates are nearly identical.
    final double a = (sin(dLat / 2) * sin(dLat / 2) +
            cos(lat1Rad) * cos(lat2Rad) * sin(dLon / 2) * sin(dLon / 2))
        .clamp(0.0, 1.0);
    final double c = 2 * asin(sqrt(a));
    final double distanceKm = R * c;

    final int minutes = (distanceKm / avgSpeedKmh * 60).round();
    if (minutes < 1) return 'Arriving now';
    if (minutes < 60) return 'Rider is $minutes min away';
    return 'Rider is ${minutes ~/ 60} h ${minutes % 60} min away';
  }

  double _deg2rad(double deg) => deg * (pi / 180.0);

  // ── Rating ───────────────────────────────────

  Future<void> _showRatingSheet() async {
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
              // Drag handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD9D9D9),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),

              // Rider avatar + name
              if (_order.deliveryBoyName != null &&
                  _order.deliveryBoyName!.isNotEmpty)
                Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: _buildRiderAvatar(size: 48),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _order.deliveryBoyName!,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1C1C),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),

              const Text(
                'How was your delivery?',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1C1C),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Rate your rider\'s service',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 24),

              // Star rating
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (index) {
                  final starNum = index + 1;
                  return GestureDetector(
                    onTap: () => setSheetState(() => selectedRating = starNum),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        starNum <= selectedRating
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
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

              // Optional comment
              TextField(
                controller: commentCtrl,
                maxLines: 3,
                maxLength: 200,
                decoration: InputDecoration(
                  hintText: 'Share your experience (optional)',
                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade300),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFBB0018)),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFFAF9F9),
                  contentPadding: const EdgeInsets.all(14),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 16),

              // Submit button
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: _isSubmittingRating
                      ? const SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text(
                          'Submit Rating',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (result == true && selectedRating > 0) {
      comment = commentCtrl.text.trim();
      await _submitRating(selectedRating, comment.isEmpty ? null : comment);
    }
    commentCtrl.dispose();
  }

  Future<void> _submitRating(int rating, String? comment) async {
    final token = context.read<AuthProvider>().token;
    final riderId = _order.deliveryBoyId;
    if (token == null || riderId == null) return;

    setState(() => _isSubmittingRating = true);
    try {
      final api = di.sl<ApiService>();
      await api.submitRiderRating(
        orderId: _order.id,
        riderId: riderId,
        rating: rating,
        comment: comment,
        token: token,
      );
      if (mounted) {
        setState(() {
          _hasRated = true;
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
          SnackBar(
            content: Text(e.message),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _isSubmittingRating = false);
    }
  }

  // ── Cancel Order ────────────────────────────

  Future<void> _cancelOrder() async {
    // Confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFF5222D), size: 24),
            SizedBox(width: 10),
            Text('Cancel Order?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ],
        ),
        content: const Text(
          'Are you sure you want to cancel this order?\n\n'
          'If a rider is already assigned, they will be notified and this delivery will be removed from their queue.',
          style: TextStyle(fontSize: 14, color: Color(0xFF5C5C5C), height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Order',
              style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF8E8E93))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, Cancel',
              style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFF5222D))),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    final token = context.read<AuthProvider>().token;
    if (token == null) return;

    try {
      final api = di.sl<ApiService>();
      await api.cancelOrder(orderId: _order.id, token: token);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('Order cancelled successfully.'),
            ],
          ),
          backgroundColor: Color(0xFF1E8E3E),
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context, true); // Return to orders list
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Build a card showing the problem report status.
  Widget _buildProblemStatusCard() {
    final problem = _problemReport;
    if (problem == null) return const SizedBox.shrink();

    final status = problem['status'] as String? ?? 'PENDING';
    final issueType = problem['issue_type'] as String? ?? '';
    final adminNote = problem['admin_note'] as String?;

    final typeLabels = {
      'wrong_item': 'Wrong Item',
      'missing_item': 'Missing Item',
      'quality': 'Food Quality',
      'other': 'Other Issue',
    };

    Color bgColor;
    Color borderColor;
    Color textColor;
    IconData icon;
    String statusLabel;
    String description;

    switch (status) {
      case 'APPROVED':
        bgColor = const Color(0xFFE6F4EA);
        borderColor = const Color(0xFF1E8E3E);
        textColor = const Color(0xFF1E8E3E);
        icon = Icons.check_circle;
        statusLabel = 'Refund Approved';
        description = adminNote != null
            ? 'Approved: $adminNote'
            : 'Your refund request has been approved.';
      case 'REJECTED':
        bgColor = const Color(0xFFFFF1F0);
        borderColor = const Color(0xFFF5222D);
        textColor = const Color(0xFFF5222D);
        icon = Icons.cancel_rounded;
        statusLabel = 'Refund Rejected';
        description = adminNote != null
            ? 'Rejected: $adminNote'
            : 'Your refund request has been declined.';
      default:
        bgColor = const Color(0xFFFFF8E1);
        borderColor = const Color(0xFFFFE082);
        textColor = const Color(0xFF795548);
        icon = Icons.hourglass_empty_rounded;
        statusLabel = 'Pending Review';
        description = 'Your report is being reviewed by the restaurant.';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: textColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(statusLabel,
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700,
                            color: textColor)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: textColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(typeLabels[issueType] ?? issueType,
                          style: TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w600,
                              color: textColor)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(description,
                    style: TextStyle(fontSize: 12, color: textColor)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Show the delivery photo in a full-screen dialog for a closer look.
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

  // ── Formatting ───────────────────────────────

  String _formatCurrency(double amount) {
    return 'Rs. ${amount.toStringAsFixed(0)}';
  }

  String _statusLabel(OrderStatus status) {
    switch (status) {
      case OrderStatus.created:
        return 'Pending';
      case OrderStatus.accepted:
        return 'Order Accepted';
      case OrderStatus.preparing:
        return 'Preparing';
      case OrderStatus.outForDelivery:
        return 'Ready for Pickup';
      case OrderStatus.pickedUp:
        return 'Picked Up — On the way!';
      case OrderStatus.delivered:
        return 'Delivered 🎉';
      case OrderStatus.cancelled:
        return 'Cancelled';
    }
  }

  Color _statusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.created:
        return const Color(0xFFF9A825);
      case OrderStatus.accepted:
        return const Color(0xFF1967D2);
      case OrderStatus.preparing:
        return const Color(0xFFF9A825);
      case OrderStatus.outForDelivery:
        return const Color(0xFF1E8E3E);
      case OrderStatus.pickedUp:
        return const Color(0xFF1967D2);
      case OrderStatus.delivered:
        return const Color(0xFF1E8E3E);
      case OrderStatus.cancelled:
        return const Color(0xFF8E8E93);
    }
  }

  // ── Call Rider via Phone App ─────────────────

  Future<void> _callRider() async {
    final phone = _order.deliveryBoyPhone;
    if (phone == null || phone.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Rider phone number not available'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open phone app'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ── Build ────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hasDeliveryBoy = _order.deliveryBoyId != null &&
        _order.deliveryBoyId!.isNotEmpty;
    final canCall = hasDeliveryBoy &&
        (_order.status == OrderStatus.pickedUp ||
            _order.status == OrderStatus.outForDelivery);
    final showLiveMap = hasDeliveryBoy &&
        (_order.status == OrderStatus.pickedUp ||
            _order.status == OrderStatus.outForDelivery);
    final showRatingPrompt = !_hasRated &&
        _order.status == OrderStatus.delivered &&
        hasDeliveryBoy;

    final hasDropoffLocation =
        _order.deliveryAddress?.latitude != null &&
        _order.deliveryAddress?.longitude != null;

    final etaText = _estimatedEtaText();

    final canCancelOrder = _order.status != OrderStatus.delivered &&
        _order.status != OrderStatus.cancelled &&
        _order.status != OrderStatus.pickedUp;

    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F9),
      appBar: AppBar(
        title: Text(
          'Order #${_order.orderNumber}',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1C1C),
        elevation: 0.5,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Live Rider Tracking Map ──
            if (showLiveMap && hasDropoffLocation && _liveRiderLocation != null)
              _buildLiveTrackingCard(etaText),

            // ── Restaurant name ──
            if (_order.restaurantName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1F0),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.storefront_rounded,
                        size: 20,
                        color: Color(0xFFBB0018),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Restaurant',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF8E8E93),
                          ),
                        ),
                        Text(
                          _order.restaurantName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1A1C1C),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            // ── Status card ──
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x141B1C1C),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _statusColor(_order.status).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          _statusLabel(_order.status),
                          style: TextStyle(
                            color: _statusColor(_order.status),
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _formatCurrency(_order.total),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFF5222D),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_order.riderNote != null && _order.riderNote!.isNotEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F0FE),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFF1967D2).withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.chat_outlined,
                              size: 14, color: Color(0xFF1967D2)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Rider: "${_order.riderNote}"',
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
              ),
            ),

            const SizedBox(height: 20),

            // ── Order items ──
            const Text(
              'Order Items',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1C1C),
              ),
            ),
            const SizedBox(height: 12),
            ..._order.items.map((item) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${item.quantity}x ${item.name}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF1A1C1C),
                          ),
                        ),
                        if (item.specialInstructions != null &&
                            item.specialInstructions!.isNotEmpty)
                          Text(
                            item.specialInstructions!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF8E8E93),
                            ),
                          ),
                      ],
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
            )),

            const SizedBox(height: 20),

            // ── Delivery Address ──
            if (_order.deliveryAddress?.fullAddress != null) ...[
              const Text(
                'Delivery Address',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1C1C),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on_outlined,
                        color: Color(0xFFF5222D), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _order.deliveryAddress!.fullAddress!,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── Delivery Photo Proof ──
            if (_order.deliveryPhotoUrl != null && _order.deliveryPhotoUrl!.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text(
                'Delivery Photo',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1C1C),
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => _showDeliveryPhotoFullScreen(_order.deliveryPhotoUrl!),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x141B1C1C),
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Image.network(
                          _order.deliveryPhotoUrl!,
                          width: double.infinity,
                          height: 200,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            height: 200,
                            color: const Color(0xFFF5F5F5),
                            child: const Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.broken_image_outlined,
                                      size: 32, color: Color(0xFFBFBFBF)),
                                  SizedBox(height: 8),
                                  Text('Photo unavailable',
                                      style: TextStyle(
                                          fontSize: 13, color: Color(0xFFBFBFBF))),
                                ],
                              ),
                            ),
                          ),
                          loadingBuilder: (_, child, progress) {
                            if (progress == null) return child;
                            return Container(
                              height: 200,
                              color: const Color(0xFFF5F5F5),
                              child: const Center(
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Color(0xFFBB0018)),
                              ),
                            );
                          },
                        ),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: const BoxDecoration(
                            color: Color(0xFFE6F4EA),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.camera_alt_rounded,
                                  size: 14, color: Color(0xFF1E8E3E)),
                              SizedBox(width: 6),
                              Text('Delivery proof — tap to expand',
                                  style: TextStyle(
                                      fontSize: 12, fontWeight: FontWeight.w500,
                                      color: Color(0xFF1E8E3E))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // ── Call Rider button ──
            if (hasDeliveryBoy)
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: canCall ? _callRider : null,
                  icon: Icon(
                    canCall ? Icons.phone_rounded : Icons.phone_disabled_rounded,
                    size: 20,
                  ),
                  label: Text(
                    canCall ? 'Call Rider' : 'Rider assigned — wait for pickup',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canCall
                        ? const Color(0xFF34C759)
                        : const Color(0xFFEFEDED),
                    foregroundColor: canCall ? Colors.white : const Color(0xFFBFBFBF),
                    disabledBackgroundColor: const Color(0xFFEFEDED),
                    disabledForegroundColor: const Color(0xFFBFBFBF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: canCall ? 2 : 0,
                  ),
                ),
              ),

            // ── Cancel Order button ──
            if (canCancelOrder)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: _cancelOrder,
                    icon: const Icon(Icons.cancel_outlined, size: 20),
                    label: const Text(
                      'Cancel Order',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFF5222D),
                      side: const BorderSide(color: Color(0xFFF5222D)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ),

            // ── Rating Prompt ──
            if (showRatingPrompt) ...[
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFF8E1), Color(0xFFFFFDF5)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFFE082)),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.emoji_emotions_outlined,
                      size: 40,
                      color: Color(0xFFF9A825),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Enjoyed your delivery?',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1A1C1C),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Rate your rider\'s service',
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF795548),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _showRatingSheet,
                        icon: const Icon(Icons.star_rounded, size: 20),
                        label: const Text(
                          'Rate Delivery',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF9A825),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── Report a Problem (only for delivered orders) ──
            if (_order.status == OrderStatus.delivered) ...[
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _problemReport != null
                        ? null
                        : () async {
                            final result = await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ReportProblemScreen(
                                  orderId: _order.id,
                                  orderNumber: _order.orderNumber,
                                ),
                              ),
                            );
                            if (result == true) {
                              _fetchProblemReport();
                            }
                          },
                    icon: Icon(
                      _problemReport != null
                          ? Icons.check_circle_outline
                          : Icons.flag_outlined,
                      size: 18,
                    ),
                    label: Text(
                      _problemReport != null
                          ? 'Report Submitted'
                          : 'Report a Problem',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _problemReport != null
                            ? const Color(0xFF8E8E93)
                            : const Color(0xFFF5222D),
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _problemReport != null
                          ? const Color(0xFF8E8E93)
                          : const Color(0xFFF5222D),
                      side: BorderSide(
                        color: _problemReport != null
                            ? const Color(0xFFE5E7EB)
                            : const Color(0xFFF5222D),
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
              // Problem status banner
              if (_problemReport != null) ...[
                const SizedBox(height: 12),
                _buildProblemStatusCard(),
              ],
            ],

            // ── Contact Support ──
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SupportConversationListScreen(
                          orderId: _order.id,
                          orderNumber: _order.orderNumber,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.headset_mic_rounded, size: 18),
                  label: const Text('Contact Support',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF1967D2),
                    side: const BorderSide(color: Color(0xFF1967D2)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),

            // ── Already rated indicator ──
            if (_hasRated) ...[
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE6F4EA),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: const Color(0xFF1E8E3E).withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle,
                        color: Color(0xFF1E8E3E), size: 22),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'You rated this delivery. Thanks for your feedback!',
                        style: TextStyle(
                          fontSize: 13,
                          color: Color(0xFF1E8E3E),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  /// A card showing the live rider tracking map with ETA and Call Rider.
  Widget _buildLiveTrackingCard(String? etaText) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x141B1C1C),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF1967D2),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Live Tracking',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1C1C),
                  ),
                ),
                const Spacer(),
                if (etaText != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F0FE),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      etaText,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1967D2),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // ── Rider info (avatar + name) ──
          if (_order.deliveryBoyName != null &&
              _order.deliveryBoyName!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  // Rider avatar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: _buildRiderAvatar(),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _order.deliveryBoyName!,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1C1C),
                        ),
                      ),
                      const Text(
                        'Your rider',
                        style: TextStyle(
                            fontSize: 11, color: Color(0xFF8E8E93)),
                      ),
                    ],
                  ),
                ],
              ),
            ),

          const SizedBox(height: 8),

          // ── Map (tap to open full screen) ──
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(16)),
            child: RiderMapView(
              riderLocation: _liveRiderLocation!,
              pickupLocation: _restaurantLocation,
              dropoffLocation: RiderMapPoint(
                latitude: _order.deliveryAddress!.latitude!,
                longitude: _order.deliveryAddress!.longitude!,
                label: _order.deliveryAddress!.fullAddress ?? 'You',
                type: RiderMapPointType.dropoff,
              ),
              etaText: etaText,
              height: 220,
              showEtaBar: false,
              showRoute: true,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FullScreenMapScreen(
                      riderLocation: _liveRiderLocation!,
                      pickupLocation: _restaurantLocation,
                      dropoffLocation: RiderMapPoint(
                        latitude: _order.deliveryAddress!.latitude!,
                        longitude: _order.deliveryAddress!.longitude!,
                        label: _order.deliveryAddress!.fullAddress ?? 'You',
                        type: RiderMapPointType.dropoff,
                      ),
                      riderId: _order.deliveryBoyId!,
                      etaText: etaText,
                    ),
                  ),
                );
              },
            ),
          ),

          // ── ETA bar (bottom) ──
          if (etaText != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.access_time_rounded,
                      size: 18, color: Color(0xFF1967D2)),
                  const SizedBox(width: 8),
                  Text(
                    etaText,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1C1C),
                    ),
                  ),
                  const Spacer(),
                  SizedBox(
                    height: 36,
                    child: ElevatedButton.icon(
                      onPressed: _order.deliveryBoyId != null
                          ? _callRider
                          : null,
                      icon: const Icon(Icons.phone_rounded, size: 16),
                      label: const Text('Call',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF34C759),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
