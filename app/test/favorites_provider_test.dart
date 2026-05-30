import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app/favorites_provider.dart';

void main() {
  group('FavoritesProvider', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('starts with empty favorites', () {
      final provider = FavoritesProvider(prefs);
      expect(provider.restaurantCount, 0);
      expect(provider.foodCount, 0);
      expect(provider.totalCount, 0);
      expect(provider.favoriteRestaurantIds, isEmpty);
      expect(provider.favoriteFoodIds, isEmpty);
    });

    test('isRestaurantFavorite returns false for non-favorited restaurant', () {
      final provider = FavoritesProvider(prefs);
      expect(provider.isRestaurantFavorite('r1'), false);
      expect(provider.isRestaurantFavorite('r99'), false);
    });

    test('isFoodFavorite returns false for non-favorited food', () {
      final provider = FavoritesProvider(prefs);
      expect(provider.isFoodFavorite('f1'), false);
      expect(provider.isFoodFavorite('f99'), false);
    });

    test('toggleRestaurant adds restaurant to favorites', () {
      final provider = FavoritesProvider(prefs);
      provider.toggleRestaurant('r1');
      expect(provider.isRestaurantFavorite('r1'), true);
      expect(provider.restaurantCount, 1);
      expect(provider.favoriteRestaurantIds, {'r1'});
    });

    test('toggleRestaurant removes restaurant from favorites', () {
      final provider = FavoritesProvider(prefs);
      provider.toggleRestaurant('r1');
      expect(provider.isRestaurantFavorite('r1'), true);

      provider.toggleRestaurant('r1');
      expect(provider.isRestaurantFavorite('r1'), false);
      expect(provider.restaurantCount, 0);
    });

    test('toggleFood adds food to favorites', () {
      final provider = FavoritesProvider(prefs);
      provider.toggleFood('f1');
      expect(provider.isFoodFavorite('f1'), true);
      expect(provider.foodCount, 1);
      expect(provider.favoriteFoodIds, {'f1'});
    });

    test('toggleFood removes food from favorites', () {
      final provider = FavoritesProvider(prefs);
      provider.toggleFood('f1');
      expect(provider.isFoodFavorite('f1'), true);

      provider.toggleFood('f1');
      expect(provider.isFoodFavorite('f1'), false);
      expect(provider.foodCount, 0);
    });

    test('tracks multiple restaurants independently', () {
      final provider = FavoritesProvider(prefs);
      provider.toggleRestaurant('r1');
      provider.toggleRestaurant('r2');
      provider.toggleRestaurant('r3');
      expect(provider.restaurantCount, 3);
      expect(provider.isRestaurantFavorite('r1'), true);
      expect(provider.isRestaurantFavorite('r2'), true);
      expect(provider.isRestaurantFavorite('r3'), true);

      // Remove one
      provider.toggleRestaurant('r2');
      expect(provider.restaurantCount, 2);
      expect(provider.isRestaurantFavorite('r2'), false);
    });

    test('tracks multiple foods independently', () {
      final provider = FavoritesProvider(prefs);
      provider.toggleFood('f1');
      provider.toggleFood('f2');
      expect(provider.foodCount, 2);

      provider.toggleFood('f1');
      expect(provider.foodCount, 1);
      expect(provider.isFoodFavorite('f2'), true);
      expect(provider.isFoodFavorite('f1'), false);
    });

    test('restaurants and foods are tracked separately', () {
      final provider = FavoritesProvider(prefs);
      provider.toggleRestaurant('r1');
      provider.toggleFood('f1');
      provider.toggleFood('f2');
      expect(provider.restaurantCount, 1);
      expect(provider.foodCount, 2);
      expect(provider.totalCount, 3);
      expect(provider.isRestaurantFavorite('r1'), true);
      expect(provider.isFoodFavorite('f1'), true);
      expect(provider.isFoodFavorite('f2'), true);
      expect(provider.isRestaurantFavorite('f1'), false); // different sets
    });

    test('notifies listeners on toggle', () {
      final provider = FavoritesProvider(prefs);
      int notificationCount = 0;
      provider.addListener(() => notificationCount++);

      provider.toggleRestaurant('r1');
      expect(notificationCount, 1);

      provider.toggleRestaurant('r1');
      expect(notificationCount, 2);

      provider.toggleFood('f1');
      expect(notificationCount, 3);
    });
  });

  group('FavoritesProvider persistence', () {
    late SharedPreferences prefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
    });

    test('saves restaurant favorites to SharedPreferences', () async {
      final provider = FavoritesProvider(prefs);
      provider.toggleRestaurant('r1');
      provider.toggleRestaurant('r2');

      // Allow the async save to complete
      await Future(() {});

      final savedJson = prefs.getString('favorite_restaurant_ids');
      expect(savedJson, isNotNull);
      final saved = json.decode(savedJson!) as List<dynamic>;
      expect(saved, containsAll(['r1', 'r2']));
    });

    test('saves food favorites to SharedPreferences', () async {
      final provider = FavoritesProvider(prefs);
      provider.toggleFood('f1');

      await Future(() {});

      final savedJson = prefs.getString('favorite_food_ids');
      expect(savedJson, isNotNull);
      final saved = json.decode(savedJson!) as List<dynamic>;
      expect(saved, ['f1']);
    });

    test('loads restaurant favorites from SharedPreferences', () async {
      // Pre-populate SharedPreferences
      await prefs.setString(
        'favorite_restaurant_ids',
        json.encode(['r1', 'r3']),
      );

      final provider = FavoritesProvider(prefs);
      expect(provider.restaurantCount, 2);
      expect(provider.isRestaurantFavorite('r1'), true);
      expect(provider.isRestaurantFavorite('r3'), true);
      expect(provider.isRestaurantFavorite('r2'), false);
    });

    test('loads food favorites from SharedPreferences', () async {
      await prefs.setString(
        'favorite_food_ids',
        json.encode(['f2', 'f5']),
      );

      final provider = FavoritesProvider(prefs);
      expect(provider.foodCount, 2);
      expect(provider.isFoodFavorite('f2'), true);
      expect(provider.isFoodFavorite('f5'), true);
      expect(provider.isFoodFavorite('f1'), false);
    });

    test('persists across provider instances', () async {
      // Create first instance, add favorites
      var provider = FavoritesProvider(prefs);
      provider.toggleRestaurant('r1');
      provider.toggleFood('f3');
      await Future(() {}); // let save complete

      // Create a fresh instance (simulating app restart)
      provider = FavoritesProvider(prefs);
      expect(provider.isRestaurantFavorite('r1'), true);
      expect(provider.isFoodFavorite('f3'), true);
      expect(provider.restaurantCount, 1);
      expect(provider.foodCount, 1);
    });

    test('handles empty SharedPreferences gracefully', () async {
      // No data pre-stored
      final provider = FavoritesProvider(prefs);
      expect(provider.restaurantCount, 0);
      expect(provider.foodCount, 0);
      expect(provider.favoriteRestaurantIds, isEmpty);
      expect(provider.favoriteFoodIds, isEmpty);
    });
  });
}
