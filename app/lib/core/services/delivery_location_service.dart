import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/saved_address.dart';
import '../../screens/user/selected_delivery_location.dart';
import 'api_service.dart';

/// Persists the user's last pinned delivery location and named saved
/// addresses so they survive app restarts.  Also syncs the pinned
/// location to the backend profile so it follows the user across devices.
class DeliveryLocationService {
  static const String _key = 'saved_delivery_location';
  static const String _savedAddressesKey = 'saved_addresses_list';

  final SharedPreferences _prefs;
  final ApiService _api;

  /// If set, the next [saveLocation] call will also push to the backend.
  String? _authToken;

  DeliveryLocationService(this._prefs, this._api);

  /// Enable backend sync by providing the user's JWT.
  void setAuthToken(String? token) {
    _authToken = token;
  }

  // ── Last pinned location ──

  /// Save (or overwrite) the last pinned delivery location.
  /// Also pushes to the backend when a token is available.
  Future<void> saveLocation(SelectedDeliveryLocation location) async {
    await _prefs.setString(_key, jsonEncode(location.toJson()));
    await _syncToBackend(location);
  }

  /// Save without syncing to backend (used when loading from backend).
  Future<void> _saveLocationLocalOnly(SelectedDeliveryLocation location) async {
    await _prefs.setString(_key, jsonEncode(location.toJson()));
  }

  /// Load the previously pinned location, or null if none has been saved yet.
  SelectedDeliveryLocation? loadLocation() {
    final raw = _prefs.getString(_key);
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return SelectedDeliveryLocation.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// Remove the pinned location (e.g. on logout).
  Future<void> clearLocation() async {
    await _prefs.remove(_key);
  }

  // ── Backend sync ──

  /// Push the current local location to the backend profile.
  Future<void> _syncToBackend(SelectedDeliveryLocation location) async {
    final token = _authToken;
    if (token == null) return;
    try {
      await _api.saveDeliveryLocation(
        address: location.address,
        latitude: location.latitude,
        longitude: location.longitude,
        token: token,
      );
    } catch (_) {
      // Silently ignore backend sync errors — location is still saved locally
    }
  }

  /// Pull the delivery location from the backend and save it locally.
  /// Returns the location if one was found, or null.
  Future<SelectedDeliveryLocation?> pullFromBackend() async {
    final token = _authToken;
    if (token == null) return null;
    try {
      final data = await _api.fetchDeliveryLocation(token: token);
      if (data == null) return null;

      final latRaw = (data['latitude'] as num?)?.toDouble();
      final lngRaw = (data['longitude'] as num?)?.toDouble();

      // Reject missing, zero, or out-of-Nepal-bounds coordinates
      if (latRaw == null || lngRaw == null) return null;
      if (latRaw == 0.0 && lngRaw == 0.0) return null;
      if (latRaw < 26.0 || latRaw > 30.0 || lngRaw < 80.0 || lngRaw > 88.0) return null;

      final location = SelectedDeliveryLocation(
        address: data['address'] as String? ?? '',
        latitude: latRaw,
        longitude: lngRaw,
      );

      if (location.address.isNotEmpty) {
        await _saveLocationLocalOnly(location);
        return location;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── Named saved addresses ──

  /// Load all user-saved named addresses (Home, Work, etc.).
  List<SavedAddress> loadSavedAddresses() {
    final raw = _prefs.getString(_savedAddressesKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => SavedAddress.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Persist the full list of saved addresses.
  Future<void> _persistSavedAddresses(List<SavedAddress> addresses) async {
    final encoded =
        jsonEncode(addresses.map((a) => a.toJson()).toList());
    await _prefs.setString(_savedAddressesKey, encoded);
  }

  /// Add a new saved address (or update one with the same label).
  Future<void> saveSavedAddress(SavedAddress address) async {
    final list = loadSavedAddresses();
    final index = list.indexWhere((a) => a.label == address.label);
    if (index >= 0) {
      list[index] = address;
    } else {
      list.add(address);
    }
    await _persistSavedAddresses(list);
  }

  /// Remove a saved address by label.
  Future<void> deleteSavedAddress(String label) async {
    final list = loadSavedAddresses();
    list.removeWhere((a) => a.label == label);
    await _persistSavedAddresses(list);
  }

  /// Remove all saved addresses.
  Future<void> clearAllSavedAddresses() async {
    await _prefs.remove(_savedAddressesKey);
  }
}
