import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FavoritesProvider with ChangeNotifier {
  final SharedPreferences _prefs;

  Set<String> _favoriteRestaurantIds = {};
  Set<String> _favoriteFoodIds = {};

  static const String _restaurantsKey = 'favorite_restaurant_ids';
  static const String _foodsKey = 'favorite_food_ids';

  FavoritesProvider(this._prefs) {
    _loadFromPrefs();
  }

  Set<String> get favoriteRestaurantIds => Set.unmodifiable(_favoriteRestaurantIds);
  Set<String> get favoriteFoodIds => Set.unmodifiable(_favoriteFoodIds);

  bool isRestaurantFavorite(String id) => _favoriteRestaurantIds.contains(id);
  bool isFoodFavorite(String id) => _favoriteFoodIds.contains(id);

  void _loadFromPrefs() {
    final restaurantsJson = _prefs.getString(_restaurantsKey);
    if (restaurantsJson != null) {
      final list = json.decode(restaurantsJson) as List<dynamic>;
      _favoriteRestaurantIds = list.map((e) => e as String).toSet();
    }
    final foodsJson = _prefs.getString(_foodsKey);
    if (foodsJson != null) {
      final list = json.decode(foodsJson) as List<dynamic>;
      _favoriteFoodIds = list.map((e) => e as String).toSet();
    }
  }

  Future<void> _saveToPrefs() async {
    await _prefs.setString(
      _restaurantsKey,
      json.encode(_favoriteRestaurantIds.toList()),
    );
    await _prefs.setString(
      _foodsKey,
      json.encode(_favoriteFoodIds.toList()),
    );
  }

  void toggleRestaurant(String id) {
    if (_favoriteRestaurantIds.contains(id)) {
      _favoriteRestaurantIds.remove(id);
    } else {
      _favoriteRestaurantIds.add(id);
    }
    notifyListeners();
    _saveToPrefs();
  }

  void toggleFood(String id) {
    if (_favoriteFoodIds.contains(id)) {
      _favoriteFoodIds.remove(id);
    } else {
      _favoriteFoodIds.add(id);
    }
    notifyListeners();
    _saveToPrefs();
  }

  int get restaurantCount => _favoriteRestaurantIds.length;
  int get foodCount => _favoriteFoodIds.length;
  int get totalCount => restaurantCount + foodCount;
}
