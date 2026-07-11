import 'package:flutter/foundation.dart';
import '../models/models.dart';
import '../core/services/api_service.dart';
import '../injection_container.dart' as di;

/// State for the restaurants list
class RestaurantsState {
  final List<Restaurant> restaurants;
  final bool isLoading;
  final String? error;

  const RestaurantsState({
    this.restaurants = const [],
    this.isLoading = false,
    this.error,
  });

  RestaurantsState copyWith({
    List<Restaurant>? restaurants,
    bool? isLoading,
    String? error,
  }) {
    return RestaurantsState(
      restaurants: restaurants ?? this.restaurants,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
    );
  }
}

/// Notifier that manages fetching and caching restaurants
class RestaurantsNotifier extends ChangeNotifier {
  RestaurantsState _state = const RestaurantsState();

  RestaurantsState get state => _state;

  Future<void> fetchRestaurants() async {
    if (_state.isLoading) return;

    _state = _state.copyWith(isLoading: true, error: null);
    notifyListeners();

    try {
      final api = di.sl<ApiService>();
      final rawRestaurants = await api.getRestaurants();
      final restaurants = rawRestaurants
          .map((r) => Restaurant.fromJson(r))
          .where((r) => r.isAcceptingOrders)
          .toList();

      _state = RestaurantsState(restaurants: restaurants, isLoading: false);
      notifyListeners();
    } on ApiException catch (e) {
      _state = _state.copyWith(isLoading: false, error: e.message);
      notifyListeners();
    } catch (e) {
      _state = _state.copyWith(isLoading: false, error: 'Failed to load restaurants.');
      notifyListeners();
    }
  }

  void refresh() => fetchRestaurants();
}
