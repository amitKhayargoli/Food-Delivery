import 'package:flutter_test/flutter_test.dart';
import 'package:baato_maps/baato_maps.dart';

import '../lib/core/services/baato_eta_service.dart';

/// Helper to build a valid mock [BaatoRouteResponse] from raw JSON.
/// The response must contain exactly one route with the given distance
/// (meters) and duration (milliseconds).
BaatoRouteResponse _makeRouteResponse({
  double distanceMeters = 5000.0,
  int timeMs = 600000, // 10 minutes
}) {
  final json = {
    'timestamp': '2024-01-01T00:00:00.000Z',
    'status': 200,
    'message': 'Success',
    'data': [
      {
        'distanceInMeters': distanceMeters,
        'timeInMs': timeMs,
      },
    ],
  };
  return BaatoRouteResponse.fromJson(json);
}

/// Helper that returns a [BaatoRouteFetcher] which always succeeds with the
/// given distance and duration.
BaatoRouteFetcher _successFetcher({
  double distanceMeters = 5000.0,
  int timeMs = 600000,
}) {
  return ({
    required BaatoCoordinate startCoordinate,
    required BaatoCoordinate endCoordinate,
    required BaatoDirectionMode mode,
    List<BaatoCoordinate>? midCoordinates,
    bool alternatives = false,
    bool instructions = false,
    bool decodePolyline = false,
  }) async {
    return _makeRouteResponse(distanceMeters: distanceMeters, timeMs: timeMs);
  };
}

/// Helper that returns a [BaatoRouteFetcher] which throws an error.
BaatoRouteFetcher _failingFetcher() {
  return ({
    required BaatoCoordinate startCoordinate,
    required BaatoCoordinate endCoordinate,
    required BaatoDirectionMode mode,
    List<BaatoCoordinate>? midCoordinates,
    bool alternatives = false,
    bool instructions = false,
    bool decodePolyline = false,
  }) async {
    throw Exception('Network error');
  };
}

/// Helper that returns a [BaatoRouteFetcher] with no routes (empty data).
BaatoRouteFetcher _emptyRoutesFetcher() {
  return ({
    required BaatoCoordinate startCoordinate,
    required BaatoCoordinate endCoordinate,
    required BaatoDirectionMode mode,
    List<BaatoCoordinate>? midCoordinates,
    bool alternatives = false,
    bool instructions = false,
    bool decodePolyline = false,
  }) async {
    final json = {
      'timestamp': '2024-01-01T00:00:00.000Z',
      'status': 200,
      'message': 'No routes',
      'data': <Map<String, dynamic>>[],
    };
    return BaatoRouteResponse.fromJson(json);
  };
}

/// Helper that returns a [BaatoRouteFetcher] with incomplete route data
/// (missing distance or duration).
BaatoRouteFetcher _incompleteDataFetcher() {
  return ({
    required BaatoCoordinate startCoordinate,
    required BaatoCoordinate endCoordinate,
    required BaatoDirectionMode mode,
    List<BaatoCoordinate>? midCoordinates,
    bool alternatives = false,
    bool instructions = false,
    bool decodePolyline = false,
  }) async {
    final json = {
      'timestamp': '2024-01-01T00:00:00.000Z',
      'status': 200,
      'message': 'Success',
      'data': [
        {
          // No distanceInMeters or timeInMs
          'encodedPolyline': 'abc123',
        },
      ],
    };
    return BaatoRouteResponse.fromJson(json);
  };
}

/// Coordinates roughly corresponding to central Kathmandu.
const double _kathmanduLat = 27.7172;
const double _kathmanduLng = 85.3240;

/// A nearby location ~5 km away in Kathmandu.
const double _nearbyLat = 27.7500;
const double _nearbyLng = 85.3500;

void main() {
  group('BaatoEtaService', () {
    late BaatoEtaService service;

    setUp(() {
      service = BaatoEtaService();
    });

    // ── cacheKey ─────────────────────────────────────────

    group('cacheKey()', () {
      test('rounds coordinates to 4 decimal places', () {
        final key = service.cacheKey(
          27.71723, 85.32396,  // ~11m resolution
          27.75001, 85.35001,
        );
        // The key should have exactly 4 decimal places
        expect(key, contains('27.7172'));
        expect(key, contains('85.3240'));
        expect(key, contains('27.7500'));
        expect(key, contains('85.3500'));
        // Verify format: lat1,lng1-lat2,lng2 with 4 decimal places
        expect(key, matches(RegExp(r'^-?\d+\.\d{4},-?\d+\.\d{4}'
            r'-?-?\d+\.\d{4},-?\d+\.\d{4}$')));
      });

      test('same coordinates produce identical keys', () {
        final key1 = service.cacheKey(27.7172, 85.3240, 27.7500, 85.3500);
        final key2 = service.cacheKey(27.7172, 85.3240, 27.7500, 85.3500);
        expect(key1, equals(key2));
      });

      test('different coordinates produce different keys', () {
        final key1 = service.cacheKey(27.7172, 85.3240, 27.7500, 85.3500);
        final key2 = service.cacheKey(27.7172, 85.3240, 27.7600, 85.3600);
        expect(key1, isNot(equals(key2)));
      });
    });

    // ── Cache hit / miss ────────────────────────────────

    group('caching', () {
      test('returns cached result for same coordinates within TTL', () async {
        final serviceWithMock = BaatoEtaService(
          routeFetcher: _successFetcher(
            distanceMeters: 5000.0,
            timeMs: 600000, // 10 min
          ),
        );

        // First call — fetches from API
        final result1 = await serviceWithMock.getEta(
          fromLat: _kathmanduLat,
          fromLng: _kathmanduLng,
          toLat: _nearbyLat,
          toLng: _nearbyLng,
        );
        expect(result1.isSuccess, isTrue);
        expect(result1.result!.durationMinutes, equals(10));
        expect(result1.result!.distanceKm, closeTo(5.0, 0.01));

        // Second call — should hit cache (same coords, within TTL)
        // Verify caching by counting fetcher calls — second identical call
        // should use cached result without calling the fetcher again.
        int fetchCount = 0;
        final countingFetcher = ({
          required BaatoCoordinate startCoordinate,
          required BaatoCoordinate endCoordinate,
          required BaatoDirectionMode mode,
          List<BaatoCoordinate>? midCoordinates,
          bool alternatives = false,
          bool instructions = false,
          bool decodePolyline = false,
        }) async {
          fetchCount++;
          return _makeRouteResponse(distanceMeters: 5000.0, timeMs: 600000);
        };

        final service2 = BaatoEtaService(routeFetcher: countingFetcher);
        await service2.getEta(
          fromLat: _kathmanduLat,
          fromLng: _kathmanduLng,
          toLat: _nearbyLat,
          toLng: _nearbyLng,
        );
        await service2.getEta(
          fromLat: _kathmanduLat,
          fromLng: _kathmanduLng,
          toLat: _nearbyLat,
          toLng: _nearbyLng,
        );
        // Two identical calls should only call the fetcher once (second is cached)
        expect(fetchCount, equals(1));
      });

      test('different coordinates bypass cache', () async {
        int fetchCount = 0;
        final countingFetcher = ({
          required BaatoCoordinate startCoordinate,
          required BaatoCoordinate endCoordinate,
          required BaatoDirectionMode mode,
          List<BaatoCoordinate>? midCoordinates,
          bool alternatives = false,
          bool instructions = false,
          bool decodePolyline = false,
        }) async {
          fetchCount++;
          return _makeRouteResponse(distanceMeters: 5000.0, timeMs: 600000);
        };

        final service2 = BaatoEtaService(routeFetcher: countingFetcher);
        await service2.getEta(
          fromLat: _kathmanduLat,
          fromLng: _kathmanduLng,
          toLat: _nearbyLat,
          toLng: _nearbyLng,
        );
        // Different destination
        await service2.getEta(
          fromLat: _kathmanduLat,
          fromLng: _kathmanduLng,
          toLat: 27.7600,
          toLng: 85.3600,
        );
        expect(fetchCount, equals(2));
      });

      test('clearCache() empties the cache', () async {
        int fetchCount = 0;
        final countingFetcher = ({
          required BaatoCoordinate startCoordinate,
          required BaatoCoordinate endCoordinate,
          required BaatoDirectionMode mode,
          List<BaatoCoordinate>? midCoordinates,
          bool alternatives = false,
          bool instructions = false,
          bool decodePolyline = false,
        }) async {
          fetchCount++;
          return _makeRouteResponse(distanceMeters: 5000.0, timeMs: 600000);
        };

        final service2 = BaatoEtaService(routeFetcher: countingFetcher);
        await service2.getEta(
          fromLat: _kathmanduLat,
          fromLng: _kathmanduLng,
          toLat: _nearbyLat,
          toLng: _nearbyLng,
        );
        service2.clearCache();
        await service2.getEta(
          fromLat: _kathmanduLat,
          fromLng: _kathmanduLng,
          toLat: _nearbyLat,
          toLng: _nearbyLng,
        );
        // Cache was cleared, so fetcher should have been called twice
        expect(fetchCount, equals(2));
      });

      test('cacheSize returns number of entries', () async {
        final service2 = BaatoEtaService(
          routeFetcher: _successFetcher(),
        );
        expect(service2.cacheSize, equals(0));

        await service2.getEta(
          fromLat: _kathmanduLat,
          fromLng: _kathmanduLng,
          toLat: _nearbyLat,
          toLng: _nearbyLng,
        );
        expect(service2.cacheSize, equals(1));

        await service2.getEta(
          fromLat: _kathmanduLat,
          fromLng: _kathmanduLng,
          toLat: 27.7600,
          toLng: 85.3600,
        );
        expect(service2.cacheSize, equals(2));

        service2.clearCache();
        expect(service2.cacheSize, equals(0));
      });
    });

    // ── Successful API response ─────────────────────────

    group('getEta() — success', () {
      test('returns correct duration and distance for valid route', () async {
        final serviceWithMock = BaatoEtaService(
          routeFetcher: _successFetcher(
            distanceMeters: 5000.0,  // 5 km
            timeMs: 600000,           // 10 min
          ),
        );

        final response = await serviceWithMock.getEta(
          fromLat: _kathmanduLat,
          fromLng: _kathmanduLng,
          toLat: _nearbyLat,
          toLng: _nearbyLng,
        );

        expect(response.isSuccess, isTrue);
        expect(response.result!.durationMinutes, equals(10));
        expect(response.result!.distanceKm, closeTo(5.0, 0.01));
      });

      test('clamps minimum duration to 1 minute', () async {
        final serviceWithMock = BaatoEtaService(
          routeFetcher: _successFetcher(
            distanceMeters: 100.0,   // 100 m
            timeMs: 10000,            // 10 seconds → 0.17 min
          ),
        );

        final response = await serviceWithMock.getEta(
          fromLat: _kathmanduLat,
          fromLng: _kathmanduLng,
          toLat: _nearbyLat,
          toLng: _nearbyLng,
        );

        expect(response.isSuccess, isTrue);
        // .clamp(1, 999) — should be at least 1 minute
        expect(response.result!.durationMinutes, greaterThanOrEqualTo(1));
      });
    });

    // ── Distance validation ────────────────────────────

    group('getEta() — distance validation', () {
      test('rejects routes exceeding maxReasonableDistanceKm (100 km)', () async {
        final serviceWithMock = BaatoEtaService(
          routeFetcher: _successFetcher(
            distanceMeters: 200000.0, // 200 km — exceeds 100 km threshold
            timeMs: 7200000,          // 120 min
          ),
        );

        final response = await serviceWithMock.getEta(
          fromLat: _kathmanduLat,
          fromLng: _kathmanduLng,
          toLat: _nearbyLat,
          toLng: _nearbyLng,
        );

        expect(response.isError, isTrue);
        expect(response.error, contains('Route distance too large'));
      });

      test('accepts routes at exactly maxReasonableDistanceKm', () async {
        final serviceWithMock = BaatoEtaService(
          routeFetcher: _successFetcher(
            distanceMeters: 100000.0, // exactly 100 km — at threshold
            timeMs: 3600000,          // 60 min
          ),
        );

        final response = await serviceWithMock.getEta(
          fromLat: _kathmanduLat,
          fromLng: _kathmanduLng,
          toLat: _nearbyLat,
          toLng: _nearbyLng,
        );

        // 100 km is NOT > 100.0, so it should be accepted
        expect(response.isSuccess, isTrue);
        expect(response.result!.distanceKm, closeTo(100.0, 0.01));
      });
    });

    // ── Error handling ─────────────────────────────────

    group('getEta() — error handling', () {
      test('returns error when fetcher throws exception', () async {
        final serviceWithMock = BaatoEtaService(
          routeFetcher: _failingFetcher(),
        );

        final response = await serviceWithMock.getEta(
          fromLat: _kathmanduLat,
          fromLng: _kathmanduLng,
          toLat: _nearbyLat,
          toLng: _nearbyLng,
        );

        expect(response.isError, isTrue);
        expect(response.error, contains('Baato Directions API error'));
      });

      test('returns error when routes list is empty', () async {
        final serviceWithMock = BaatoEtaService(
          routeFetcher: _emptyRoutesFetcher(),
        );

        final response = await serviceWithMock.getEta(
          fromLat: _kathmanduLat,
          fromLng: _kathmanduLng,
          toLat: _nearbyLat,
          toLng: _nearbyLng,
        );

        expect(response.isError, isTrue);
        expect(response.error, contains('No route found'));
      });

      test('returns error when route data is incomplete', () async {
        final serviceWithMock = BaatoEtaService(
          routeFetcher: _incompleteDataFetcher(),
        );

        final response = await serviceWithMock.getEta(
          fromLat: _kathmanduLat,
          fromLng: _kathmanduLng,
          toLat: _nearbyLat,
          toLng: _nearbyLng,
        );

        expect(response.isError, isTrue);
        expect(response.error, contains('Incomplete route data'));
      });
    });

    // ── BaatoEtaResult ─────────────────────────────────

    group('BaatoEtaResult', () {
      test('stores durationMinutes and distanceKm', () {
        const result = BaatoEtaResult(
          durationMinutes: 15,
          distanceKm: 3.5,
        );
        expect(result.durationMinutes, equals(15));
        expect(result.distanceKm, equals(3.5));
      });
    });

    // ── BaatoEtaResponse ───────────────────────────────

    group('BaatoEtaResponse', () {
      test('isSuccess returns true when result is set', () {
        const response = BaatoEtaResponse(
          result: BaatoEtaResult(durationMinutes: 5, distanceKm: 2.0),
        );
        expect(response.isSuccess, isTrue);
        expect(response.isError, isFalse);
      });

      test('isError returns true when error is set', () {
        const response = BaatoEtaResponse(error: 'Something went wrong');
        expect(response.isError, isTrue);
        expect(response.isSuccess, isFalse);
      });
    });
  });
}
