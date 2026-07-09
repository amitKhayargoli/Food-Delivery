import 'dart:async';

import 'package:flutter/material.dart';
import 'package:baato_maps/baato_maps.dart';
// ignore: implementation_imports
import 'package:baato_maps/src/map_core/implementation/baato_map_controller_impl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../widgets/rider_map_view.dart';
import '../core/services/supabase_client_service.dart';

/// A full-screen map that shows the rider's live location alongside
/// the pickup (restaurant) and dropoff (delivery) markers.
///
/// Opened by tapping the mini map in the Owner Dashboard Ready tab.
/// The map is centered on the rider's current location at zoom ~15 so
/// the user can clearly see where the rider is in real time.
class FullScreenMapScreen extends StatefulWidget {
  final RiderMapPoint riderLocation;
  final RiderMapPoint? pickupLocation;
  final RiderMapPoint? dropoffLocation;
  final String? etaText;

  /// The rider's Supabase user ID — used for live location tracking.
  final String riderId;

  const FullScreenMapScreen({
    super.key,
    required this.riderLocation,
    required this.riderId,
    this.pickupLocation,
    this.dropoffLocation,
    this.etaText,
  });

  @override
  State<FullScreenMapScreen> createState() => _FullScreenMapScreenState();
}

class _FullScreenMapScreenState extends State<FullScreenMapScreen> {
  final BaatoMapController _mapController = BaatoMapControllerImpl();
  bool _isMapLoading = true;

  /// Live rider location — updated via Realtime subscription.
  /// Initialised from [widget.riderLocation] but kept fresh as the rider moves.
  late RiderMapPoint _liveRiderLocation;

  /// Realtime channel for live rider location updates.
  sb.RealtimeChannel? _riderLocationChannel;

  // ── Route state ──
  bool _showRoute = true;
  bool _isRouteLoading = false;

  /// Debounce timer to avoid excessive Baato Directions API calls.
  Timer? _routeRefreshDebounce;

  /// Screen positions for Flutter overlay markers.
  final Map<String, Offset> _markerScreenPositions = {};

  // ── Polling fallback ──
  Timer? _riderPollingTimer;
  DateTime? _lastRealtimeUpdate;
  static const _pollingInterval = Duration(seconds: 15);

  @override
  void initState() {
    super.initState();
    _liveRiderLocation = widget.riderLocation;
    _subscribeToRiderLocation();
  }

  /// Subscribe to live rider location updates via Supabase Realtime.
  void _subscribeToRiderLocation() {
    try {
      _riderLocationChannel =
          SupabaseClientService.client.channel('fullscreen-rider-${widget.riderId}');

      _riderLocationChannel!.onPostgresChanges(
        event: sb.PostgresChangeEvent.update,
        schema: 'public',
        table: 'rider_locations',
        callback: (payload) {
          final record = payload.newRecord;
          if (record['user_id']?.toString() != widget.riderId) return;
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
            _onRiderLocationChanged();
          }
        },
      );

      _riderLocationChannel!.subscribe((status, [error]) {
        debugPrint('[FullScreenMap-RT] Channel status: $status');
        if (error != null) debugPrint('[FullScreenMap-RT] Error: $error');
      });

      _startPollingFallback();
    } catch (e) {
      debugPrint('[FullScreenMap-RT] Setup error: $e');
      _startPollingFallback();
    }
  }

  @override
  void dispose() {
    _unsubscribeFromRiderLocation();
    _routeRefreshDebounce?.cancel();
    _riderPollingTimer?.cancel();
    super.dispose();
  }

  void _unsubscribeFromRiderLocation() {
    if (_riderLocationChannel != null) {
      SupabaseClientService.client.removeChannel(_riderLocationChannel!);
      _riderLocationChannel = null;
    }
  }

  /// Center the map on the rider's current location with smooth animation.
  /// Uses [_liveRiderLocation] which is kept updated via Realtime subscription.
  void _centerOnRider() {
    try {
      _mapController.cameraManager.moveTo(
        BaatoCoordinate(
          latitude: _liveRiderLocation.latitude,
          longitude: _liveRiderLocation.longitude,
        ),
        zoom: 15.0,
        animate: true,
      );
    } catch (e) {
      debugPrint('[FullScreenMap] Error centering on rider: $e');
    }
  }

  /// Calculate screen positions for overlay markers via toScreenLocation.
  Future<void> _recalculateOverlayMarkers() async {
    final controller = _mapController.libreController;
    if (controller == null) {
      debugPrint('[FullScreenMap] ⚠️ libreController null, retrying in 800ms');
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) _recalculateOverlayMarkers();
      });
      return;
    }

    try {
      final newPositions = <String, Offset>{};

      // Rider
      final riderScreen = await controller.toScreenLocation(
        LatLng(_liveRiderLocation.latitude, _liveRiderLocation.longitude),
      );
      newPositions['rider'] =
          Offset(riderScreen.x.toDouble(), riderScreen.y.toDouble());

      // Pickup
      if (widget.pickupLocation != null) {
        final pickupScreen = await controller.toScreenLocation(
          LatLng(widget.pickupLocation!.latitude, widget.pickupLocation!.longitude),
        );
        newPositions['pickup'] =
            Offset(pickupScreen.x.toDouble(), pickupScreen.y.toDouble());
      }

      // Dropoff
      if (widget.dropoffLocation != null) {
        final dropoffScreen = await controller.toScreenLocation(
          LatLng(widget.dropoffLocation!.latitude, widget.dropoffLocation!.longitude),
        );
        newPositions['dropoff'] =
            Offset(dropoffScreen.x.toDouble(), dropoffScreen.y.toDouble());
      }

      debugPrint('[FullScreenMap] Marker positions: ${newPositions.keys.join(", ")}');

      if (mounted) {
        setState(() {
          _markerScreenPositions
            ..clear()
            ..addAll(newPositions);
        });
      }
    } catch (e) {
      debugPrint('[FullScreenMap] ❌ Marker conversion error: $e - retrying');
      Future.delayed(const Duration(milliseconds: 1000), () {
        if (mounted) _recalculateOverlayMarkers();
      });
    }
  }

  // ──────────────────────────────────────────────
  //  Route Drawing (Baato Directions API)
  // ──────────────────────────────────────────────

  /// Fetch the route from rider → pickup → dropoff using the Baato Directions
  /// API and draw it on the map. Uses [midCoordinates] to route through the
  /// restaurant pickup location as a waypoint.
  Future<void> _fetchAndDrawRoute() async {
    if (_isRouteLoading) return;

    try {
      setState(() => _isRouteLoading = true);

      final riderCoord = BaatoCoordinate(
        latitude: _liveRiderLocation.latitude,
        longitude: _liveRiderLocation.longitude,
      );

      final dropoffCoord = BaatoCoordinate(
        latitude: widget.dropoffLocation!.latitude,
        longitude: widget.dropoffLocation!.longitude,
      );

      // Build waypoints — include pickup (restaurant) if available
      final List<BaatoCoordinate> midCoords = [];
      if (widget.pickupLocation != null) {
        midCoords.add(BaatoCoordinate(
          latitude: widget.pickupLocation!.latitude,
          longitude: widget.pickupLocation!.longitude,
        ));
      }

      // Fetch route from Baato Directions API
      final route = await Baato.api.direction.getRoutes(
        startCoordinate: riderCoord,
        endCoordinate: dropoffCoord,
        midCoordinates: midCoords,
        mode: BaatoDirectionMode.car,
        decodePolyline: true,
      );

      // Draw new route first (smooth transition, no blink)
      await _mapController.routeManager.drawRouteFromResponse(
        route,
        lineLayerProperties: BaatoLineLayerProperties(
          lineColor: '#D93025',
          lineWidth: 4.0,
          lineOpacity: 0.8,
        ),
      );

      if (mounted) setState(() => _showRoute = true);
    } catch (e) {
      debugPrint('[FullScreenMap] Route fetch/draw error: $e');
    } finally {
      if (mounted) setState(() => _isRouteLoading = false);
    }
  }

  /// Toggle the route visibility on/off.
  Future<void> _toggleRoute() async {
    _routeRefreshDebounce?.cancel();
    if (_showRoute) {
      // Hide route
      try {
        await _mapController.routeManager.clearRoute();
      } catch (_) {}
      if (mounted) setState(() => _showRoute = false);
    } else {
      // Show route (re-fetch from live location)
      await _fetchAndDrawRoute();
    }
  }

  /// Poll rider location via Supabase REST as fallback when Realtime is silent.
  /// Only fires if no Realtime update was received within [_pollingInterval].
  void _startPollingFallback() {
    _riderPollingTimer?.cancel();
    _riderPollingTimer = Timer.periodic(_pollingInterval, (_) async {
      // Skip polling if Realtime is alive
      if (_lastRealtimeUpdate != null &&
          DateTime.now().difference(_lastRealtimeUpdate!) < _pollingInterval) {
        return;
      }

      if (!mounted) return;

      try {
        final rows = await SupabaseClientService.client
            .from('rider_locations')
            .select('latitude, longitude')
            .eq('user_id', widget.riderId)
            .limit(1);

        if (rows.isEmpty || !mounted) return;

        final row = rows.first;
        final lat = (row['latitude'] as num?)?.toDouble();
        final lng = (row['longitude'] as num?)?.toDouble();
        if (lat == null || lng == null) return;

        setState(() {
          _liveRiderLocation = RiderMapPoint(
            latitude: lat,
            longitude: lng,
            label: 'Rider',
            type: RiderMapPointType.rider,
          );
        });
        _onRiderLocationChanged();
      } catch (e) {
        debugPrint('[FullScreenMap-RT] Polling fetch failed: $e');
      }
    });
  }

  /// Redraw the route when rider location changes via Realtime.
  /// Calls the API directly if not already loading; retries after 500ms if busy.
  void _onRiderLocationChanged() {
    _routeRefreshDebounce?.cancel();
    if (!_showRoute) return;
    if (_isRouteLoading) {
      _routeRefreshDebounce = Timer(const Duration(milliseconds: 500), () {
        _onRiderLocationChanged();
      });
      return;
    }
    _fetchAndDrawRoute();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1C1C),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1C1C),
        elevation: 0.5,
        title: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Color(0xFFD93025),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Rider Live Location',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 17,
              ),
            ),
            const Spacer(),
            if (widget.etaText != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F0FE),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  widget.etaText!,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1967D2),
                  ),
                ),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: Stack(
        children: [
          // ── Baato Map ──
          BaatoMap(
            controller: _mapController,
            style: BaatoMapStyle.breeze,
            initialPosition: BaatoCoordinate(
              latitude: _liveRiderLocation.latitude,
              longitude: _liveRiderLocation.longitude,
            ),
            initialZoom: 15.0,
            myLocationEnabled: false,
            onMapCreated: (controller) {
              setState(() => _isMapLoading = false);
              // Draw route immediately (separate from markers)
              if (widget.dropoffLocation != null) {
                Future.delayed(const Duration(milliseconds: 800), () {
                  _fetchAndDrawRoute();
                });
              }
              // Position overlay markers later (after map settles)
              Future.delayed(const Duration(milliseconds: 1200), () {
                _recalculateOverlayMarkers();
              });
            },
          ),

          // ── Overlay markers (rider image, emojis) ──
          // Rider marker (custom image)
          if (_markerScreenPositions.containsKey('rider'))
            Positioned(
              left: _markerScreenPositions['rider']!.dx - 22,
              top: _markerScreenPositions['rider']!.dy - 35,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset('assets/img/deliveryguy.png',
                    width: 36, height: 36,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.delivery_dining, size: 30, color: Color(0xFFD93025)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(_liveRiderLocation.label,
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1C1C)),
                    ),
                  ),
                ],
              ),
            ),

          // Pickup / Restaurant marker (emoji)
          if (_markerScreenPositions.containsKey('pickup'))
            Positioned(
              left: _markerScreenPositions['pickup']!.dx - 18,
              top: _markerScreenPositions['pickup']!.dy - 28,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🏪', style: TextStyle(fontSize: 28)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('Restaurant',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                        color: Color(0xFF1E8E3E)),
                    ),
                  ),
                ],
              ),
            ),

          // Dropoff / Customer marker (emoji)
          if (_markerScreenPositions.containsKey('dropoff'))
            Positioned(
              left: _markerScreenPositions['dropoff']!.dx - 18,
              top: _markerScreenPositions['dropoff']!.dy - 28,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('📍', style: TextStyle(fontSize: 28)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(widget.dropoffLocation?.label ?? 'Delivery',
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                        color: Color(0xFFBB0018)),
                    ),
                  ),
                ],
              ),
            ),

          // ── Find Rider FAB (re-centers map on rider's live location) ──
          // ── FABs (top-right) ──
          if (!_isMapLoading)
            Positioned(
              right: 16,
              top: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Find Rider button
                  Material(
                    elevation: 4,
                    shape: const CircleBorder(),
                    color: Colors.white,
                    child: InkWell(
                      onTap: _centerOnRider,
                      customBorder: const CircleBorder(),
                      child: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.my_location,
                          color: Color(0xFFD93025),
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Show/Hide Route button
                  Material(
                    elevation: 4,
                    shape: const CircleBorder(),
                    color: Colors.white,
                    child: InkWell(
                      onTap: _isRouteLoading ? null : _toggleRoute,
                      customBorder: const CircleBorder(),
                      child: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        child: _isRouteLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(
                                Icons.route_rounded,
                                color: _showRoute
                                    ? const Color(0xFFD93025)
                                    : const Color(0xFF8E8E93),
                                size: 22,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ── Route legend indicator ──
          if (!_isMapLoading && _showRoute)
            Positioned(
              left: 16,
              top: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 20,
                      height: 3,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD93025),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Route',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF5C5C5C),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Loading skeleton ──
          if (_isMapLoading)
            Container(
              color: Colors.grey.shade100,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(strokeWidth: 3),
                    SizedBox(height: 16),
                    Text(
                      'Loading map...',
                      style: TextStyle(
                        color: Color(0xFF8E8E93),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Bottom info bar ──
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                border: Border(
                  top: BorderSide(color: Colors.grey.shade200),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Legend
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _legendItem('Rider', const Color(0xFFD93025)),
                        const SizedBox(width: 20),
                        _legendItem('Restaurant', const Color(0xFF1E8E3E)),
                        const SizedBox(width: 20),
                        _legendItem('Delivery', const Color(0xFFBB0018)),
                      ],
                    ),
                    if (widget.etaText != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Rider is ${widget.etaText!.toLowerCase()}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF5C5C5C),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Color(0xFF5C5C5C),
          ),
        ),
      ],
    );
  }
}
