import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:baato_maps/baato_maps.dart';
// ignore: implementation_imports
import 'package:baato_maps/src/map_core/implementation/baato_map_controller_impl.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/services/delivery_location_service.dart';
import '../../injection_container.dart' as di;
import '../../models/saved_address.dart';
import '../../widgets/map_skeleton.dart';
import '../../widgets/save_address_dialog.dart';
import 'selected_delivery_location.dart';

class DeliveryAddressMapScreen extends StatefulWidget {
  final SelectedDeliveryLocation? initialLocation;

  const DeliveryAddressMapScreen({super.key, this.initialLocation});

  @override
  State<DeliveryAddressMapScreen> createState() =>
      _DeliveryAddressMapScreenState();
}

class _DeliveryAddressMapScreenState extends State<DeliveryAddressMapScreen>
    with TickerProviderStateMixin {
  static const Color _primaryColor = Color(0xFFF5222D);

  final BaatoMapController _controller = BaatoMapControllerImpl();
  final DeliveryLocationService _locationService =
      di.sl<DeliveryLocationService>();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  BaatoCoordinate _selectedCoordinate = BaatoCoordinate(
    latitude: 27.7172,
    longitude: 85.3240,
  );
  String _currentAddress = 'Search or tap the map to pin a location';
  bool _isLoadingAddress = false;
  bool _hasSelected = false;
  bool _isMapLoading = true;
  BaatoCoordinate? _gpsCoordinate;
  Timer? _mapReadyTimer;
  late final DateTime _screenOpenedAt;
  late final AnimationController _pinBounceController;
  late final AnimationController _shimmerController;
  late final AnimationController _locationPulseController;

  @override
  void initState() {
    super.initState();
    _screenOpenedAt = DateTime.now();

    // Restore previously selected location if provided
    if (widget.initialLocation != null) {
      _selectedCoordinate = BaatoCoordinate(
        latitude: widget.initialLocation!.latitude,
        longitude: widget.initialLocation!.longitude,
      );
      _currentAddress = widget.initialLocation!.address;
      _hasSelected = true;
    }

    _pinBounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _locationPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) => _initCurrentLocation());
  }

  // Search state
  List<BaatoSearchPlace> _searchResults = [];
  bool _isSearching = false;
  bool _showSearchResults = false;
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchDebounce?.cancel();
    _pinBounceController.dispose();
    _shimmerController.dispose();
    _locationPulseController.dispose();
    _mapReadyTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _showSearchResults = false;
        _isSearching = false;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      _performSearch(query.trim());
    });
  }

  Future<void> _performSearch(String query) async {
    debugPrint('[BAATO SEARCH] Query: "$query" (coordinate: ${_selectedCoordinate.latitude}, ${_selectedCoordinate.longitude})');
    setState(() => _isSearching = true);
    try {
      final stopwatch = Stopwatch()..start();
      final response = await Baato.api.place.search(
        query,
        currentCoordinate: _selectedCoordinate,
        limit: 7,
      );
      stopwatch.stop();
      final results = response.data ?? [];
      debugPrint('[BAATO SEARCH] ✓ ${stopwatch.elapsedMilliseconds}ms — ${results.length} results');
      for (final place in results) {
        debugPrint('  - [${place.placeId}] ${place.name} — ${place.address}');
      }
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _showSearchResults = _searchResults.isNotEmpty;
        _isSearching = false;
      });
    } catch (e) {
      debugPrint('[BAATO SEARCH] ✗ ERROR: $e');
      if (!mounted) return;
      setState(() {
        _searchResults = [];
        _showSearchResults = false;
        _isSearching = false;
      });
    }
  }

  Future<void> _onSearchResultTapped(BaatoSearchPlace place) async {
    debugPrint('[BAATO DETAIL] Fetching details for placeId=${place.placeId}, name="${place.name}"');
    setState(() {
      _showSearchResults = false;
      _isSearching = true;
    });
    _searchController.text = place.name;
    _searchFocusNode.unfocus();

    try {
      final stopwatch = Stopwatch()..start();
      final detailResponse = await Baato.api.place.getDetail(place.placeId);
      stopwatch.stop();
      if (!mounted) return;
      final detailData = detailResponse.data;
      debugPrint('[BAATO DETAIL] ✓ ${stopwatch.elapsedMilliseconds}ms — data length: ${detailData?.length ?? 0}');
      if (detailData != null && detailData.isNotEmpty) {
        final placeDetail = detailData.first;
        debugPrint('[BAATO DETAIL]   centroid: (${placeDetail.centroid.latitude}, ${placeDetail.centroid.longitude})');
        debugPrint('[BAATO DETAIL]   name: "${placeDetail.name}", address: "${placeDetail.address}"');
        _onPlaceSelectedFromSearch(placeDetail);
        setState(() => _isSearching = false);
      } else {
        debugPrint('[BAATO DETAIL] ⚠ No detail data returned');
        if (mounted) setState(() => _isSearching = false);
      }
    } catch (e) {
      debugPrint('[BAATO DETAIL] ✗ ERROR: $e');
      if (!mounted) return;
      setState(() => _isSearching = false);
    }
  }

  // ──────────────────────────────────────────────
  // Helpers
  // ──────────────────────────────────────────────

  Future<void> _updateLocation(BaatoCoordinate coordinate,
      {String? label}) async {
    setState(() {
      _selectedCoordinate = coordinate;
      _isLoadingAddress = true;
    });

    String address = label ??
        '${coordinate.latitude.toStringAsFixed(5)}, ${coordinate.longitude.toStringAsFixed(5)}';

    try {
      debugPrint('[BAATO REVERSE] Reverse geocoding: (${coordinate.latitude}, ${coordinate.longitude})');
      final stopwatch = Stopwatch()..start();
      final response =
          await Baato.api.place.reverseGeocode(coordinate, limit: 1);
      stopwatch.stop();
      final places = response.data;
      debugPrint('[BAATO REVERSE] ✓ ${stopwatch.elapsedMilliseconds}ms — places: ${places?.length ?? 0}');
      if (places != null && places.isNotEmpty) {
        final first = places.first;
        debugPrint('[BAATO REVERSE]   name="${first.name}", address="${first.address}"');
        if (first.name.isNotEmpty) {
          address = first.name;
        } else if (first.address.isNotEmpty) {
          address = first.address;
        }
      } else {
        debugPrint('[BAATO REVERSE] ⚠ No reverse geocode results');
      }
    } catch (e) {
      debugPrint('[BAATO REVERSE] ✗ ERROR: $e');
      // fall back to coordinate string
    }

    if (mounted) {
      setState(() {
        _currentAddress = address;
        _isLoadingAddress = false;
        _hasSelected = true;
      });
      // Subtle pulse bounce: scale 1.0 → 1.15 → 1.0
      _pinBounceController
        ..stop()
        ..value = 0.0;
      _pinBounceController.forward().then((_) {
        if (mounted) _pinBounceController.reverse();
      });
    }
  }

  void _onMapTapped(BaatoCoordinate coordinate) {
    _searchController.clear();
    setState(() => _showSearchResults = false);
    _controller.cameraManager.moveTo(coordinate, zoom: 15.0, animate: true);
    _updateLocation(coordinate);
  }

  void _onPlaceSelectedFromSearch(BaatoPlace place) {
    final centroid = place.centroid;
    final coord = BaatoCoordinate(
      latitude: centroid.latitude,
      longitude: centroid.longitude,
    );
    _controller.cameraManager.moveTo(coord, zoom: 16.0, animate: true);
    _updateLocation(
        coord, label: place.name.isNotEmpty ? place.name : place.address);
  }

  Future<void> _onConfirm() async {
    final location = SelectedDeliveryLocation(
      address: _currentAddress,
      latitude: _selectedCoordinate.latitude,
      longitude: _selectedCoordinate.longitude,
    );

    // Show save dialog
    final result = await showSaveAddressDialog(
      context,
      currentAddress: _currentAddress,
      latitude: _selectedCoordinate.latitude,
      longitude: _selectedCoordinate.longitude,
      existingAddresses: _locationService.loadSavedAddresses(),
    );

    // Save as named address if the user chose to
    if (result != null && result.didSave && mounted) {
      _locationService.saveSavedAddress(
        SavedAddress(
          label: result.label,
          address: _currentAddress,
          latitude: _selectedCoordinate.latitude,
          longitude: _selectedCoordinate.longitude,
          icon: SavedAddress.iconForLabel(result.label),
        ),
      );
    }

    if (mounted) {
      Navigator.pop(context, location);
    }
  }

  // ──────────────────────────────────────────────
  // Current Location Initialisation
  // ──────────────────────────────────────────────

  Future<void> _initCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (!mounted) return;

      final coord = BaatoCoordinate(
        latitude: position.latitude,
        longitude: position.longitude,
      );
      _gpsCoordinate = coord;

      if (_hasSelected) return;

      _controller.cameraManager.moveTo(coord, zoom: 15.0, animate: true);
      _updateLocation(coord);
    } catch (_) {
      // GPS unavailable — user can still tap the map to select a location
    }
  }

  void _goToGpsLocation() {
    if (_gpsCoordinate == null) return;
    _controller.cameraManager.moveTo(_gpsCoordinate!, zoom: 15.0, animate: true);
    _updateLocation(_gpsCoordinate!);
  }

  // ──────────────────────────────────────────────
  // Web fallback
  // ──────────────────────────────────────────────

  Widget _buildWebFallback(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: InkWell(
            onTap: () => Navigator.pop(context),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: const Icon(Icons.arrow_back, color: Colors.black, size: 20),
            ),
          ),
        ),
        title: const Text(
          'Delivery Address',
          style: TextStyle(
            color: Colors.black,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.map_outlined, size: 64, color: Colors.black54),
            const SizedBox(height: 16),
            const Text(
              'Map selection is not available on web yet.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Text(
              'Use the default delivery address to continue.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _onConfirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryColor,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Use Default Address',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Build
  // ──────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return _buildWebFallback(context);

    final mapHeight = MediaQuery.of(context).size.height;
    final mapWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: InkWell(
            onTap: () => Navigator.pop(context),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: const Icon(Icons.arrow_back, color: Colors.black, size: 20),
            ),
          ),
        ),
        title: const Text(
          'Delivery Address',
          style: TextStyle(
            color: Colors.black,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Stack(
        children: [
          // ── Baato Map ──
          SizedBox(
            height: mapHeight,
            width: mapWidth,
            child: BaatoMap(
              controller: _controller,
              style: BaatoMapStyle.breeze,
              initialPosition: _selectedCoordinate,
              initialZoom: 15.0,
              myLocationEnabled: true,
              onMapCreated: (controller) {
                // Adaptive skeleton timing:
                // The longer it took onMapCreated to fire, the slower the
                // connection — keep skeleton visible proportionally longer.
                if (mounted) {
                  final elapsed =
                      DateTime.now().difference(_screenOpenedAt).inMilliseconds;
                  // buffer = clamp(elapsed * 0.5, 800ms, 2500ms)
                  final buffer = (elapsed * 0.5).round().clamp(800, 2500);
                  _mapReadyTimer = Timer(Duration(milliseconds: buffer), () {
                    if (mounted) {
                      _shimmerController.stop();
                      setState(() => _isMapLoading = false);
                    }
                  });
                }
              },
              onMapClick: (point, coordinate, features) {
                _onMapTapped(coordinate);
              },
            ),
          ),

          // ── Pulsating Map Loading Skeleton ──
          AnimatedOpacity(
            opacity: _isMapLoading ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 800),
            child: _isMapLoading
                ? IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _shimmerController,
                      builder: (context, _) {
                        final value = _shimmerController.value;
                        return SizedBox(
                          height: mapHeight,
                          width: mapWidth,
                          child: CustomPaint(
                            painter: MapSkeletonPainter(
                              shimmerValue: value,
                            ),
                          ),
                        );
                      },
                    ),
                  )
                : const SizedBox.shrink(),
          ),

          // ── Custom Search Bar ──
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Search text field
                Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    onChanged: _onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Search for a place...',
                      hintStyle: TextStyle(
                        color: Colors.grey.shade400,
                        fontSize: 15,
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        color: Colors.grey.shade500,
                        size: 22,
                      ),
                      suffixIcon: _isSearching
                          ? Padding(
                              padding: const EdgeInsets.all(14),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _primaryColor,
                                ),
                              ),
                            )
                          : (_searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: Icon(
                                    Icons.clear,
                                    color: Colors.grey.shade500,
                                    size: 20,
                                  ),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {
                                      _showSearchResults = false;
                                      _searchResults = [];
                                    });
                                  },
                                )
                              : null),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: Color(0xFFF5222D),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),

                // Search results dropdown
                if (_showSearchResults)
                  Container(
                    constraints: const BoxConstraints(maxHeight: 280),
                    margin: const EdgeInsets.only(top: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: _searchResults.length,
                        itemBuilder: (context, index) {
                          final place = _searchResults[index];
                          return InkWell(
                            onTap: () => _onSearchResultTapped(place),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFFF1F0),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      Icons.location_on_outlined,
                                      size: 18,
                                      color: Color(0xFFF5222D),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          place.name,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF1A1A1A),
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (place.address.isNotEmpty)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 2),
                                            child: Text(
                                              place.address,
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: Colors.grey.shade600,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  const Icon(
                                    Icons.chevron_right,
                                    size: 20,
                                    color: Color(0xFFBFBFBF),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                // No results message
                if (!_isSearching &&
                    _searchController.text.isNotEmpty &&
                    !_showSearchResults &&
                    _searchResults.isEmpty &&
                    _searchFocusNode.hasFocus)
                  Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.search_off,
                            size: 20, color: Colors.grey.shade400),
                        const SizedBox(width: 8),
                        Text(
                          'No places found. Try a different search.',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // ── Pulsing current location ring (Google Maps style blue dot) ──
          // Expands & contracts in a slow 2s cycle behind the selection pin.
          IgnorePointer(
            child: Align(
              alignment: Alignment.center,
              child: AnimatedBuilder(
                animation: _locationPulseController,
                builder: (context, _) {
                  final pulse = _locationPulseController.value;
                  return Container(
                    width: 80 + pulse * 40,
                    height: 80 + pulse * 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.blue
                          .withValues(alpha: 0.12 * (1.0 - pulse)),
                      border: Border.all(
                        color: Colors.blue
                            .withValues(alpha: 0.25 * (1.0 - pulse)),
                        width: 2.0,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // ── Center pin (always visible — bounce animates on tap) ──
          IgnorePointer(
            child: Align(
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Pin icon with subtle bounce animation (pulse: 1.0→1.15→1.0)
                  AnimatedBuilder(
                    animation: _pinBounceController,
                    builder: (context, child) {
                      final scale = 1.0 + 0.15 * _pinBounceController.value;
                      return Transform.scale(
                        scale: scale,
                        child: child,
                      );
                    },
                    child: const Icon(
                      Icons.location_on,
                      color: _primaryColor,
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: 34),
                ],
              ),
            ),
          ),

          // ── GPS re-centre FAB (appears when pinned location ≠ GPS location) ──
          if (_gpsCoordinate != null &&
              (_selectedCoordinate.latitude != _gpsCoordinate!.latitude ||
                  _selectedCoordinate.longitude !=
                      _gpsCoordinate!.longitude) &&
              !_isMapLoading)
            Positioned(
              right: 16,
              bottom: MediaQuery.of(context).size.height * 0.35,
              child: Material(
                elevation: 4,
                shape: const CircleBorder(),
                color: Colors.white,
                child: InkWell(
                  onTap: _goToGpsLocation,
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.my_location,
                      color: Color(0xFF1A73E8),
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),

          // ── Bottom Panel ──
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          shape: BoxShape.circle,
                        ),
                        child: _isLoadingAddress
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: _primaryColor,
                                ),
                              )
                            : const Icon(
                                Icons.location_on_outlined,
                                color: Colors.grey,
                                size: 24,
                              ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Address',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _currentAddress,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: _hasSelected ? _onConfirm : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryColor,
                        disabledBackgroundColor: Colors.grey.shade300,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        _hasSelected
                            ? 'Confirm Pin Location'
                            : 'Select a Location First',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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

}
