import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';
import '../../cart_provider.dart';
import '../../state_providers.dart';
import 'checkout_screen.dart';

/// Extracts a short description/subtitle from the item's specialInstructions.
/// The instructions string is pipe-delimited (e.g. "Size: Medium | Add-ons: Cheese").
/// Returns the first meaningful segment that isn't just a note.
String _extractSubtitle(CartItem item) {
  if (item.specialInstructions.isEmpty) return '';
  // Take the first part that looks like a customization (not a raw instruction)
  final parts = item.specialInstructions.split(' | ');
  final customization = parts.where((p) =>
      p.startsWith('Size:') || p.startsWith('Add-ons:') || p.startsWith('Flavor:'));
  return customization.join(' + ');
}

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartStateProvider);

    if (cart.items.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: _buildAppBar(context, ref, false),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 200,
                height: 200,
                child: Lottie.asset(
                  'assets/animations/done.json',
                  repeat: false,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Your cart is empty',
                style: TextStyle(
                  color: Color(0xFF999999),
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Add items from a restaurant to get started',
                style: TextStyle(
                  color: Color(0xFFBFBFBF),
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () => Navigator.of(context).popUntil((route) => route.isFirst),
                child: Container(
                  width: 200,
                  height: 48,
                  decoration: ShapeDecoration(
                    color: Color(0xFFF5222D),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                  ),
                  child: const Center(
                    child: Text(
                      'Browse Restaurants',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Group items by restaurant
    final groupedItems = <String, List<MapEntry<String, CartItem>>>{};
    final restaurantNames = <String, String>{};

    for (final entry in cart.items.entries) {
      groupedItems.putIfAbsent(entry.value.restaurantId, () => []);
      restaurantNames.putIfAbsent(
          entry.value.restaurantId, () => entry.value.restaurantName);
      groupedItems[entry.value.restaurantId]!.add(entry);
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(context, ref, true),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 160),
        itemCount: groupedItems.length,
        itemBuilder: (context, index) {
          final restaurantId = groupedItems.keys.elementAt(index);
          final items = groupedItems[restaurantId]!;
          final restaurantName = restaurantNames[restaurantId]!;
          return _buildRestaurantGroup(
              context, ref, restaurantName, items, cart);
        },
      ),
      bottomSheet: _buildBottomBar(context, ref, cart),
    );
  }

  // ──────────────────────────────────────────────
  // App Bar
  // ──────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar(
      BuildContext context, WidgetRef ref, bool hasItems) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(56),
      child: Container(
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
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () async {
                    if (context.mounted) Navigator.maybePop(context);
                  },
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_back_ios_new_rounded,
                        size: 16, color: Color(0xFF1A1A1A)),
                  ),
                ),
                const Spacer(),
                const Text('My Cart',
                    style: TextStyle(
                        color: Color(0xFF1A1A1A),
                        fontSize: 17,
                        fontWeight: FontWeight.w600)),
                const Spacer(),
                if (hasItems)
                  GestureDetector(
                    onTap: () =>
                        ref.read(cartStateProvider.notifier).clearCart(),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF1F0),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.delete_outline,
                          size: 18, color: Color(0xFFF5222D)),
                    ),
                  )
                else
                  const SizedBox(width: 36),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Restaurant Group
  // ──────────────────────────────────────────────

  Widget _buildRestaurantGroup(
    BuildContext context,
    WidgetRef ref,
    String restaurantName,
    List<MapEntry<String, CartItem>> items,
    CartProvider cart,
  ) {
    // If only one restaurant, skip the header for a cleaner look
    final showHeader = cart.items.values
            .map((i) => i.restaurantId)
            .toSet()
            .length >
        1;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeader) ...[
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF1F0),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.restaurant_outlined,
                        size: 14, color: Color(0xFFF5222D)),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    restaurantName,
                    style: const TextStyle(
                      color: Color(0xFF1A1A1A),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
          // Cart items with spacing: 16 as per design
          ...items.asMap().entries.map((entry) {
            final i = entry.key;
            final item = entry.value.value;
            return Padding(
              padding: EdgeInsets.only(bottom: i < items.length - 1 ? 16 : 0),
              child: _buildCartItemCard(context, ref, item),
            );
          }),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Cart Item Card (Figma Design)
  // ──────────────────────────────────────────────

  Widget _buildCartItemCard(
    BuildContext context,
    WidgetRef ref,
    CartItem item,
  ) {
    final subtitle = _extractSubtitle(item);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: ShapeDecoration(
        color: const Color(0xFFF5F5F5),
        shape: RoundedRectangleBorder(
          side: const BorderSide(width: 1, color: Color(0xFFF0F0F0)),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Image (96x96) ──
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: item.imageUrl != null
                ? Image.network(
                    item.imageUrl!,
                    width: 96,
                    height: 96,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 96,
                      height: 96,
                      color: const Color(0xFFE8E8E8),
                      child: const Icon(Icons.restaurant,
                          size: 32, color: Color(0xFFBFBFBF)),
                    ),
                  )
                : Container(
                    width: 96,
                    height: 96,
                    color: const Color(0xFFE8E8E8),
                    child: const Icon(Icons.restaurant,
                        size: 32, color: Color(0xFFBFBFBF)),
                  ),
          ),
          const SizedBox(width: 16),

          // ── Details (name, subtitle, price, quantity) ──
          Expanded(
            child: SizedBox(
              height: 96,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Top: name and subtitle
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(
                          color: Color(0xFF1C1B1B),
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          height: 1.25,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: Color(0xFF5E3F3C),
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                            height: 1.43,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),

                  // Bottom: price + quantity controls
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Price
                      Text(
                        'रु${(item.price * item.quantity).toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: Color(0xFFBB0018),
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          height: 1.40,
                        ),
                      ),

                      // Quantity controls (horizontal, matching design)
                      _buildHorizontalQuantityControls(context, ref, item),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Horizontal Quantity Controls (design style)
  // ──────────────────────────────────────────────

  Widget _buildHorizontalQuantityControls(
    BuildContext context,
    WidgetRef ref,
    CartItem item,
  ) {
    return Container(
      decoration: ShapeDecoration(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          side: const BorderSide(width: 1, color: Color(0xFFF0F0F0)),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Minus
          GestureDetector(
            onTap: () {
              if (item.quantity <= 1) {
                ref.read(cartStateProvider.notifier).removeItem(item.id);
              } else {
                ref
                    .read(cartStateProvider.notifier)
                    .updateQuantity(item.id, item.quantity - 1);
              }
            },
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              child: Icon(
                Icons.remove,
                size: 18,
                color: item.quantity > 1
                    ? const Color(0xFF1C1B1B)
                    : const Color(0xFFCCCCCC),
              ),
            ),
          ),

          // Quantity
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '${item.quantity}',
              style: const TextStyle(
                color: Color(0xFF1C1B1B),
                fontSize: 16,
                fontWeight: FontWeight.w700,
                height: 1.50,
              ),
            ),
          ),

          // Plus
          GestureDetector(
            onTap: () {
              ref
                  .read(cartStateProvider.notifier)
                  .updateQuantity(item.id, item.quantity + 1);
            },
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              child: const Icon(Icons.add, size: 18, color: Color(0xFF1C1B1B)),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Bottom Bar (Subtotal + Checkout)
  // ──────────────────────────────────────────────

  Widget _buildBottomBar(
      BuildContext context, WidgetRef ref, CartProvider cart) {
    final totalItems =
        cart.items.values.fold(0, (int s, i) => s + i.quantity);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x19000000),
            blurRadius: 6,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Subtotal row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Subtotal',
                  style: TextStyle(
                    color: Color(0xFF666666),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  'रु${cart.subtotal.toStringAsFixed(0)}',
                  style: const TextStyle(
                    color: Color(0xFF1C1B1B),
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Item count
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$totalItems item${totalItems == 1 ? '' : 's'}',
                  style: const TextStyle(
                    color: Color(0xFF999999),
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Proceed to Checkout
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const CheckoutScreen()),
              ),
              child: Container(
                width: double.infinity,
                height: 50,
                decoration: const ShapeDecoration(
                  color: Color(0xFFF5222D),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                ),
                child: const Center(
                  child: Text(
                    'Proceed to Checkout',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
