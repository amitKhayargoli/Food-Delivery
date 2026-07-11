import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' hide Consumer;
import '../../models/models.dart';
import '../../models/order.dart';
import '../../cart_provider.dart';
import '../../core/services/api_service.dart';
import '../../providers/notification_provider.dart';
import '../notifications_screen.dart';
import '../../core/utils/time_of_day_util.dart';
import '../../injection_container.dart' as di;
import '../../providers/auth_provider.dart';
import '../../state_providers.dart';
import '../../widgets/delivery_location_header.dart';
import 'restaurant_menu_screen.dart';
import 'favorites_screen.dart';

class UserHomeScreen extends ConsumerStatefulWidget {
  const UserHomeScreen({super.key});

  @override
  ConsumerState<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends ConsumerState<UserHomeScreen> {
  List<Order> _recentOrders = [];

  /// Personalized suggestions data
  List<Map<String, dynamic>> _favoriteRestaurants = [];

  /// Time-of-day greeting & suggestions data (lazily fetched + cached).
  String _greeting = TimeOfDayUtil.greeting();
  String _currentPeriod = TimeOfDayUtil.currentPeriod;
  List<String> _favoriteCuisines = [];

  /// Timer that refreshes the greeting at period boundaries.
  Timer? _periodTimer;

  String? get _token => context.read<AuthProvider>().token;

  @override
  void initState() {
    super.initState();
    ref.read(restaurantsProvider).fetchRestaurants();
    _fetchOrderHistory();
    _schedulePeriodRefresh();
  }

  /// Schedule a timer that fires at the next period boundary
  /// (e.g., from morning→afternoon at 12:00) to update the greeting.
  void _schedulePeriodRefresh() {
    _periodTimer?.cancel();
    final secondsUntilNext = TimeOfDayUtil.secondsUntilNextPeriod();
    if (secondsUntilNext <= 0) return;

    _periodTimer = Timer(Duration(seconds: secondsUntilNext), () {
      if (mounted) {
        setState(() {
          _currentPeriod = TimeOfDayUtil.currentPeriod;
          _greeting = TimeOfDayUtil.greeting();
        });
        // Re-schedule for the next boundary
        _schedulePeriodRefresh();
      }
    });
  }

  Future<void> _fetchOrderHistory() async {
    final token = _token;
    if (token == null) return;

    try {
      final api = di.sl<ApiService>();
      final response = await api.getOrderHistory(token: token, limit: 10);
      if (mounted) {
        setState(() {
          _recentOrders = response.orders
              .map((o) => Order.fromJson(o))
              .where((o) => o.status == OrderStatus.delivered)
              .take(3)
              .toList();
        });
      }

      // Also fetch favorite cuisines from the suggestions endpoint
      try {
        final suggestions = await api.getHomeSuggestions(token: token);
        if (mounted && suggestions.favoriteCuisines.isNotEmpty) {
          setState(() {
            _favoriteCuisines = suggestions.favoriteCuisines;
          });
        }
      } catch (_) {}

      // Fetch personalized suggestions (Order Again + Your Favourites)
      try {
        final personalized = await api.getPersonalizedSuggestions(token: token);
        if (!mounted) return;
        final favRestaurants = (personalized['favorite_restaurants'] as List<dynamic>? ?? [])
            .cast<Map<String, dynamic>>();
        setState(() {
          _favoriteRestaurants = favRestaurants;
        });
      } catch (_) {}
    } catch (e) {
      // Silently ignore order history errors — not critical for the home screen
    }
  }

  @override
  void dispose() {
    _periodTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final restaurantsNotifier = ref.watch(restaurantsProvider);
    final restaurantsState = restaurantsNotifier.state;
    final allRestaurants = restaurantsState.restaurants;
    final isLoading = restaurantsState.isLoading;
    final cartProvider = context.read<CartProvider>();

    // Feed preferences (toggle on/off from Customize Feed screen)
    final feedPrefs = ref.watch(feedPreferencesProvider);
    final timeOfDayEnabled = feedPrefs.timeOfDayEnabled;
    final personalizedEnabled = feedPrefs.personalizedSuggestionsEnabled;

    // Filter restaurants by the current time-of-day
    // Matches both by food-item category and by restaurant cuisine type
    final period = _currentPeriod;
    final timeMatched = allRestaurants
        .map((r) => (
              r,
              r.foods.where((f) => TimeOfDayUtil.categoryMatches(f.categoryId, period)).toList(),
            ))
        .where((pair) =>
          pair.$2.isNotEmpty ||
          TimeOfDayUtil.cuisineMatches(pair.$1.cuisineType, period),
        )
        .toList();
    final hasTimeSuggestions = timeMatched.isNotEmpty && timeOfDayEnabled;

    // Prioritize favorite cuisines for the time-of-day section
    final prioritizedSuggestions = [...timeMatched];
    if (_favoriteCuisines.isNotEmpty && personalizedEnabled) {
      prioritizedSuggestions.sort((a, b) {
        final aIsFav = _favoriteCuisines.any((fav) =>
            a.$1.cuisineType.toLowerCase().contains(fav.toLowerCase()));
        final bIsFav = _favoriteCuisines.any((fav) =>
            b.$1.cuisineType.toLowerCase().contains(fav.toLowerCase()));
        if (aIsFav && !bIsFav) return -1;
        if (!aIsFav && bIsFav) return 1;
        return b.$1.rating.compareTo(a.$1.rating);
      });
    }

    // Top picks by rating (for "Top Picks" section)
    final topPicks = [...allRestaurants]
      ..sort((a, b) => b.rating.compareTo(a.rating));
    final displayTopPicks = topPicks.take(3).toList();

    // Discount badges — random assignment for display
    final discounts = <String, String>{
      for (final r in allRestaurants)
        r.id: ['Flat 30% OFF', 'Flat 20% OFF', 'Flat 10% OFF'][
            allRestaurants.indexOf(r) % 3]
    };

    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      body: SafeArea(
        child: Stack(
          children: [
            CustomScrollView(
          slivers: [
            // ── Sticky Location Header (SliverPersistentHeader, pinned) ──
            SliverPersistentHeader(
              pinned: true,
              delegate: _StickyHeaderDelegate(
                child: const DeliveryLocationHeader(),
              ),
            ),

            // ── Scrollable Content ──
            SliverList(
              delegate: SliverChildListDelegate([
                // ── Time-of-Day Greeting ──
                if (timeOfDayEnabled) _buildTimeGreeting(context),

                // ── Promo Banner ──
                _buildPromoBanner(context),

                // ── Surprise Me Button ──
                _buildSurpriseMeButton(context),

                // ── Quick Reorder Section (individual food items from recent orders) ──
                if (_recentOrders.isNotEmpty && personalizedEnabled) ...[
                  _buildQuickReorder(context, cartProvider),
                ],

                // ── Your Favourites Section (only if data exists + toggle on) ──
                if (_favoriteRestaurants.isNotEmpty && personalizedEnabled) ...[
                  _buildYourFavourites(context),
                ],

                // ── Loading / Error / Restaurants ──
                if (isLoading && allRestaurants.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator(color: Color(0xFFBB0018))),
                  )
                else if (restaurantsState.error != null && allRestaurants.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
                    child: Center(
                      child: Column(
                        children: [
                          const Icon(Icons.cloud_off, size: 40, color: Color(0xFF8E8E93)),
                          const SizedBox(height: 12),
                          Text(
                            restaurantsState.error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 14),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () => ref.read(restaurantsProvider).refresh(),
                            child: const Text('Try Again'),
                          ),
                        ],
                      ),
                    ),
                  )
                else ...[
                  // ── Time-of-Day Food Suggestions ──
                  if (hasTimeSuggestions && allRestaurants.isNotEmpty) ...[
                    _buildSectionHeader(
                      context,
                      TimeOfDayUtil.suggestionSectionTitle(period),
                      subtitle: _favoriteCuisines.isNotEmpty
                          ? 'Your favorite cuisines first'
                          : null,
                      onSeeAll: () {},
                    ),
                    _buildTimeSuggestionList(
                      context,
                      suggestions: prioritizedSuggestions,
                      discounts: discounts,
                    ),
                  ],

                  // ── New Near You Section ──
                  if (allRestaurants.isNotEmpty) ...[
                    _buildSectionHeader(context, 'New Near You', onSeeAll: () {}),
                    _buildRestaurantHorizontalList(
                      context,
                      restaurants: allRestaurants,
                      discounts: discounts,
                    ),
                  ],

                  // ── Top Picks For You Section ──
                  if (displayTopPicks.isNotEmpty) ...[
                    _buildSectionHeader(context, 'Top Picks For You', onSeeAll: () {}),
                    _buildRestaurantHorizontalList(
                      context,
                      restaurants: displayTopPicks,
                      discounts: discounts,
                    ),
                  ],
                ],

                // ── Because You Ordered Section ──
                if (_recentOrders.isNotEmpty) ...[
                  _buildBecauseYouOrdered(context, cartProvider),
                ],

                const SizedBox(height: 24),
              ]),
            ),
          ],
        ),

        // ── Bell icon (top-right) ──
        Positioned(
          top: 8,
          right: 12,
          child: _buildBellIcon(context),
        ),
      ],
      ),
    ),
  );
  }

  Widget _buildBellIcon(BuildContext context) {
    final notifProvider = context.watch<NotificationProvider>();
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(30),
      elevation: 4,
      shadowColor: Colors.black26,
      child: InkWell(
        borderRadius: BorderRadius.circular(30),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NotificationsScreen()),
          );
        },
        child: Container(
          width: 42,
          height: 42,
          padding: const EdgeInsets.all(2),
          child: Stack(
            children: [
              const Center(
                child: Icon(
                  Icons.notifications_outlined,
                  size: 22,
                  color: Color(0xFF1A1C1C),
                ),
              ),
              if (notifProvider.hasUnread)
                Positioned(
                  top: 2,
                  right: 4,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Color(0xFFF5222D),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${notifProvider.unreadCount}',
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Time-of-Day Greeting
  // ──────────────────────────────────────────────

  Widget _buildTimeGreeting(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          // Emoji badge
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F0),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                TimeOfDayUtil.mealEmoji(_currentPeriod),
                style: const TextStyle(fontSize: 24),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _greeting,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1C1C),
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  context.read<AuthProvider>().username ?? 'Hungry?',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF8E8E93),
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Time-of-Day Suggestion Horizontal List
  // ──────────────────────────────────────────────

  Widget _buildTimeSuggestionList(
    BuildContext context, {
    required List<(Restaurant, List<Food>)> suggestions,
    required Map<String, String> discounts,
  }) {
    // Show top 5 time-matched restaurants in a horizontal scroll
    final display = suggestions.take(5).toList();

    return SizedBox(
      height: 230,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: display.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final (restaurant, _) = display[index];
          final discount = discounts[restaurant.id];
          return _buildRestaurantCard(
            context,
            restaurant: restaurant,
            discount: discount,
          );
        },
      ),
    );
  }

  // ── \"Because You Ordered\" Section ──

  Widget _buildBecauseYouOrdered(BuildContext context, CartProvider cart) {
    // Use the most recent delivered order to personalize
    final latestOrder = _recentOrders.first;
    if (latestOrder.items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              const Icon(Icons.restaurant_rounded,
                  size: 20, color: Color(0xFFF9A825)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Because you ordered from ${latestOrder.restaurantName}',
                  style: const TextStyle(
                    color: Color(0xFF262626),
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 90,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: latestOrder.items.length.clamp(0, 4),
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final item = latestOrder.items[index];
              return _buildReorderItemCard(context, item, latestOrder, cart);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildReorderItemCard(
      BuildContext context, OrderItem item, Order order, CartProvider cart) {
    return GestureDetector(
      onTap: () {
        // Add just this single item to cart
        final cartItem = CartItem(
          id: '${item.foodId}_${item.specialInstructions ?? ''}',
          foodId: item.foodId,
          name: item.name,
          price: item.price,
          restaurantId: order.restaurantId,
          restaurantName: '',
          imageUrl: item.imageUrl,
          specialInstructions: item.specialInstructions ?? '',
          quantity: 1,
        );
        cart.addItem(cartItem);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Added ${item.name} to cart!'),
              backgroundColor: const Color(0xFF1E8E3E),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
      child: Container(
        width: 160,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFF0F0F0)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.network(
                        item.imageUrl!,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Icon(
                            Icons.restaurant,
                            size: 22,
                            color: Color(0xFFF9A825)),
                      ),
                    )
                  : const Icon(Icons.restaurant,
                      size: 22, color: Color(0xFFF9A825)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    item.name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1C1C),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Rs. ${item.price.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF8E8E93),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Quick Reorder Section ──

  Widget _buildQuickReorder(BuildContext context, CartProvider cart) {
    // Collect unique food items from all recent orders (up to 8 items)
    final allItems = <_QuickReorderItem>[];
    final seenFoodIds = <String>{};
    for (final order in _recentOrders) {
      for (final item in order.items) {
        if (seenFoodIds.add(item.foodId)) {
          allItems.add(_QuickReorderItem(
            item: item,
            order: order,
          ));
        }
      }
    }
    final displayItems = allItems.take(8).toList();

    if (displayItems.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              const Icon(Icons.bolt_rounded,
                  size: 20, color: Color(0xFFF9A825)),
              const SizedBox(width: 8),
              const Text(
                'Quick Reorder',
                style: TextStyle(
                  color: Color(0xFF262626),
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                'Tap to add',
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF8E8E93),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 130,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: displayItems.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final quickItem = displayItems[index];
              return _buildQuickReorderCard(
                context,
                item: quickItem.item,
                order: quickItem.order,
                cart: cart,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildQuickReorderCard(
    BuildContext context, {
    required OrderItem item,
    required Order order,
    required CartProvider cart,
  }) {
    return GestureDetector(
      onTap: () {
        final cartItem = CartItem(
          id: '${item.foodId}_${item.specialInstructions ?? ''}_q',
          foodId: item.foodId,
          name: item.name,
          price: item.price,
          restaurantId: order.restaurantId,
          restaurantName: '',
          imageUrl: item.imageUrl,
          specialInstructions: item.specialInstructions ?? '',
          quantity: 1,
        );
        cart.addItem(cartItem);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Added ${item.name} to cart!'),
              backgroundColor: const Color(0xFF1E8E3E),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
      child: Container(
        width: 120,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFF0F0F0)),
          boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6, offset: const Offset(0, 2),
          )],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Item image
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        item.imageUrl!,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Icon(
                            Icons.restaurant,
                            size: 24, color: Color(0xFFF9A825)),
                      ),
                    )
                  : const Icon(Icons.restaurant,
                      size: 24, color: Color(0xFFF9A825)),
            ),
            const SizedBox(height: 8),
            // Item name
            Text(
              item.name,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1C1C),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 2),
            // Price
            Text(
              'Rs. ${item.price.toStringAsFixed(0)}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Color(0xFFBB0018),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Your Favourites Section ──

  Widget _buildYourFavourites(BuildContext context) {
    final favourites = _favoriteRestaurants.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              const Icon(Icons.trending_up_rounded,
                  size: 20, color: Color(0xFFF9A825)),
              const SizedBox(width: 8),
              const Text(
                'Most Ordered',
                style: TextStyle(
                  color: Color(0xFF262626),
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),

            ],
          ),
        ),
        SizedBox(
          height: 210,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: favourites.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) => _buildFavouriteCard(
              context,
              restaurantData: favourites[index],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFavouriteCard(
    BuildContext context, {
    required Map<String, dynamic> restaurantData,
  }) {
    final name = restaurantData['name'] as String? ?? 'Restaurant';
    final bannerUrl = restaurantData['banner_url'] as String? ?? '';
    final rating = (restaurantData['rating'] as num?)?.toDouble() ?? 0;
    final deliveryTime = (restaurantData['delivery_time_minutes'] as num?)?.toInt() ?? 30;
    final orderCount = (restaurantData['user_order_count'] as num?)?.toInt() ?? 0;
    final cuisineType = restaurantData['cuisine_type'] as String? ?? '';

    Restaurant? restaurant;
    try {
      restaurant = Restaurant.fromJson(restaurantData);
    } catch (_) {}

    return GestureDetector(
      onTap: () {
        if (restaurant != null) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RestaurantMenuScreen(restaurant: restaurant!),
            ),
          );
        }
      },
      child: Container(
        width: 180,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFF0F0F0)),
          boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8, offset: const Offset(0, 3),
          )],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Banner image with cuisine badge
            Stack(
              children: [
                Image.network(
                  bannerUrl,
                  height: 100,
                  width: 180,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    height: 100,
                    width: 180,
                    color: const Color(0xFFF0F0F0),
                    child: const Icon(Icons.restaurant,
                        size: 32, color: Color(0xFFBFBFBF)),
                  ),
                ),
                if (cuisineType.isNotEmpty)
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(cuisineType,
                          style: const TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w600,
                              color: Color(0xFFBB0018))),
                    ),
                  ),
                // Order count badge (replaces heart icon)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.replay_rounded,
                            size: 10, color: Color(0xFFF9A825)),
                        const SizedBox(width: 2),
                        Text('$orderCount',
                            style: const TextStyle(
                                fontSize: 10, fontWeight: FontWeight.w700,
                                color: Color(0xFF795548))),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            // Info
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600,
                          color: Color(0xFF1A1C1C)),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded, size: 14, color: Color(0xFFFFC107)),
                      const SizedBox(width: 2),
                      Text('$rating',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600,
                              color: Color(0xFF1A1C1C))),
                      const SizedBox(width: 8),
                      const Icon(Icons.access_time, size: 12, color: Color(0xFF8E8E93)),
                      const SizedBox(width: 2),
                      Text('$deliveryTime min',
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF8E8E93))),
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
  // Surprise Me Button
  // ──────────────────────────────────────────────

  Widget _buildSurpriseMeButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          onPressed: () => _showSurpriseMeDialog(context),
          icon: const Icon(Icons.shuffle_rounded, size: 22),
          label: const Text('Surprise Me!',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFBB0018),
            foregroundColor: Colors.white,
            elevation: 2,
            shadowColor: const Color(0xFFBB0018).withValues(alpha: 0.3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ),
    );
  }

  /// Show a full-screen modal that reveals a random restaurant.
  Future<void> _showSurpriseMeDialog(BuildContext context) async {
    final token = _token;
    if (token == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _SurpriseMeDialog(
        token: token,
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Section Header
  // ──────────────────────────────────────────────

  Widget _buildSectionHeader(
    BuildContext context,
    String title, {
    String? subtitle,
    VoidCallback? onSeeAll,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF262626),
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (onSeeAll != null)
                GestureDetector(
                  onTap: onSeeAll,
                  child: Text(
                    'See all',
                    style: const TextStyle(
                      color: Color(0xFFF5222D),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF8E8E93),
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Banner Promo Section
  // ──────────────────────────────────────────────

  Widget _buildPromoBanner(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      height: 170,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFFF5222D), Color(0xFFFF7A45)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: 0,
            bottom: 0,
            child: Image.asset(
              'assets/img/BannerPizza.png',
              height: 120,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Free Delivery',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'on orders over',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const Text(
                  'Rs. 500',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Order Now',
                    style: TextStyle(
                      color: Color(0xFFF5222D),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRestaurantHorizontalList(
    BuildContext context, {
    required List<Restaurant> restaurants,
    required Map<String, String> discounts,
  }) {
    return SizedBox(
      height: 230,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: restaurants.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final restaurant = restaurants[index];
          final discount = discounts[restaurant.id];
          return _buildRestaurantCard(
            context,
            restaurant: restaurant,
            discount: discount,
          );
        },
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Restaurant Card
  // ──────────────────────────────────────────────

  Widget _buildRestaurantCard(
    BuildContext context, {
    required Restaurant restaurant,
    String? discount,
  }) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RestaurantMenuScreen(
              restaurant: restaurant,
            ),
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
            // ── Image + Discount Badge ──
            Stack(
              children: [
                Image.network(
                  restaurant.bannerUrl,
                  height: 120,
                  width: 160,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    height: 120,
                    width: 160,
                    color: const Color(0xFFF0F0F0),
                    child: const Icon(
                      Icons.restaurant,
                      color: Color(0xFFBFBFBF),
                      size: 32,
                    ),
                  ),
                ),
                if (discount != null)
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: ShapeDecoration(
                        color: const Color(0xFFF5222D),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      child: Text(
                        discount,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                // Favorite button
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Consumer(
                      builder: (context, ref, _) {
                        final isFav = ref.watch(favoritesProvider)
                            .isRestaurantFavorite(restaurant.id);                          return GestureDetector(
                            onTap: () {
                              final wasAdded = !ref.read(favoritesProvider)
                                  .isRestaurantFavorite(restaurant.id);
                              ref.read(favoritesProvider.notifier)
                                  .toggleRestaurant(restaurant.id);
                              ScaffoldMessenger.of(context).showSnackBar(
                                _favoriteSnackbar(context, wasAdded: wasAdded),
                              );
                            },
                          child: Icon(
                            isFav ? Icons.favorite : Icons.favorite_border,
                            size: 16,
                            color: isFav
                                ? const Color(0xFFF5222D)
                                : const Color(0xFF595959),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),

            // ── Card Details ──
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    restaurant.name,
                    style: const TextStyle(
                      color: Color(0xFF262626),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  // Rating row
                  Row(
                    children: [
                      const Icon(
                        Icons.star,
                        size: 14,
                        color: Color(0xFFFFC107),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        restaurant.rating.toStringAsFixed(1),
                        style: const TextStyle(
                          color: Color(0xFF595959),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (restaurant.totalReviews > 0) ...[
                        const SizedBox(width: 4),
                        Text(
                          '(${restaurant.totalReviews})',
                          style: const TextStyle(
                            color: Color(0xFF8C8C8C),
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Delivery time row
                  Row(
                    children: [
                      const Icon(
                        Icons.access_time,
                        size: 14,
                        color: Color(0xFF8C8C8C),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${restaurant.deliveryTimeMinutes} mins',
                        style: const TextStyle(
                          color: Color(0xFF8C8C8C),
                          fontSize: 12,
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
  // Favorite Snackbar
  // ──────────────────────────────────────────────

  SnackBar _favoriteSnackbar(BuildContext context, {required bool wasAdded}) {
    return SnackBar(
      content: Row(
        children: [
          Icon(
            wasAdded ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            color: Colors.white,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(wasAdded ? 'Added to favorites' : 'Removed from favorites'),
        ],
      ),
      backgroundColor: const Color(0xFF1E8E3E),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 3),
      action: wasAdded
          ? SnackBarAction(
              label: 'View all',
              textColor: Colors.white,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const FavoritesScreen(),
                  ),
                );
              },
            )
          : null,
    );
  }
}

/// Helper data class for the Quick Reorder section.
class _QuickReorderItem {
  final OrderItem item;
  final Order order;
  const _QuickReorderItem({required this.item, required this.order});
}

/// Delegate for the sticky location header that stays pinned at the top
/// while the user scrolls through restaurant content.
class _StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  _StickyHeaderDelegate({
    required this.child,
  });

  @override
  double get minExtent => 82.0;

  @override
  double get maxExtent => 82.0;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  bool shouldRebuild(_StickyHeaderDelegate oldDelegate) {
    return child != oldDelegate.child;
  }
}

/// Full-screen modal dialog that shows a random restaurant the user
/// hasn't tried yet, with options to view the menu or try another.
class _SurpriseMeDialog extends StatefulWidget {
  final String token;

  const _SurpriseMeDialog({required this.token});

  @override
  State<_SurpriseMeDialog> createState() => _SurpriseMeDialogState();
}

class _SurpriseMeDialogState extends State<_SurpriseMeDialog> {
  Map<String, dynamic>? _data;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchRestaurant();
  }

  Future<void> _fetchRestaurant() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = di.sl<ApiService>();
      final data = await api.getSurpriseMe(token: widget.token);
      if (!mounted) return;
      setState(() {
        _data = data;
        _isLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Something went wrong. Try again!';
        _isLoading = false;
      });
    }
  }

  void _openMenu(Map<String, dynamic> restaurant) {
    try {
      final restaurantObj = Restaurant.fromJson(restaurant);
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RestaurantMenuScreen(restaurant: restaurantObj),
        ),
      );
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open restaurant menu.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isLoading) _buildLoadingState(),
            if (_error != null && !_isLoading) _buildErrorState(),
            if (_data != null && !_isLoading) _buildSurpriseContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 48, height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: Color(0xFFBB0018),
            ),
          ),
          const SizedBox(height: 20),
          const Text('Finding a surprise for you...',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1C1C))),
          const SizedBox(height: 8),
          const Text('This may take a moment',
              style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93))),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.search_off_rounded, size: 56, color: Color(0xFFD9D9D9)),
          const SizedBox(height: 16),
          Text(_error!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Color(0xFF8E8E93))),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close',
                    style: TextStyle(color: Color(0xFF8E8E93))),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _fetchRestaurant,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFBB0018),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSurpriseContent() {
    final restaurant = _data!['restaurant'] as Map<String, dynamic>?;
    final alreadyOrderedFromAll = _data!['already_ordered_from_all'] == true;

    if (restaurant == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.store_mall_directory_outlined,
                size: 56, color: Color(0xFFD9D9D9)),
            const SizedBox(height: 16),
            const Text('No restaurants available right now',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Color(0xFF8E8E93))),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFBB0018),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }

    final name = restaurant['name'] as String? ?? 'Unknown';
    final bannerUrl = restaurant['banner_url'] as String? ?? '';
    final rating = (restaurant['rating'] as num?)?.toDouble() ?? 0;
    final cuisineType = restaurant['cuisine_type'] as String? ?? '';
    final deliveryTime = (restaurant['delivery_time_minutes'] as num?)?.toInt() ?? 30;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Banner Image ──
        Stack(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              child: Image.network(
                bannerUrl,
                width: double.infinity,
                height: 180,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  height: 180,
                  color: const Color(0xFFF0F0F0),
                  child: const Icon(Icons.restaurant,
                      size: 48, color: Color(0xFFBFBFBF)),
                ),
              ),
            ),
            // Gradient overlay
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0),
                      Colors.black.withValues(alpha: 0.35),
                    ],
                  ),
                ),
              ),
            ),
            // Close button
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, size: 20),
                  color: const Color(0xFF1A1C1C),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ),
            ),
            // "Surprise!" label
            Positioned(
              left: 16,
              bottom: 12,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome, size: 14, color: Color(0xFFF9A825)),
                        SizedBox(width: 4),
                        Text('Surprise!',
                            style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w700,
                                color: Color(0xFF1A1C1C))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        // ── Restaurant Info ──
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(name,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700,
                            color: Color(0xFF1A1C1C)),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.star_rounded, size: 18, color: Color(0xFFFFC107)),
                  const SizedBox(width: 4),
                  Text('$rating',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1C1C))),
                  if (cuisineType.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1F0),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(cuisineType,
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w600,
                              color: Color(0xFFBB0018))),
                    ),
                  ],
                  const SizedBox(width: 8),
                  const Icon(Icons.access_time_rounded, size: 14, color: Color(0xFF8E8E93)),
                  const SizedBox(width: 3),
                  Text('$deliveryTime min',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF8E8E93))),
                ],
              ),
            ],
          ),
        ),

        // ── "Already ordered from all" note ──
        if (alreadyOrderedFromAll)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.emoji_events_rounded, size: 16, color: Color(0xFFF9A825)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "You've tried every restaurant! Here's a top pick just for you.",
                    style: TextStyle(fontSize: 12, color: Color(0xFF795548)),
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 8),

        // ── Action Buttons ──
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Row(
            children: [
              // View Menu
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: ElevatedButton.icon(
                    onPressed: () => _openMenu(restaurant),
                    icon: const Icon(Icons.restaurant_menu_rounded, size: 18),
                    label: const Text('View Menu',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFBB0018),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Try Another
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : _fetchRestaurant,
                    icon: const Icon(Icons.shuffle_rounded, size: 18),
                    label: const Text('Try Another',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFBB0018),
                      side: const BorderSide(color: Color(0xFFBB0018)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
