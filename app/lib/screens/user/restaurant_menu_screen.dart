import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/models.dart';
import '../../cart_provider.dart';
import '../../state_providers.dart';
import 'cart_screen.dart';
import 'food_details_screen.dart';

class RestaurantMenuScreen extends ConsumerStatefulWidget {
  final Restaurant restaurant;

  const RestaurantMenuScreen({super.key, required this.restaurant});

  @override
  ConsumerState<RestaurantMenuScreen> createState() => _RestaurantMenuScreenState();
}

class _RestaurantMenuScreenState extends ConsumerState<RestaurantMenuScreen> {
  // Tracks quantity per food item (0 = not in cart, not shown)
  final Map<String, int> _quantities = {};

  @override
  void initState() {
    super.initState();
    for (final food in widget.restaurant.foods) {
      _quantities[food.id] = 0;
    }
  }

  int get _totalItems => _quantities.values.fold(0, (sum, q) => sum + q);

  double get _totalPrice {
    double total = 0;
    for (final food in widget.restaurant.foods) {
      final qty = _quantities[food.id] ?? 0;
      if (qty > 0) total += food.price * qty;
    }
    return total;
  }

  void _increment(Food food) {
    setState(() {
      _quantities[food.id] = (_quantities[food.id] ?? 0) + 1;
    });
    _syncToCart(food);
  }

  void _decrement(Food food) {
    final current = _quantities[food.id] ?? 0;
    if (current <= 0) return;
    setState(() {
      _quantities[food.id] = current - 1;
    });
    _syncToCart(food);
  }

  void _addToCart(Food food) {
    setState(() {
      _quantities[food.id] = 1;
    });
    _syncToCart(food);
  }

  void _syncToCart(Food food) {
    final qty = _quantities[food.id] ?? 0;
    final cart = ref.read(cartStateProvider);
    final itemKey = '${food.id}_';

    if (qty > 0) {
      if (cart.items.containsKey(itemKey)) {
        cart.updateQuantity(itemKey, qty);
      } else {
        cart.addItem(CartItem(
          id: itemKey,
          foodId: food.id,
          name: food.name,
          price: food.price,
          restaurantId: widget.restaurant.id,
          restaurantName: widget.restaurant.name,
          imageUrl: food.imageUrl,
          quantity: qty,
        ));
      }
    } else {
      cart.removeItem(itemKey);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Main scrollable content
          SingleChildScrollView(
            child: Column(
              children: [
                // ── Banner Image ──
                _buildBanner(),

                // ── Restaurant Info ──
                _buildRestaurantInfo(),

                // ── Offer Banner ──
                _buildOfferBanner(),

                // ── Bestsellers Section ──
                _buildBestsellersSection(),

                // Bottom padding so content isn't hidden behind the cart bar
                if (_totalItems > 0) const SizedBox(height: 80),
              ],
            ),
          ),

          // ── Bottom Cart Bar ──
          if (_totalItems > 0) _buildBottomCartBar(),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Banner Image
  // ──────────────────────────────────────────────

  Widget _buildBanner() {
    return SizedBox(
      width: double.infinity,
      height: 240,
      child: Stack(
        children: [
          // Background image
          Image.network(
            widget.restaurant.bannerUrl,
            width: double.infinity,
            height: 240,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              color: const Color(0xFFF0F0F0),
              child: const Center(
                child: Icon(Icons.restaurant, size: 48, color: Color(0xFFBFBFBF)),
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
                    Colors.black.withValues(alpha: 0.30),
                  ],
                ),
              ),
            ),
          ),
          // Back button
          Positioned(
            left: 16,
            top: MediaQuery.of(context).padding.top + 4,
            child: GestureDetector(
              onTap: () => Future.microtask(() {
                if (mounted) Navigator.maybePop(context);
              }),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.90),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 18,
                  color: Color(0xFF1A1A1A),
                ),
              ),
            ),
          ),
          // Favorite button
          Positioned(
            right: 16,
            top: MediaQuery.of(context).padding.top + 4,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.90),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.favorite_border,
                size: 18,
                color: Color(0xFF595959),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Restaurant Info
  // ──────────────────────────────────────────────

  Widget _buildRestaurantInfo() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x0C000000),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.restaurant.name,
            style: const TextStyle(
              color: Color(0xFF1A1A1A),
              fontSize: 22,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.star, size: 16, color: Color(0xFFFFC107)),
              const SizedBox(width: 6),
              Text(
                widget.restaurant.rating.toString(),
                style: const TextStyle(
                  color: Color(0xFF333333),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                '(2K+)',
                style: TextStyle(
                  color: Color(0xFF333333),
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                '•',
                style: TextStyle(
                  color: Color(0xFF666666),
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${widget.restaurant.deliveryTimeMinutes} mins',
                style: const TextStyle(
                  color: Color(0xFF666666),
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                '•',
                style: TextStyle(
                  color: Color(0xFF666666),
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'Open Now',
                style: TextStyle(
                  color: Color(0xFF52C41A),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Offer Banner
  // ──────────────────────────────────────────────

  Widget _buildOfferBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: ShapeDecoration(
          color: const Color(0xFFFFF1F0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Text(
                'Flat 50% OFF on Orders from\nRs. 500 to 800',
                style: TextStyle(
                  color: Color(0xFFF5222D),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  height: 1.5,
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'View offers',
                  style: TextStyle(
                    color: Color(0xFFF5222D),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: Color(0xFFF5222D),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Bestsellers Section
  // ──────────────────────────────────────────────

  Widget _buildBestsellersSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Bestsellers',
            style: TextStyle(
              color: Color(0xFF1A1A1A),
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          ...widget.restaurant.foods.map((food) => _buildFoodItem(food)),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Food Item
  // ──────────────────────────────────────────────

  Widget _buildFoodItem(Food food) {
    final qty = _quantities[food.id] ?? 0;

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FoodDetailsScreen(
              food: food,
              restaurant: widget.restaurant,
            ),
          ),
        );
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(width: 1, color: Color(0xFFE8E8E8)),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
          // Food image
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              food.imageUrl,
              width: 80,
              height: 80,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                width: 80,
                height: 80,
                color: const Color(0xFFF0F0F0),
                child: const Icon(Icons.restaurant, color: Color(0xFFBFBFBF), size: 28),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Name & Price
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  food.name,
                  style: const TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  'रु${food.price.toStringAsFixed(0)}',
                  style: const TextStyle(
                    color: Color(0xFF333333),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          // ADD button or Quantity controls
          if (qty == 0)
            _buildAddButton(food)
          else
            _buildQuantityControls(food, qty),
        ],
      ),
    ),
  );
  }

  // ──────────────────────────────────────────────
  // ADD Button
  // ──────────────────────────────────────────────

  Widget _buildAddButton(Food food) {
    return GestureDetector(
      onTap: () => _addToCart(food),
      child: Container(
        width: 70,
        height: 32,
        decoration: ShapeDecoration(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            side: const BorderSide(width: 1, color: Color(0xFFF5222D)),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: const Center(
          child: Text(
            'ADD',
            style: TextStyle(
              color: Color(0xFFF5222D),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Quantity Controls (-, count, +)
  // ──────────────────────────────────────────────

  Widget _buildQuantityControls(Food food, int qty) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Minus button
        GestureDetector(
          onTap: () => _decrement(food),
          child: Container(
            width: 32,
            height: 32,
            decoration: ShapeDecoration(
              color: const Color(0xFFF5222D),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Center(
              child: Icon(Icons.remove, size: 18, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Quantity count
        SizedBox(
          width: 24,
          child: Text(
            '$qty',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF1A1A1A),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Plus button
        GestureDetector(
          onTap: () => _increment(food),
          child: Container(
            width: 32,
            height: 32,
            decoration: ShapeDecoration(
              color: const Color(0xFFF5222D),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Center(
              child: Icon(Icons.add, size: 18, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────
  // Bottom Cart Bar
  // ──────────────────────────────────────────────

  Widget _buildBottomCartBar() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(width: 1, color: Color(0xFFE8E8E8)),
          ),
          boxShadow: [
            BoxShadow(
              color: Color(0x0C000000),
              blurRadius: 2,
              offset: Offset(0, -1),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Total price
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.shopping_bag_outlined,
                    size: 20,
                    color: Color(0xFF1A1A1A),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'रु${_totalPrice.toStringAsFixed(0)}',
                    style: const TextStyle(
                      color: Color(0xFF1A1A1A),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              // View Cart button
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const CartScreen()),
                  );
                },
                child: Container(
                  width: 160,
                  height: 48,
                  decoration: ShapeDecoration(
                    color: const Color(0xFFF5222D),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Center(
                    child: Text(
                      'View Cart',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
