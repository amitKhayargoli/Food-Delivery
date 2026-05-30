import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/mock_data.dart';
import '../../models/models.dart';
import '../../state_providers.dart';
import 'restaurant_menu_screen.dart';
import 'food_details_screen.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoritesProvider);
    final favoriteRestaurants = mockRestaurants
        .where((r) => favorites.favoriteRestaurantIds.contains(r.id))
        .toList();
    final favoriteFoods = mockRestaurants
        .expand((r) => r.foods)
        .where((f) => favorites.favoriteFoodIds.contains(f.id))
        .toList();

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildProfileHeader(),
              _buildFavoritesSection(context, ref, favoriteRestaurants, favoriteFoods),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Profile Header
  // ──────────────────────────────────────────────

  Widget _buildProfileHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F0),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.person_outline,
              size: 32,
              color: Color(0xFFF5222D),
            ),
          ),
          const SizedBox(width: 16),
          // User info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Food Lover',
                  style: TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '+977-98XXXXXXXX',
                  style: TextStyle(
                    color: Color(0xFF999999),
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          // Edit button
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.edit_outlined,
              size: 18,
              color: Color(0xFF666666),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Favorites Section
  // ──────────────────────────────────────────────

  Widget _buildFavoritesSection(
    BuildContext context,
    WidgetRef ref,
    List<Restaurant> favoriteRestaurants,
    List<Food> favoriteFoods,
  ) {
    if (favoriteRestaurants.isEmpty && favoriteFoods.isEmpty) {
      return _buildEmptyFavorites();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        // Section header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            children: [
              const Icon(Icons.favorite, size: 18, color: Color(0xFFF5222D)),
              const SizedBox(width: 8),
              Text(
                'My Favorites',
                style: const TextStyle(
                  color: Color(0xFF1A1A1A),
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),

        // Favorite Restaurants
        if (favoriteRestaurants.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Restaurants (${favoriteRestaurants.length})',
              style: const TextStyle(
                color: Color(0xFF666666),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SizedBox(
            height: 200,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: favoriteRestaurants.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) =>
                  _buildFavoriteRestaurantCard(context, ref, favoriteRestaurants[index]),
            ),
          ),
        ],

        // Favorite Foods
        if (favoriteFoods.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(
              'Food Items (${favoriteFoods.length})',
              style: const TextStyle(
                color: Color(0xFF666666),
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: favoriteFoods.map((food) {
                final restaurant = mockRestaurants.firstWhere(
                  (r) => r.foods.any((f) => f.id == food.id),
                  orElse: () => mockRestaurants.first,
                );
                return _buildFavoriteFoodItem(context, ref, food, restaurant);
              }).toList(),
            ),
          ),
        ],
      ],
    );
  }

  // ──────────────────────────────────────────────
  // Empty Favorites State
  // ──────────────────────────────────────────────

  Widget _buildEmptyFavorites() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.favorite_border,
            size: 64,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          const Text(
            'No favorites yet',
            style: TextStyle(
              color: Color(0xFF999999),
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Tap the heart icon on restaurants\nand food items to save them here',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFFBFBFBF),
              fontSize: 14,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Favorite Restaurant Card
  // ──────────────────────────────────────────────

  Widget _buildFavoriteRestaurantCard(
    BuildContext context,
    WidgetRef ref,
    Restaurant restaurant,
  ) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RestaurantMenuScreen(restaurant: restaurant),
          ),
        );
      },
      child: Container(
        width: 160,
        decoration: ShapeDecoration(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            side: const BorderSide(width: 1, color: Color(0xFFF0F0F0)),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            Stack(
              children: [
                Image.network(
                  restaurant.bannerUrl,
                  height: 110,
                  width: 160,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    height: 110,
                    width: 160,
                    color: const Color(0xFFF0F0F0),
                    child: const Icon(Icons.restaurant,
                        color: Color(0xFFBFBFBF), size: 32),
                  ),
                ),
                // Favorite button
                Positioned(
                  right: 6,
                  top: 6,
                  child: GestureDetector(
                    onTap: () {
                      ref
                          .read(favoritesProvider.notifier)
                          .toggleRestaurant(restaurant.id);
                    },
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.favorite,
                        size: 16,
                        color: const Color(0xFFF5222D),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            // Details
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    restaurant.name,
                    style: const TextStyle(
                      color: Color(0xFF262626),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.star, size: 12, color: Color(0xFFFFC107)),
                      const SizedBox(width: 3),
                      Text(
                        restaurant.rating.toString(),
                        style: const TextStyle(
                          color: Color(0xFF595959),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${restaurant.deliveryTimeMinutes} mins',
                        style: const TextStyle(
                          color: Color(0xFF8C8C8C),
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                        ),
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

  // ──────────────────────────────────────────────
  // Favorite Food Item
  // ──────────────────────────────────────────────

  Widget _buildFavoriteFoodItem(
    BuildContext context,
    WidgetRef ref,
    Food food,
    Restaurant restaurant,
  ) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FoodDetailsScreen(
              food: food,
              restaurant: restaurant,
            ),
          ),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(width: 1, color: Color(0xFFF0F0F0)),
          ),
        ),
        child: Row(
          children: [
            // Food image
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                food.imageUrl,
                width: 60,
                height: 60,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 60,
                  height: 60,
                  color: const Color(0xFFF0F0F0),
                  child: const Icon(Icons.restaurant,
                      color: Color(0xFFBFBFBF), size: 24),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    food.name,
                    style: const TextStyle(
                      color: Color(0xFF1A1A1A),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    restaurant.name,
                    style: const TextStyle(
                      color: Color(0xFF999999),
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'रु${food.price.toStringAsFixed(0)}',
                    style: const TextStyle(
                      color: Color(0xFFF5222D),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            // Remove favorite button
            GestureDetector(
              onTap: () {
                ref.read(favoritesProvider.notifier).toggleFood(food.id);
              },
              child: Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFF1F0),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.favorite,
                  size: 16,
                  color: Color(0xFFF5222D),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
