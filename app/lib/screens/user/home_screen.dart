import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' hide Consumer;
import '../../data/mock_data.dart';
import '../../models/models.dart';
import '../../models/order.dart';
import '../../cart_provider.dart';
import '../../core/services/api_service.dart';
import '../../core/services/reorder_service.dart';
import '../../injection_container.dart' as di;
import '../../providers/auth_provider.dart';
import '../../state_providers.dart';
import 'restaurant_menu_screen.dart';
import 'delivery_address_map_screen.dart';
import 'selected_delivery_location.dart';

class UserHomeScreen extends ConsumerStatefulWidget {
  const UserHomeScreen({super.key});

  @override
  ConsumerState<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends ConsumerState<UserHomeScreen> {
  String _currentAddress = 'Jhamsikhel, Lalitpur';
  List<Order> _recentOrders = [];
  bool _isLoadingHistory = true;
  String? _historyError;

  // Discount offers mapped by restaurant ID
  static const Map<String, String> _restaurantDiscounts = {
    'r1': 'Flat 30% OFF',
    'r2': 'Flat 10% OFF',
    'r3': 'Flat 20% OFF',
  };

  static const List<Map<String, dynamic>> _topPicks = [
    {'name': 'Thai Delight', 'rating': 4.6, 'time': '28 mins', 'discount': 'Flat 25% OFF'},
    {'name': 'Pasta Palace', 'rating': 4.5, 'time': '30 mins', 'discount': 'Flat 20% OFF'},
    {'name': 'Noodle Bar', 'rating': 4.4, 'time': '22 mins', 'discount': 'Flat 30% OFF'},
  ];

  // Map top picks to actual restaurants
  List<Restaurant> _getTopPickRestaurants() {
    return mockRestaurants.take(_topPicks.length).toList();
  }

  String? get _token => context.read<AuthProvider>().token;

  @override
  void initState() {
    super.initState();
    _fetchOrderHistory();
  }

  Future<void> _fetchOrderHistory() async {
    final token = _token;
    if (token == null) {
      setState(() {
        _isLoadingHistory = false;
      });
      return;
    }

    try {
      final api = di.sl<ApiService>();
      final response = await api.getOrderHistory(token: token, limit: 10);
      if (mounted) {
        setState(() {
          // Only show DELIVERED orders for quick reorder
          _recentOrders = response.orders
              .map((o) => Order.fromJson(o))
              .where((o) => o.status == OrderStatus.delivered)
              .take(3)
              .toList();
          _isLoadingHistory = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingHistory = false;
          _historyError = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPickRestaurants = _getTopPickRestaurants();
    final cartProvider = context.read<CartProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── Sticky Location Header (SliverPersistentHeader, pinned) ──
            SliverPersistentHeader(
              pinned: true,
              delegate: _StickyHeaderDelegate(
                child: _buildLocationHeader(context),
              ),
            ),

            // ── Scrollable Content ──
            SliverList(
              delegate: SliverChildListDelegate([
                // ── Quick Reorder Section (only if orders exist) ──
                if (_recentOrders.isNotEmpty) ...[
                  _buildQuickReorder(context, cartProvider),
                ],

                // ── Promo Banner ──
                _buildPromoBanner(context),

                // ── New Near You Section ──
                _buildSectionHeader(context, 'New Near You', onSeeAll: () {}),
                _buildRestaurantHorizontalList(
                  context,
                  restaurants: mockRestaurants,
                  discounts: _restaurantDiscounts,
                ),

                // ── Top Picks For You Section ──
                _buildSectionHeader(context, 'Top Picks For You', onSeeAll: () {}),
                _buildRestaurantHorizontalList(
                  context,
                  restaurants: topPickRestaurants,
                  discounts: {
                    for (int i = 0; i < topPickRestaurants.length; i++)
                      topPickRestaurants[i].id: _topPicks[i]['discount'] as String,
                  },
                ),

                // ── Because You Ordered Section ──
                if (_recentOrders.isNotEmpty) ...[
                  _buildBecauseYouOrdered(context, cartProvider),
                ],

                const SizedBox(height: 24),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  // ── "Because You Ordered" Section ──

  Widget _buildBecauseYouOrdered(BuildContext context, CartProvider cart) {
    // Use the most recent delivered order to personalize
    final latestOrder = _recentOrders.first;

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
                  'Because you ordered from #${latestOrder.orderNumber}',
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              const Icon(Icons.replay_rounded,
                  size: 20, color: Color(0xFFBB0018)),
              const SizedBox(width: 8),
              const Text(
                'Quick Reorder',
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
          height: 90,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _recentOrders.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final order = _recentOrders[index];
              return _buildReorderCard(context, order, cart);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildReorderCard(BuildContext context, Order order, CartProvider cart) {
    final itemCount = order.items.length;
    final reorderService = ReorderService();

    return GestureDetector(
      onTap: () {
        // Reorder on tap
        final added = reorderService.reorder(order: order, cart: cart);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Added $added items to your cart!'),
              backgroundColor: const Color(0xFF1E8E3E),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
      child: Container(
        width: 180,
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
                color: const Color(0xFFFFF1F0),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.receipt_long_rounded,
                  color: Color(0xFFBB0018), size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '#${order.orderNumber}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1C1C),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$itemCount item${itemCount > 1 ? 's' : ''}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF8E8E93),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.replay_rounded,
                size: 18, color: Color(0xFFBB0018)),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Location Header
  // ──────────────────────────────────────────────

  Widget _buildLocationHeader(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final result = await Navigator.push<SelectedDeliveryLocation>(
          context,
          MaterialPageRoute(
            builder: (context) => const DeliveryAddressMapScreen(),
          ),
        );
        if (result != null && mounted) {
          setState(() => _currentAddress = result.address);
        }
      },
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
                  Text(
                    'Delivering To',
                    style: TextStyle(
                      color: const Color(0xFF262626),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          _currentAddress,
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

  // ──────────────────────────────────────────────
  // Section Header
  // ──────────────────────────────────────────────

  Widget _buildSectionHeader(
    BuildContext context,
    String title, {
    VoidCallback? onSeeAll,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
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
                              .isRestaurantFavorite(restaurant.id);
                          return GestureDetector(
                            onTap: () {
                              ref.read(favoritesProvider.notifier)
                                  .toggleRestaurant(restaurant.id);
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
                        restaurant.rating.toString(),
                        style: const TextStyle(
                          color: Color(0xFF595959),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
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
