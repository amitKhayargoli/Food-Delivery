import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:baato_maps/baato_maps.dart';
import '../core/services/delivery_location_service.dart';
import '../injection_container.dart' as di;
import '../screens/user/delivery_address_map_screen.dart';
import '../screens/user/selected_delivery_location.dart';

/// Shared "Delivering To" header used by both [UserHomeScreen] and
/// [SearchScreen].  It is fully self-contained:
///  1. Loads the last-pinned location from SharedPreferences on init
///  2. Falls back to GPS reverse-geocode if no saved location exists
///  3. On tap opens [DeliveryAddressMapScreen] so the user can pick a new pin
///  4. Saves the result to SharedPreferences automatically
class DeliveryLocationHeader extends StatefulWidget {
  const DeliveryLocationHeader({super.key});

  @override
  State<DeliveryLocationHeader> createState() => _DeliveryLocationHeaderState();
}

class _DeliveryLocationHeaderState extends State<DeliveryLocationHeader> {
  final DeliveryLocationService _locationService =
      di.sl<DeliveryLocationService>();

  String _address = '';

  @override
  void initState() {
    super.initState();
    _loadOrDetect();
  }

  /// Called on first init **and** on every build so the header always shows
  /// the latest persisted location (even if it was changed from another
  /// screen like checkout).
  void _syncFromPrefs() {
    final saved = _locationService.loadLocation();
    if (saved != null) {
      _address = saved.address;
    }
  }

  Future<void> _loadOrDetect() async {
    // 1. Try SharedPreferences first
    final saved = _locationService.loadLocation();
    if (saved != null) {
      if (mounted) {
        setState(() => _address = saved.address);
      }
      return;
    }

    // 2. Nothing saved — show loading message and try GPS
    if (mounted) {
      setState(() => _address = 'Detecting your location...');
    }

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) setState(() => _address = 'Location services off');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (mounted) setState(() => _address = 'Set location in settings');
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) return;

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (!mounted) return;

      // Reverse-geocode via Baato
      String address = '';
      try {
        final coord = BaatoCoordinate(
          latitude: position.latitude,
          longitude: position.longitude,
        );
        final response =
            await Baato.api.place.reverseGeocode(coord, limit: 1);
        final places = response.data;
        if (places != null && places.isNotEmpty) {
          final first = places.first;
          address = first.name.isNotEmpty ? first.name : first.address;
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _address = address.isNotEmpty
              ? address
              : '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _address = 'Tap to set location');
    }
  }

  Future<void> _onTap() async {
    // Re-sync before navigating so the map opens with the latest pin
    _syncFromPrefs();

    final initialLocation = _locationService.loadLocation();

    final result = await Navigator.push<SelectedDeliveryLocation>(
      context,
      MaterialPageRoute(
        builder: (_) => DeliveryAddressMapScreen(
          initialLocation: initialLocation,
        ),
      ),
    );

    if (result != null && mounted) {
      setState(() => _address = result.address);
      _locationService.saveLocation(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Always pull the latest from SharedPreferences so the header reflects
    // location changes made on another screen (e.g. checkout).
    _syncFromPrefs();

    return GestureDetector(
      onTap: _onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            bottom: BorderSide(color: Color(0xFFF0F0F0), width: 1),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFF5222D),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.location_on_outlined,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Delivering To',
                    style: TextStyle(
                      color: Color(0xFF262626),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          _address.isNotEmpty ? _address : 'Detecting your location...',
                          style: const TextStyle(
                            color: Color(0xFF8C8C8C),
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.keyboard_arrow_down,
                        size: 18,
                        color: Color(0xFF8C8C8C),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
