import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:baato_maps/baato_maps.dart';
// ignore: implementation_imports
import 'package:baato_maps/src/map_core/implementation/baato_map_controller_impl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../widgets/rider_map_view.dart';
import '../core/services/supabase_client_service.dart';

/// A full-screen map that shows the rider's live location alongside
/// the pickup (restaurant) and dropoff (delivery) markers.
///
/// Uses Baato's native [markerManager.addMarker] API so markers correctly
/// track their lat/lng coordinates as the rider moves and the user pans/zooms.
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

  /// Tracks which images have been loaded into the map sprite sheet.
  final Set<String> _loadedImages = {};

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

  /// Native Baato markers currently displayed on the map.
  /// Cleared and re-added when locations or rider moves.
  final List<Symbol> _currentMarkers = [];

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
    _clearMarkers();
    super.dispose();
  }

  void _unsubscribeFromRiderLocation() {
    if (_riderLocationChannel != null) {
      SupabaseClientService.client.removeChannel(_riderLocationChannel!);
      _riderLocationChannel = null;
    }
  }

  /// Center the map on the rider's current location with smooth animation.
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

  /// Clear all native Baato markers.
  Future<void> _clearMarkers() async {
    try {
      await _mapController.markerManager.clearMarkers();
      _currentMarkers.clear();
    } catch (_) {}
  }

  /// Load the delivery guy image and the default Baato marker image into the
  /// map sprite sheet so they can be used as native marker icons.
  ///
  /// The Baato SDK has `_addDefaultAssets()` commented out, so the `baato_marker`
  /// image is never loaded automatically — we must load it ourselves.
  Future<void> _loadMarkerImages() async {
    // ── Load delivery guy image ──
    if (!_loadedImages.contains('delivery_guy')) {
      try {
        final byteData = await rootBundle.load('assets/img/deliveryguy.png');
        await _mapController.addImageFromData('delivery_guy', byteData);
        _loadedImages.add('delivery_guy');
        debugPrint('[FullScreenMap] ✅ Delivery guy image loaded');
      } catch (e) {
        debugPrint('[FullScreenMap] ⚠️ Delivery guy image load failed: $e');
      }
    }

    // ── Load default Baato marker (needed for pickup/dropoff pins) ──
    if (!_loadedImages.contains('baato_marker')) {
      try {
        final baatoMarkerData = await rootBundle.load(
          'packages/baato_maps/lib/assets/markers/baato_marker.png',
        );
        await _mapController.addImageFromData('baato_marker', baatoMarkerData);
        _loadedImages.add('baato_marker');
        debugPrint('[FullScreenMap] ✅ Baato marker image loaded');
      } catch (e) {
        debugPrint('[FullScreenMap] ⚠️ Baato marker image load failed: $e');
      }
    }
  }

  /// Refresh all markers as native Baato symbols.
  Future<void> _refreshNativeMarkers() async {
    await _clearMarkers();
    await _loadMarkerImages();

    try {
      // ── Rider marker ──
      final riderSym = await _mapController.markerManager.addMarker(
        BaatoSymbolOption(
          geometry: BaatoCoordinate(
            latitude: _liveRiderLocation.latitude,
            longitude: _liveRiderLocation.longitude,
          ),
          iconImage: 'delivery_guy',
          iconSize: 0.8,
          textField: _liveRiderLocation.label,
          textSize: 11,
          textOffset: const Offset(0, 1.5),
          textColor: '#D93025',
          textHaloColor: '#FFFFFF',
          textHaloWidth: 1.0,
          zIndex: 10,
        ),
      );
      _currentMarkers.add(riderSym);

      // ── Pickup / Restaurant marker ──
      if (widget.pickupLocation != null) {
        final pickupSym = await _mapController.markerManager.addMarker(
          BaatoSymbolOption(
            geometry: BaatoCoordinate(
              latitude: widget.pickupLocation!.latitude,
              longitude: widget.pickupLocation!.longitude,
            ),
            iconImage: 'baato_marker',
            iconSize: 1.0,
            textField: widget.pickupLocation!.label,
            textSize: 11,
            textOffset: const Offset(0, 1.5),
            textColor: '#1E8E3E',
            textHaloColor: '#FFFFFF',
            textHaloWidth: 1.0,
          ),
        );
        _currentMarkers.add(pickupSym);
      }

      // ── Dropoff / Customer marker ──
      if (widget.dropoffLocation != null) {
        final dropoffSym = await _mapController.markerManager.addMarker(
          BaatoSymbolOption(
            geometry: BaatoCoordinate(
              latitude: widget.dropoffLocation!.latitude,
              longitude: widget.dropoffLocation!.longitude,
            ),
            iconImage: 'baato_marker',
            iconSize: 1.0,
            textField: widget.dropoffLocation!.label,
            textSize: 11,
            textOffset: const Offset(0, 1.5),
            textColor: '#BB0018',
            textHaloColor: '#FFFFFF',
            textHaloWidth: 1.0,
          ),
        );
        _currentMarkers.add(dropoffSym);
      }

      debugPrint('[FullScreenMap] ✅ Added ${_currentMarkers.length} native markers');
    } catch (e) {
      debugPrint('[FullScreenMap] ❌ Native marker error: $e');
    }
  }

  /// Called when rider location changes via Realtime — update marker + redraw route.
  void _onRiderLocationChanged() {
    // Refresh the rider marker position
    _refreshNativeMarkers();

    // Redraw route with new rider position
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

  // ──────────────────────────────────────────────
  //  Route Drawing (Baato Directions API)
  // ──────────────────────────────────────────────

  /// Fetch the route from rider → pickup → dropoff using the Baato Directions
  /// API and draw it on the map.
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
        mode: BaatoDirectionMode.bike,
        decodePolyline: true,
      );

      // Draw new route (smooth transition, no blink)
      await _mapController.routeManager.drawRouteFromResponse(
        route,
        lineLayerProperties: BaatoLineLayerProperties(
          lineColor: '#FF6B35',
          lineWidth: 5.0,
          lineOpacity: 0.85,
          lineBlur: 1.5,
          lineCap: 'round',
          lineJoin: 'round',
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
      try {
        await _mapController.routeManager.clearRoute();
      } catch (_) {}
      if (mounted) setState(() => _showRoute = false);
    } else {
      await _fetchAndDrawRoute();
    }
  }

  /// Poll rider location via Supabase REST as fallback when Realtime is silent.
  void _startPollingFallback() {
    _riderPollingTimer?.cancel();
    _riderPollingTimer = Timer.periodic(_pollingInterval, (_) async {
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
          // ── Baato Map (native markers are rendered by the map engine) ──
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
              // Draw route immediately
              if (widget.dropoffLocation != null) {
                Future.delayed(const Duration(milliseconds: 800), () {
                  _fetchAndDrawRoute();
                });
              }
              // Add native markers (after map style loads)
              Future.delayed(const Duration(milliseconds: 800), () {
                _refreshNativeMarkers();
              });
            },
          ),

          // ── Find Rider FAB (top-right) ──
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
                    const Text('🛵', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 4),
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
                      'Bike Route',
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
                        _legendItem('🛵 Rider', const Color(0xFFD93025)),
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
