import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:baato_maps/baato_maps.dart';
// ignore: implementation_imports
import 'package:baato_maps/src/map_core/implementation/baato_map_controller_impl.dart';

/// Represents a point on the map (rider, pickup, dropoff).
class RiderMapPoint {
  final double latitude;
  final double longitude;
  final String label;
  final RiderMapPointType type;

  const RiderMapPoint({
    required this.latitude,
    required this.longitude,
    required this.label,
    this.type = RiderMapPointType.dropoff,
  });
}

enum RiderMapPointType { rider, pickup, dropoff }

/// A reusable Baato map widget that displays:
///   - Rider's current location marker (native Baato symbol)
///   - Pickup (restaurant) and dropoff (customer) markers (native Baato symbols)
///   - Polyline route from rider -> pickup -> dropoff
///   - ETA and distance overlay
///
/// Uses Baato's native [markerManager.addMarker] API so markers are correctly
/// positioned at their lat/lng coordinates and move/scale with the map.
///
/// Supports both single-rider view (with ETA bar) and multi-rider view
/// (showing all online riders on the map with name labels).
///
/// Used in the customer's OrderDetailScreen, the admin dashboard, and
/// the delivery boy's jobs screen.
class RiderMapView extends StatefulWidget {
  /// Current rider location (single-rider mode).
  /// Ignored when [riderLocations] is provided and non-empty.
  final RiderMapPoint riderLocation;

  /// Multiple rider locations (multi-rider mode).
  /// When provided, shows a marker for each rider with their label.
  /// Initial camera centers on the average of all rider coordinates.
  final List<RiderMapPoint>? riderLocations;

  /// Pickup location (restaurant)
  final RiderMapPoint? pickupLocation;

  /// Dropoff location (customer)
  final RiderMapPoint? dropoffLocation;

  /// Estimated time of arrival text (e.g. "5 min away")
  final String? etaText;

  /// Estimated distance text (e.g. "2.3 km")
  final String? distanceText;

  /// Map height (defaults to 250)
  final double height;

  /// Whether to show the ETA overlay bar at the bottom
  final bool showEtaBar;

  /// Whether to draw the route polyline from rider to dropoff.
  /// Uses Baato Directions API internally. Only works in single-rider mode.
  final bool showRoute;

  /// Called when the user taps on the map area.
  /// Used to open a full-screen map view.
  final VoidCallback? onTap;

  const RiderMapView({
    super.key,
    required this.riderLocation,
    this.riderLocations,
    this.pickupLocation,
    this.dropoffLocation,
    this.etaText,
    this.distanceText,
    this.height = 250,
    this.showEtaBar = true,
    this.showRoute = false,
    this.onTap,
  });

  @override
  State<RiderMapView> createState() => _RiderMapViewState();
}

class _RiderMapViewState extends State<RiderMapView> {
  final BaatoMapController _mapController = BaatoMapControllerImpl();
  bool _isMapLoading = true;
  bool _mapReady = false;

  /// Tracks which images have been loaded into the map sprite sheet.
  /// See [_loadMarkerImages] for the actual loading logic.
  final Set<String> _loadedImages = {};

  /// Native Baato markers currently displayed on the map.
  /// Cleared and re-added when locations change.
  final List<Symbol> _currentMarkers = [];
  bool _isRouteLoading = false;
  bool _initialRouteDrawn = false;
  Timer? _routeRefreshDebounce;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(RiderMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_mapReady) return;

    // Compare rider points (handles both single and multi-rider)
    final oldRiderPoints = oldWidget.riderLocations?.isNotEmpty == true
        ? oldWidget.riderLocations!
        : [oldWidget.riderLocation];
    final newRiderPoints = widget.riderLocations?.isNotEmpty == true
        ? widget.riderLocations!
        : [widget.riderLocation];
    final riderChanged = _locationsListsDiffer(oldRiderPoints, newRiderPoints);

    // Compare pickup / dropoff location changes
    final pickupChanged = _pointChanged(oldWidget.pickupLocation, widget.pickupLocation);
    final dropoffChanged = _pointChanged(oldWidget.dropoffLocation, widget.dropoffLocation);

    if (riderChanged || pickupChanged || dropoffChanged) {
      _refreshNativeMarkers();
      // Only redraw the route when the rider moves, not for pickup/dropoff changes
      if (riderChanged) _onRiderLocationChanged();
    }
  }

  /// Compare two nullable RiderMapPoints by lat/lng.
  bool _pointChanged(RiderMapPoint? a, RiderMapPoint? b) {
    if (a == null && b == null) return false;
    if (a == null || b == null) return true;
    return a.latitude != b.latitude ||
        a.longitude != b.longitude ||
        a.label != b.label;
  }

  /// Compare two nullable lists of RiderMapPoint by value (lat/lng/label/type).
  bool _locationsListsDiffer(
    List<RiderMapPoint>? a,
    List<RiderMapPoint>? b,
  ) {
    if (a == null && b == null) return false;
    if (a == null || b == null) return true;
    if (a.length != b.length) return true;
    for (int i = 0; i < a.length; i++) {
      final pa = a[i], pb = b[i];
      if (pa.latitude != pb.latitude ||
          pa.longitude != pb.longitude ||
          pa.label != pb.label ||
          pa.type != pb.type) {
        return true;
      }
    }
    return false;
  }

  @override
  void dispose() {
    _routeRefreshDebounce?.cancel();
    _clearMarkers();
    _clearRoute();
    super.dispose();
  }

  /// Whether the map is showing multiple riders.
  bool get _isMultiRider =>
      widget.riderLocations != null && widget.riderLocations!.isNotEmpty;

  /// All rider points to render (either from list or single).
  List<RiderMapPoint> get _allRiderPoints {
    if (_isMultiRider) return widget.riderLocations!;
    return [widget.riderLocation];
  }

  /// All map points including rider, pickup, and dropoff (if provided).
  /// Used for computing center and zoom so all markers fit on screen.
  List<RiderMapPoint> get _allMapPoints {
    final points = <RiderMapPoint>[..._allRiderPoints];
    if (widget.pickupLocation != null) points.add(widget.pickupLocation!);
    if (widget.dropoffLocation != null) points.add(widget.dropoffLocation!);
    return points;
  }

  /// Compute the center of ALL points (rider, pickup, dropoff) for initial camera.
  BaatoCoordinate _computeCenter() {
    final points = _allMapPoints;
    if (points.isEmpty) return _toCoord(widget.riderLocation);

    double latSum = 0, lngSum = 0;
    for (final p in points) {
      latSum += p.latitude;
      lngSum += p.longitude;
    }
    return BaatoCoordinate(
      latitude: latSum / points.length,
      longitude: lngSum / points.length,
    );
  }

  /// Determine zoom level dynamically based on how spread out all points are.
  /// Wider spread = lower zoom so all markers fit on screen.
  /// Falls back to 14.0 when there's only one point or points are close.
  double _computeZoom() {
    final allPoints = _allMapPoints;
    if (allPoints.isEmpty) return 14.0;
    if (allPoints.length == 1) return 14.0;

    double minLat = allPoints.first.latitude;
    double maxLat = allPoints.first.latitude;
    double minLng = allPoints.first.longitude;
    double maxLng = allPoints.first.longitude;

    for (final p in allPoints) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    final double latDiff = maxLat - minLat;
    final double lngDiff = maxLng - minLng;
    final double maxDiff = latDiff > lngDiff ? latDiff : lngDiff;

    if (maxDiff > 0.5) return 11.0;
    if (maxDiff > 0.1) return 12.0;
    if (maxDiff > 0.05) return 13.0;
    if (maxDiff > 0.01) return 14.0;
    return 15.0;
  }

  /// Clear all native Baato markers from the map.
  Future<void> _clearMarkers() async {
    try {
      await _mapController.markerManager.clearMarkers();
      _currentMarkers.clear();
    } catch (_) {
      // Map might not be initialized yet
    }
  }

  Future<void> _clearRoute() async {
    try {
      await _mapController.routeManager.clearRoute();
    } catch (_) {
      // Map might not be initialized yet
    }
  }

  /// Load the delivery guy image and the default Baato marker image into the
  /// map sprite sheet so they can be used as native marker icons via [iconImage].
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
        debugPrint('[RiderMapView] ✅ Delivery guy image loaded');
      } catch (e) {
        debugPrint('[RiderMapView] ⚠️ Delivery guy image load failed: $e');
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
        debugPrint('[RiderMapView] ✅ Baato marker image loaded');
      } catch (e) {
        debugPrint('[RiderMapView] ⚠️ Baato marker image load failed: $e');
      }
    }
  }

  /// Add all markers (rider, pickup, dropoff) as native Baato symbols.
  /// Clears any existing markers first.
  Future<void> _refreshNativeMarkers() async {
    await _clearMarkers();
    await _loadMarkerImages();

    try {
      // ── Rider marker(s) ──
      for (final point in _allRiderPoints) {
        final sym = await _mapController.markerManager.addMarker(
          BaatoSymbolOption(
            geometry: BaatoCoordinate(
              latitude: point.latitude,
              longitude: point.longitude,
            ),
            iconImage: 'delivery_guy',
            iconSize: 0.7,
            textField: point.label,
            textSize: 10,
            textOffset: const Offset(0, 1.5),
            textColor: '#D93025',
            textHaloColor: '#FFFFFF',
            textHaloWidth: 1.0,
            // Keep rider markers on top
            zIndex: 10,
          ),
        );
        _currentMarkers.add(sym);
      }

      // ── Pickup / Restaurant marker ──
      if (widget.pickupLocation != null) {
        final sym = await _mapController.markerManager.addMarker(
          BaatoSymbolOption(
            geometry: BaatoCoordinate(
              latitude: widget.pickupLocation!.latitude,
              longitude: widget.pickupLocation!.longitude,
            ),
            iconImage: 'baato_marker',
            iconSize: 1.0,
            textField: widget.pickupLocation!.label,
            textSize: 10,
            textOffset: const Offset(0, 1.5),
            textColor: '#1E8E3E',
            textHaloColor: '#FFFFFF',
            textHaloWidth: 1.0,
          ),
        );
        _currentMarkers.add(sym);
      }

      // ── Dropoff / Customer marker ──
      if (widget.dropoffLocation != null) {
        final sym = await _mapController.markerManager.addMarker(
          BaatoSymbolOption(
            geometry: BaatoCoordinate(
              latitude: widget.dropoffLocation!.latitude,
              longitude: widget.dropoffLocation!.longitude,
            ),
            iconImage: 'baato_marker',
            iconSize: 1.0,
            textField: widget.dropoffLocation!.label,
            textSize: 10,
            textOffset: const Offset(0, 1.5),
            textColor: '#BB0018',
            textHaloColor: '#FFFFFF',
            textHaloWidth: 1.0,
          ),
        );
        _currentMarkers.add(sym);
      }

      debugPrint('[RiderMapView] ✅ Added ${_currentMarkers.length} native markers');
    } catch (e) {
      debugPrint('[RiderMapView] ❌ Native marker error: $e');
    }
  }

  /// Fetch the route from rider to dropoff via Baato Directions API
  /// and draw it on the map.
  Future<void> _fetchAndDrawRoute() async {
    if (_isRouteLoading || _isMultiRider || !widget.showRoute) return;
    if (widget.dropoffLocation == null) return;

    // Small delay to ensure the map style is fully loaded before drawing route layers.
    // MapLibre needs the style loaded before we can add GeoJSON sources/layers.
    if (!_initialRouteDrawn) {
      await Future.delayed(const Duration(milliseconds: 500));
    }

    try {
      _isRouteLoading = true;

      debugPrint('[RiderMapView] 🗺️ Fetching route from '
          '(${widget.riderLocation.latitude}, ${widget.riderLocation.longitude}) '
          'to (${widget.dropoffLocation!.latitude}, ${widget.dropoffLocation!.longitude})');

      final riderCoord = BaatoCoordinate(
        latitude: widget.riderLocation.latitude,
        longitude: widget.riderLocation.longitude,
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

      final routeResult = await Baato.api.direction.getRoutes(
        startCoordinate: riderCoord,
        endCoordinate: dropoffCoord,
        midCoordinates: midCoords,
        mode: BaatoDirectionMode.bike,
        alternatives: true,  // Get multiple route options
        decodePolyline: true,
      );

      // Pick the SHORTEST route by distance (not the default fastest)
      // The API may return multiple alternatives — we sort by distanceInMeters
      // and use only the shortest one for optimal delivery routing.
      final BaatoRouteResponse shortestRoute;
      if (routeResult.data != null && routeResult.data!.length > 1) {
        routeResult.data!.sort((a, b) =>
          (a.distanceInMeters ?? double.infinity)
              .compareTo(b.distanceInMeters ?? double.infinity));
        shortestRoute = BaatoRouteResponse(
          routeResult.timestamp,
          routeResult.status,
          routeResult.message,
          [routeResult.data!.first],
        );
        debugPrint('[RiderMapView] ✅ Selected shortest route: '
            '${routeResult.data!.first.distanceInMeters?.toStringAsFixed(0)}m '
            '(from ${routeResult.data!.length} alternatives)');
      } else {
        shortestRoute = routeResult;
      }

      debugPrint('[RiderMapView] ✅ Route fetched, drawing shortest route...');

      // Draw the shortest route — routeManager replaces the previous route
      await _mapController.routeManager.drawRouteFromResponse(
        shortestRoute,
        lineLayerProperties: BaatoLineLayerProperties(
          lineColor: '#FF6B35',
          lineWidth: 4.0,
          lineOpacity: 0.85,
          lineBlur: 1.5,
          lineCap: 'round',
          lineJoin: 'round',
        ),
      );

      debugPrint('[RiderMapView] ✅ Route drawn on map');
      _initialRouteDrawn = true;
    } catch (e) {
      debugPrint('[RiderMapView] ❌ Route fetch/draw error: $e');
    } finally {
      _isRouteLoading = false;
      if (mounted) setState(() {});
    }
  }

  /// Redraw the route when rider location changes.
  /// Calls the API directly if not already loading; retries after 500ms if busy.
  void _onRiderLocationChanged() {
    if (_isMultiRider || !widget.showRoute || widget.dropoffLocation == null) return;

    _routeRefreshDebounce?.cancel();
    if (_isRouteLoading) {
      // API still busy from a previous call — retry after a short delay
      _routeRefreshDebounce = Timer(const Duration(milliseconds: 500), () {
        _onRiderLocationChanged();
      });
      return;
    }
    _fetchAndDrawRoute();
  }

  BaatoCoordinate _toCoord(RiderMapPoint point) {
    return BaatoCoordinate(
      latitude: point.latitude,
      longitude: point.longitude,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: Stack(
        children: [
          // -- Baato Map --
          // Native markers are rendered directly on the map via
          // markerManager.addMarker() so they correctly track lat/lng.
          BaatoMap(
            controller: _mapController,
            style: BaatoMapStyle.breeze,
            initialPosition: _computeCenter(),
            initialZoom: _computeZoom(),
            myLocationEnabled: false,
            onMapCreated: (controller) {
              setState(() => _isMapLoading = false);
              _mapReady = true;
              // Draw the route independently
              if (widget.showRoute && widget.dropoffLocation != null) {
                Future.delayed(const Duration(milliseconds: 800), () {
                  _fetchAndDrawRoute();
                });
              }
              // Add native markers (slightly later so the map style finishes loading)
              Future.delayed(const Duration(milliseconds: 800), () {
                _refreshNativeMarkers();
              });
            },
          ),

          // -- Transparent tap overlay (sits on top of the map) --
          if (widget.onTap != null)
            Positioned.fill(
              child: GestureDetector(
                onTap: widget.onTap,
                child: Container(color: Colors.transparent),
              ),
            ),

          // -- Loading skeleton --
          if (_isMapLoading)
            Container(
              color: Colors.grey.shade100,
              child: const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),

          // -- ETA overlay bar (single-rider mode only) --
          if (!_isMultiRider &&
              widget.showEtaBar &&
              (widget.etaText != null || widget.distanceText != null))
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.95),
                  border: Border(
                    top: BorderSide(color: Colors.grey.shade200),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.delivery_dining, size: 18, color: Color(0xFFBB0018)),
                    const SizedBox(width: 8),
                    const Text('🛵', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 4),
                    if (widget.etaText != null)
                      Text(
                        widget.etaText!,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1C1C),
                        ),
                      ),
                    if (widget.etaText != null && widget.distanceText != null) ...[
                      const SizedBox(width: 8),
                      Container(width: 1, height: 12, color: Colors.grey.shade300),
                      const SizedBox(width: 8),
                    ],
                    if (widget.distanceText != null)
                      Text(
                        widget.distanceText!,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    const Spacer(),
                    const Icon(Icons.navigation, size: 16, color: Color(0xFF1967D2)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
