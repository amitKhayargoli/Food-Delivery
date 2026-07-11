import 'package:baato_maps/baato_maps.dart';

/// Type signature for a Baato Directions API call.
/// Injectable for testability — see [BaatoEtaService.routeFetcher].
typedef BaatoRouteFetcher = Future<BaatoRouteResponse> Function({
  required BaatoCoordinate startCoordinate,
  required BaatoCoordinate endCoordinate,
  required BaatoDirectionMode mode,
  List<BaatoCoordinate>? midCoordinates,
  bool alternatives,
  bool instructions,
  bool decodePolyline,
});

/// Result of a Baato Directions API call containing road-based
/// distance and estimated travel time.
class BaatoEtaResult {
  /// Travel time in minutes.
  final int durationMinutes;

  /// Travel distance in kilometers.
  final double distanceKm;

  const BaatoEtaResult({
    required this.durationMinutes,
    required this.distanceKm,
  });
}

/// A lightweight result-type wrapper for Baato ETA lookups.
/// Either [result] is set (success) or [error] is set (failure).
class BaatoEtaResponse {
  final BaatoEtaResult? result;
  final String? error;

  const BaatoEtaResponse({this.result, this.error});

  bool get isSuccess => result != null;
  bool get isError => error != null;
}

/// Cached ETA entry with timestamp for TTL enforcement.
class _CachedEta {
  final DateTime timestamp;
  final BaatoEtaResult result;

  const _CachedEta(this.timestamp, this.result);
}

/// Provides road-distance-based ETA estimates using the Baato Directions API.
///
/// Results are cached per coordinate pair for [cacheTtl] to avoid excessive
/// API calls while the rider is moving. The cache key has ~100m granularity
/// (4 decimal places), so small rider movements reuse the cached result.
class BaatoEtaService {
  /// Default time-to-live for a cached ETA result.
  static const Duration cacheTtl = Duration(seconds: 30);

  /// Maximum reasonable road distance in km.
  /// Baato Directions API returns road distance (not straight line), so we
  /// use a higher threshold than the Haversine fallback (100 km). For a food
  /// delivery app operating in a city / valley, anything > 50 km on road is
  /// likely invalid or an edge case.
  static const double maxReasonableDistanceKm = 100.0;

  final Map<String, _CachedEta> _cache = {};

  /// Optional injectable route fetcher, used primarily in unit tests to
  /// return controlled mock responses without making real API calls.
  /// When null (the default), the real [Baato.api.direction.getRoutes] is used.
  final BaatoRouteFetcher? routeFetcher;

  /// Create a [BaatoEtaService].
  ///
  /// Provide [routeFetcher] in tests to stub the Baato Directions API call.
  /// The [routeFetcher] must return a [BaatoRouteResponse] whose `data` list
  /// contains routes with [BaatoRoute.distanceInMeters] and
  /// [BaatoRoute.timeInMs] populated.
  BaatoEtaService({this.routeFetcher});

  /// Generate a cache key with 4-decimal-place precision (~11m resolution).
  /// Though [cacheTtl] is shorter, a finer key means the same cached
  /// result is reused when the rider hasn't moved meaningfully.
  String cacheKey(double lat1, double lng1, double lat2, double lng2) {
    return '${lat1.toStringAsFixed(4)},${lng1.toStringAsFixed(4)}'
        '-${lat2.toStringAsFixed(4)},${lng2.toStringAsFixed(4)}';
  }

  /// Look up the cache for [key]. Returns the cached result if still fresh.
  BaatoEtaResult? getCached(String key) {
    final entry = _cache[key];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.timestamp) > cacheTtl) {
      _cache.remove(key);
      return null;
    }
    return entry.result;
  }

  /// Expose cache size for testing.
  int get cacheSize => _cache.length;

  /// Fetch the road-based ETA from [from] coordinate to [to] coordinate.
  ///
  /// Returns a [BaatoEtaResponse] with either a success result or an error.
  /// On failure (API error, no route found, distance exceeds threshold), the
  /// caller can fall back to the Haversine estimate or hide the ETA.
  Future<BaatoEtaResponse> getEta({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  }) async {
    final key = cacheKey(fromLat, fromLng, toLat, toLng);

    // Check cache
    final cached = getCached(key);
    if (cached != null) {
      return BaatoEtaResponse(result: cached);
    }

    try {
      final start = BaatoCoordinate(latitude: fromLat, longitude: fromLng);
      final end = BaatoCoordinate(latitude: toLat, longitude: toLng);

      final BaatoRouteResponse response;
      if (routeFetcher != null) {
        response = await routeFetcher!(
          startCoordinate: start,
          endCoordinate: end,
          mode: BaatoDirectionMode.car,
          alternatives: false,
          instructions: false,
          decodePolyline: false,
        );
      } else {
        response = await Baato.api.direction.getRoutes(
          startCoordinate: start,
          endCoordinate: end,
          mode: BaatoDirectionMode.car,
          alternatives: false,
          instructions: false,
          decodePolyline: false,
        );
      }

      final routes = response.data;
      if (routes == null || routes.isEmpty) {
        return const BaatoEtaResponse(error: 'No route found');
      }

      final route = routes.first;
      final distanceM = route.distanceInMeters;
      final timeMs = route.timeInMs;

      if (distanceM == null || timeMs == null) {
        return const BaatoEtaResponse(error: 'Incomplete route data');
      }

      final distanceKm = distanceM / 1000.0;

      // Sanity check: reject unreasonably long routes (invalid coordinates)
      if (distanceKm > maxReasonableDistanceKm) {
        return const BaatoEtaResponse(error: 'Route distance too large');
      }

      final durationMinutes = (timeMs / 60000).round().clamp(1, 999);

      final result = BaatoEtaResult(
        durationMinutes: durationMinutes,
        distanceKm: distanceKm,
      );

      // Cache the result
      _cache[key] = _CachedEta(DateTime.now(), result);

      return BaatoEtaResponse(result: result);
    } catch (e) {
      return BaatoEtaResponse(error: 'Baato Directions API error: $e');
    }
  }

  /// Clear all cached ETA results, forcing fresh API calls on the next request.
  void clearCache() {
    _cache.clear();
  }
}
