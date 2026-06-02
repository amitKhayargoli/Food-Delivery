import 'dart:async';
import 'package:flutter/material.dart';
import 'package:baato_maps/baato_maps.dart';
// ignore: implementation_imports
import 'package:baato_maps/src/map_core/implementation/baato_map_controller_impl.dart';
import 'selected_delivery_location.dart';

// ──────────────────────────────────────────────
// Saved Address Model
// ──────────────────────────────────────────────

class _SavedAddress {
  final String label;
  final String address;
  final double latitude;
  final double longitude;
  final IconData icon;

  const _SavedAddress({
    required this.label,
    required this.address,
    required this.latitude,
    required this.longitude,
    this.icon = Icons.home_outlined,
  });
}

const List<_SavedAddress> _mockSavedAddresses = [
  _SavedAddress(
    label: 'Home',
    address: 'Lakila, Bhaktapur',
    latitude: 27.6760,
    longitude: 85.4270,
    icon: Icons.home_outlined,
  ),
  _SavedAddress(
    label: 'Work',
    address: 'Byasi, Bhaktapur',
    latitude: 27.6833,
    longitude: 85.4376,
    icon: Icons.work_outline,
  ),
];

// ──────────────────────────────────────────────
// Constants
// ──────────────────────────────────────────────

const Color _primaryRed = Color(0xFFF5222D);
const Color _screenBg = Color(0xFFFBF9F9);
const Color _greyBorder = Color(0xFFE8E8E8);
const Color _grey11 = Color(0xFF1B1C1C);
const Color _addressRed = Color(0xFF5D3F3C);
const Color _grey96 = Color(0xFFF5F3F3);
const Color _grey88 = Color(0xFFE2DFDE);
const double _mapHeight = 353.0;

// ──────────────────────────────────────────────
// Screen
// ──────────────────────────────────────────────

class SelectAddressScreen extends StatefulWidget {
  const SelectAddressScreen({super.key});

  @override
  State<SelectAddressScreen> createState() => _SelectAddressScreenState();
}

class _SelectAddressScreenState extends State<SelectAddressScreen> {
  final BaatoMapController _mapController = BaatoMapControllerImpl();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  BaatoCoordinate _selectedCoordinate =
      BaatoCoordinate(latitude: 27.7172, longitude: 85.3240);
  String _currentAddress = '';
  bool _isSearching = false;
  bool _showSearchResults = false;
  bool _hasSelected = false;
  int? _selectedSavedIndex;

  List<BaatoSearchPlace> _searchResults = [];
  Timer? _searchDebounce;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // ── Search Handlers ──

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
    setState(() => _isSearching = true);
    try {
      final response = await Baato.api.place.search(
        query,
        currentCoordinate: _selectedCoordinate,
        limit: 7,
      );
      final results = response.data ?? [];
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _showSearchResults = results.isNotEmpty;
        _isSearching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searchResults = [];
        _showSearchResults = false;
        _isSearching = false;
      });
    }
  }

  Future<void> _onSearchResultTapped(BaatoSearchPlace place) async {
    setState(() {
      _showSearchResults = false;
      _isSearching = true;
      _selectedSavedIndex = null;
    });
    _searchController.text = place.name;
    _searchFocusNode.unfocus();

    try {
      final detailResponse = await Baato.api.place.getDetail(place.placeId);
      if (!mounted) return;
      final detailData = detailResponse.data;
      if (detailData != null && detailData.isNotEmpty) {
        final placeDetail = detailData.first;
        _onPlaceSelected(
          BaatoCoordinate(
            latitude: placeDetail.centroid.latitude,
            longitude: placeDetail.centroid.longitude,
          ),
          label: placeDetail.name.isNotEmpty
              ? placeDetail.name
              : placeDetail.address,
        );
      }
      if (mounted) setState(() => _isSearching = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSearching = false);
    }
  }

  // ── Map Interaction ──

  void _onMapTapped(BaatoCoordinate coordinate) {
    _searchController.clear();
    setState(() {
      _showSearchResults = false;
      _selectedSavedIndex = null;
    });
    _mapController.cameraManager.moveTo(coordinate, zoom: 15.0, animate: true);
    _updateLocation(coordinate);
  }

  void _onPlaceSelected(BaatoCoordinate coordinate, {String? label}) {
    _mapController.cameraManager.moveTo(coordinate, zoom: 16.0, animate: true);
    _updateLocation(coordinate, label: label);
  }

  // ── Saved Address ──

  void _onSavedAddressTapped(int index) {
    final addr = _mockSavedAddresses[index];
    setState(() {
      _selectedSavedIndex = index;
      _showSearchResults = false;
    });
    _searchController.clear();
    _searchFocusNode.unfocus();
    final coord = BaatoCoordinate(
      latitude: addr.latitude,
      longitude: addr.longitude,
    );
    _mapController.cameraManager.moveTo(coord, zoom: 16.0, animate: true);

    // Reverse geocode the saved address to get a proper name
    _updateLocation(coord, label: '${addr.label}, ${addr.address}');
  }

  // ── Use Current Location ──

  Future<void> _onUseCurrentLocation() async {
    setState(() {
      _selectedSavedIndex = null;
    });
    _searchController.clear();
    _searchFocusNode.unfocus();

    // Use the map's current center coordinate as current location proxy.
    // The map has myLocationEnabled: true so it already shows the blue dot.
    final coord = _selectedCoordinate;
    _onMapTapped(coord);
  }

  // ── Location Update ──

  Future<void> _updateLocation(BaatoCoordinate coordinate,
      {String? label}) async {
    setState(() {
      _selectedCoordinate = coordinate;
    });

    String address = label ??
        '${coordinate.latitude.toStringAsFixed(5)}, ${coordinate.longitude.toStringAsFixed(5)}';

    await _addMarkerAt(coordinate);

    // Only reverse-geocode if no label was provided
    if (label == null) {
      try {
        final response =
            await Baato.api.place.reverseGeocode(coordinate, limit: 1);
        final places = response.data;
        if (places != null && places.isNotEmpty) {
          final first = places.first;
          if (first.name.isNotEmpty) {
            address = first.name;
          } else if (first.address.isNotEmpty) {
            address = first.address;
          }
        }
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _currentAddress = address;
        _hasSelected = true;
      });
    }
  }

  Future<void> _addMarkerAt(BaatoCoordinate coordinate) async {
    try {
      await _mapController.markerManager.clearMarkers();
      await _mapController.markerManager.addMarker(
        BaatoSymbolOption(
          geometry: coordinate,
          textField: 'Delivery Location',
          iconSize: 0.35,
        ),
      );
    } catch (_) {}
  }

  // ── Confirm ──

  void _onDeliverHere() {
    if (!_hasSelected) return;
    Navigator.pop(
      context,
      SelectedDeliveryLocation(
        address: _currentAddress,
        latitude: _selectedCoordinate.latitude,
        longitude: _selectedCoordinate.longitude,
      ),
    );
  }

  // ══════════════════════════════════════════════
  // Build
  // ══════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _screenBg,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          // ── Map (353px) ──
          SizedBox(
            width: double.infinity,
            height: _mapHeight,
            child: BaatoMap(
              controller: _mapController,
              style: BaatoMapStyle.breeze,
              initialPosition: _selectedCoordinate,
              initialZoom: 15.0,
              myLocationEnabled: true,
              onMapCreated: (_) {
                _addMarkerAt(_selectedCoordinate);
              },
              onMapClick: (point, coordinate, features) {
                _onMapTapped(coordinate);
              },
            ),
          ),

          // ── Scrollable Content Below Map ──
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Search Card ──
                  _buildSearchCard(),

                  // ── Search Results Dropdown ──
                  if (_showSearchResults) _buildSearchResultsDropdown(),

                  // ── No Results Message ──
                  if (!_isSearching &&
                      _searchController.text.isNotEmpty &&
                      !_showSearchResults &&
                      _searchResults.isEmpty &&
                      _searchFocusNode.hasFocus)
                    _buildNoResultsMessage(),

                  const SizedBox(height: 16),

                  // ── Use Current Location ──
                  _buildUseCurrentLocation(),

                  const SizedBox(height: 24),

                  // ── Saved Addresses ──
                  _buildSavedAddresses(),
                ],
              ),
            ),
          ),
        ],
      ),

      // ── Bottom Bar: Deliver Here ──
      bottomSheet: _buildBottomBar(),
    );
  }

  // ══════════════════════════════════════════════
  // App Bar
  // ══════════════════════════════════════════════

  PreferredSizeWidget _buildAppBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(56),
      child: Container(
        decoration: const BoxDecoration(
          color: _screenBg,
          boxShadow: [
            BoxShadow(
              color: Color(0x0C000000),
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
          ],
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () async {
                    if (context.mounted) Navigator.maybePop(context);
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.arrow_back,
                      size: 24,
                      color: Colors.black,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Select Address',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 18,
                    
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════
  // Search Card
  // ══════════════════════════════════════════════

  Widget _buildSearchCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(4),
      decoration: ShapeDecoration(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          side: const BorderSide(width: 1, color: _greyBorder),
          borderRadius: BorderRadius.circular(12),
        ),
        shadows: const [
          BoxShadow(
            color: Color(0x0C000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        onChanged: _onSearchChanged,
        decoration: InputDecoration(
          hintText: 'Search for your location',
          hintStyle: const TextStyle(
            color: Color(0xFF6B7280),
            fontSize: 14,
            
            fontWeight: FontWeight.w400,
          ),
          prefixIcon: const Icon(
            Icons.search,
            size: 22,
            color: Color(0xFF6B7280),
          ),
          suffixIcon: _isSearching
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _primaryRed,
                    ),
                  ),
                )
              : (_searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 20,
                          color: Color(0xFF6B7280)),
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
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _primaryRed, width: 1.5),
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════
  // Search Results Dropdown
  // ══════════════════════════════════════════════

  Widget _buildSearchResultsDropdown() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 280),
      margin: const EdgeInsets.only(top: 8),
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
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _searchResults.length,
          itemBuilder: (context, index) {
            final place = _searchResults[index];
            return InkWell(
              onTap: () => _onSearchResultTapped(place),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
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
                        color: _primaryRed,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            place.name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: _grey11,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (place.address.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
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
    );
  }

  // ══════════════════════════════════════════════
  // No Results Message
  // ══════════════════════════════════════════════

  Widget _buildNoResultsMessage() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
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
          Icon(Icons.search_off, size: 20, color: Colors.grey.shade400),
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
    );
  }

  // ══════════════════════════════════════════════
  // Use Current Location
  // ══════════════════════════════════════════════

  Widget _buildUseCurrentLocation() {
    final isSelected = _hasSelected && _selectedSavedIndex == null &&
        _searchController.text.isEmpty;

    return GestureDetector(
      onTap: _onUseCurrentLocation,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: ShapeDecoration(
          color: isSelected ? const Color(0xFFFFF1F0) : _grey96,
          shape: RoundedRectangleBorder(
            side: BorderSide(
              width: 1,
              color: isSelected ? _primaryRed : _greyBorder,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.my_location_outlined,
              size: 22,
              color: isSelected ? _primaryRed : _grey11,
            ),
            const SizedBox(width: 12),
            const Text(
              'Use current location',
              style: TextStyle(
                color: _grey11,
                fontSize: 16,
                
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════
  // Saved Addresses
  // ══════════════════════════════════════════════

  Widget _buildSavedAddresses() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4),
          child: Text(
            'Saved Addresses',
            style: TextStyle(
              color: Colors.black,
              fontSize: 16,
              
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 12),
        ...List.generate(_mockSavedAddresses.length, (i) {
          final addr = _mockSavedAddresses[i];
          final selected = _selectedSavedIndex == i;
          return Padding(
            padding: EdgeInsets.only(
                bottom: i < _mockSavedAddresses.length - 1 ? 12 : 0),
            child: _buildSavedAddressCard(i, addr, selected),
          );
        }),
      ],
    );
  }

  Widget _buildSavedAddressCard(
      int index, _SavedAddress addr, bool selected) {
    return GestureDetector(
      onTap: () => _onSavedAddressTapped(index),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: ShapeDecoration(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            side: BorderSide(
              width: 1,
              color: selected ? _primaryRed : _greyBorder,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          shadows: const [
            BoxShadow(
              color: Color(0x0C000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // Circle icon
            Container(
              width: 40,
              height: 40,
              decoration: const ShapeDecoration(
                color: _grey88,
                shape: CircleBorder(),
              ),
              child: Icon(
                addr.icon,
                size: 20,
                color: _grey11,
              ),
            ),
            const SizedBox(width: 16),
            // Label + address
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    addr.label,
                    style: const TextStyle(
                      color: _grey11,
                      fontSize: 16,
                      
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    addr.address,
                    style: const TextStyle(
                      color: _addressRed,
                      fontSize: 12,
                      
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            // Edit icon
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20,
                  color: Color(0xFF9CA3AF)),
              onPressed: () {},
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            const SizedBox(width: 4),
            // Delete icon
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20,
                  color: Color(0xFF9CA3AF)),
              onPressed: () {},
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════
  // Bottom Bar: Deliver Here
  // ══════════════════════════════════════════════

  Widget _buildBottomBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
      decoration: const ShapeDecoration(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          side: BorderSide(width: 1, color: _greyBorder),
        ),
      ),
      child: SafeArea(
        top: false,
        child: GestureDetector(
          onTap: _hasSelected ? _onDeliverHere : null,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: ShapeDecoration(
              color: _hasSelected ? _primaryRed : const Color(0xFFD9D9D9),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Deliver Here',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFFFFBFF),
                    fontSize: 18,
                    
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
