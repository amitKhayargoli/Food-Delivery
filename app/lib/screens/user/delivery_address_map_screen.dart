import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:baato_maps/baato_maps.dart';
// ignore: implementation_imports
import 'package:baato_maps/src/map_core/implementation/baato_map_controller_impl.dart';
import 'selected_delivery_location.dart';

class DeliveryAddressMapScreen extends StatefulWidget {
  const DeliveryAddressMapScreen({super.key});

  @override
  State<DeliveryAddressMapScreen> createState() =>
      _DeliveryAddressMapScreenState();
}

class _DeliveryAddressMapScreenState extends State<DeliveryAddressMapScreen> {
  static const Color _primaryColor = Color(0xFFF5222D);

  final BaatoMapController _controller = BaatoMapControllerImpl();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  BaatoCoordinate _selectedCoordinate = BaatoCoordinate(
    latitude: 27.7172,
    longitude: 85.3240,
  );
  String _currentAddress = 'Search or tap the map to pin a location';
  bool _isLoadingAddress = false;
  bool _hasSelected = false;

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

    // Update the marker on the map
    await _addMarkerAt(coordinate);

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

  void _onConfirm() {
    Navigator.pop(
      context,
      SelectedDeliveryLocation(
        address: _currentAddress,
        latitude: _selectedCoordinate.latitude,
        longitude: _selectedCoordinate.longitude,
      ),
    );
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
              initialPosition: BaatoCoordinate(
                latitude: 27.7172,
                longitude: 85.3240,
              ),
              initialZoom: 15.0,
              myLocationEnabled: true,
              onMapCreated: (controller) {
                _addMarkerAt(_selectedCoordinate);
              },
              onMapClick: (point, coordinate, features) {
                _onMapTapped(coordinate);
              },
            ),
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

          // ── Center pin (shown until user taps or searches) ──
          if (!_hasSelected)
            IgnorePointer(
              child: Align(
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFCEAE0),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Tap on the map to pin a location',
                        style: TextStyle(
                          color: Color(0xFF6B3A22),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    CustomPaint(
                      size: const Size(12, 8),
                      painter: _TrianglePainter(color: const Color(0xFFFCEAE0)),
                    ),
                    const Icon(Icons.location_on, color: _primaryColor, size: 34),
                    const SizedBox(height: 34),
                  ],
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
                          borderRadius: BorderRadius.circular(28),
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

  Future<void> _addMarkerAt(BaatoCoordinate coordinate) async {
    try {
      await _controller.markerManager.clearMarkers();
      await _controller.markerManager.addMarker(
        BaatoSymbolOption(
          geometry: coordinate,
          textField: 'Delivery Location',
          iconSize: 0.35,
        ),
      );
    } catch (_) {
      // marker ops best-effort until map is fully loaded
    }
  }
}

class _TrianglePainter extends CustomPainter {
  final Color color;

  _TrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(0, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width / 2, size.height);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
