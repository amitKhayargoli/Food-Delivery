import 'package:flutter/material.dart';
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
///   - Rider's current location marker
///   - Pickup (restaurant) and dropoff (customer) markers
///   - Polyline route from rider -> pickup -> dropoff
///   - ETA and distance overlay
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
  });

  @override
  State<RiderMapView> createState() => _RiderMapViewState();
}

class _RiderMapViewState extends State<RiderMapView> {
  final BaatoMapController _mapController = BaatoMapControllerImpl();
  bool _isMapLoading = true;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didUpdateWidget(RiderMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_mapReady) return;

    // Compute the full point list for old and new widget, then compare by value.
    // This handles both multi-rider and single-rider mode uniformly.
    final List<RiderMapPoint> oldPoints = oldWidget.riderLocations?.isNotEmpty == true
        ? oldWidget.riderLocations!
        : [oldWidget.riderLocation];
    final List<RiderMapPoint> newPoints = widget.riderLocations?.isNotEmpty == true
        ? widget.riderLocations!
        : [widget.riderLocation];

    if (_locationsListsDiffer(oldPoints, newPoints)) {
      _addRiderMarkers();
    }
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
    _clearMarkers();
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

  /// Compute the average coordinate from all rider points for initial camera.
  BaatoCoordinate _computeCenter() {
    final points = _allRiderPoints;
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

  /// Determine initial zoom level: tighter zoom for single, wider for multi.
  double _computeZoom() {
    if (_isMultiRider) return 13.0;
    return 14.0;
  }

  void _clearMarkers() {
    try {
      _mapController.markerManager.clearMarkers();
    } catch (_) {
      // Map might not be initialized yet
    }
  }

  Future<void> _addRiderMarkers() async {
    final points = _allRiderPoints;
    if (points.isEmpty) return;

    try {
      _clearMarkers();

      for (final point in points) {
        await _mapController.markerManager.addMarker(
          BaatoSymbolOption(
            geometry: _toCoord(point),
            iconSize: 1.0,
            iconImage: 'baato_marker',
            iconColor: point.type == RiderMapPointType.rider
                ? '#1967D2'
                : '#BB0018',
            textField: point.label,
            textSize: 11.0,
            textOffset: const Offset(0, 2),
            textColor: '#1A1C1C',
            textHaloColor: '#FFFFFF',
            textHaloWidth: 1.5,
          ),
        );
      }
    } catch (e) {
      debugPrint('[RiderMapView] Error adding markers: $e');
    }
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
          BaatoMap(
            controller: _mapController,
            style: BaatoMapStyle.breeze,
            initialPosition: _computeCenter(),
            initialZoom: _computeZoom(),
            myLocationEnabled: false,
            onMapCreated: (controller) {
              setState(() => _isMapLoading = false);
              _mapReady = true;
              _addRiderMarkers();
            },
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
