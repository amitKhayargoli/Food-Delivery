import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/models.dart';
import '../../cart_provider.dart';
import '../../state_providers.dart';
import '../../data/mock_data.dart';

class FoodDetailsScreen extends ConsumerStatefulWidget {
  final Food food;
  final Restaurant restaurant;

  const FoodDetailsScreen({
    super.key,
    required this.food,
    required this.restaurant,
  });

  @override
  ConsumerState<FoodDetailsScreen> createState() => _FoodDetailsScreenState();
}

class _FoodDetailsScreenState extends ConsumerState<FoodDetailsScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  /// Whether this food item has size selection (e.g., pizza).
  bool get _hasSizes => widget.food.sizes.isNotEmpty;

  /// The add-on set for this food's category, or null if none defined.
  AddOnSet? get _addOnSet {
    final sets = mockAddOnSets.where(
      (set) => set.categoryId == widget.food.categoryId,
    );
    return sets.isNotEmpty ? sets.first : null;
  }

  /// Selected size index (only relevant when [_hasSizes] is true).
  /// Defaults to the popular size, or the first size.
  int _selectedSize = 0;

  /// Selected add-on indices within the current add-on set.
  final Set<int> _selectedAddOns = {};

  int _quantity = 1;
  final TextEditingController _instructionsController = TextEditingController();

  FoodSize get _selectedFoodSize => widget.food.sizes[_selectedSize];

  double get _addOnPrice =>
      _selectedAddOns.fold(0.0, (sum, i) => sum + (_addOnSet?.addOns[i].price ?? 0));

  double get _basePrice => _hasSizes ? _selectedFoodSize.price : widget.food.price;

  double get _itemPrice => _basePrice + _addOnPrice;

  double get _totalPrice => _itemPrice * _quantity;

  // Carousel images — main food image + placeholder angles
  List<String> get _images => [
        widget.food.imageUrl,
        'https://placehold.co/402x380/FFF1F0/F5222D?text=Angle+2',
        'https://placehold.co/402x402/FFF1F0/F5222D?text=Angle+3',
        'https://placehold.co/430x287/FFF1F0/F5222D?text=Angle+4',
      ];

  @override
  void initState() {
    super.initState();
    // Default to popular size or first size
    if (_hasSizes) {
      final popularIndex = widget.food.sizes.indexWhere((s) => s.isPopular);
      _selectedSize = popularIndex >= 0 ? popularIndex : 0;
    }
    _pageController.addListener(() {
      final page = _pageController.page?.round() ?? 0;
      if (page != _currentPage) {
        setState(() => _currentPage = page);
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  void _addToCart() {
    final instructions = _instructionsController.text.trim();
    final addOnNames =
        _selectedAddOns.map((i) => _addOnSet?.addOns[i].name ?? '').join(', ');

    final sizePart = _hasSizes ? '$_selectedSize' : 'x';
    final cartItem = CartItem(
      id: '${widget.food.id}_${sizePart}_${_selectedAddOns.join('|')}',
      foodId: widget.food.id,
      name: _hasSizes
          ? '${widget.food.name} (${_selectedFoodSize.name})'
          : widget.food.name,
      price: _itemPrice,
      restaurantId: widget.restaurant.id,
      restaurantName: widget.restaurant.name,
      imageUrl: widget.food.imageUrl,
      specialInstructions: [
        if (_hasSizes) 'Size: ${_selectedFoodSize.name}',
        if (addOnNames.isNotEmpty) 'Add-ons: $addOnNames',
        if (instructions.isNotEmpty) instructions,
      ].join(' | '),
      quantity: _quantity,
    );

    final cart = ref.read(cartStateProvider);
    cart.addItem(cartItem);

    // Show a quick confirmation then pop back
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${cartItem.name} added to cart'),
          backgroundColor: const Color(0xFF52C41A),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
          duration: const Duration(milliseconds: 1200),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
    }

    // Pop back after a brief delay so user sees the confirmation
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) Navigator.maybePop(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // ── Image Carousel (fixed at top) ──
          _buildImageCarousel(),

          // ── Scrollable Content ──
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFoodInfo(),
                  _buildDescription(),
                  if (_hasSizes) _buildChooseSize(),
                  if (_addOnSet != null) _buildCustomizeSection(),
                  _buildSpecialInstructions(),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomSheet: _buildBottomBar(),
    );
  }

  // ══════════════════════════════════════════════
  // 1. Image Carousel
  // ══════════════════════════════════════════════

  Widget _buildImageCarousel() {
    final topSafe = MediaQuery.of(context).padding.top;
    return SizedBox(
      width: double.infinity,
      height: 280,
      child: Stack(
        children: [
          // Swipeable images
          PageView.builder(
            controller: _pageController,
            itemCount: _images.length,
            itemBuilder: (context, index) => Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  _images[index],
                  width: double.infinity,
                  height: 280,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    color: const Color(0xFFF0F0F0),
                    child: const Center(
                      child: Icon(Icons.image_outlined,
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
                          Colors.black.withValues(alpha: 0.20),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Back button
          Positioned(
            left: 16,
            top: topSafe + 8,
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
                  color: Color(0xFF333333),
                ),
              ),
            ),
          ),

          // Favorite button
          Positioned(
            right: 16,
            top: topSafe + 8,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.90),
                shape: BoxShape.circle,
              ),
              child: Consumer(
                builder: (context, ref, _) {
                  final isFav = ref.watch(favoritesProvider)
                      .isFoodFavorite(widget.food.id);
                  return GestureDetector(
                    onTap: () {
                      ref.read(favoritesProvider.notifier)
                          .toggleFood(widget.food.id);
                    },
                    child: Icon(
                      isFav ? Icons.favorite : Icons.favorite_border,
                      size: 18,
                      color: isFav
                          ? const Color(0xFFF5222D)
                          : const Color(0xFF333333),
                    ),
                  );
                },
              ),
            ),
          ),

          // Page indicator badge (x/4)
          Positioned(
            right: 16,
            bottom: 40,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.60),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${_currentPage + 1}/${_images.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),

          // Dot indicators
          Positioned(
            left: 0,
            right: 0,
            bottom: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_images.length, (index) {
                final active = index == _currentPage;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.50),
                    shape: BoxShape.circle,
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════
  // 2. Food Info
  // ══════════════════════════════════════════════

  Widget _buildFoodInfo() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.food.name,
            style: const TextStyle(
              color: Color(0xFF1A1A1A),
              fontSize: 22,
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.star, size: 14, color: Color(0xFFFFC107)),
              const SizedBox(width: 6),
              const Text(
                '4.8',
                style: TextStyle(
                  color: Color(0xFF333333),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                '(850+ ratings)',
                style: TextStyle(
                  color: Color(0xFF666666),
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                '•',
                style: TextStyle(
                  color: Color(0xFF666666),
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Bestseller',
                style: TextStyle(
                  color: Color(0xFFF5222D),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════
  // 3. Description
  // ══════════════════════════════════════════════

  Widget _buildDescription() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Text(
        widget.food.description.isNotEmpty
            ? widget.food.description
            : 'Combines a crunchy crust with either crispy breaded chicken '
                'as a topping or a low-carb crust made entirely from ground chicken.',
        style: const TextStyle(
          color: Color(0xFF666666),
          fontSize: 14,
          fontWeight: FontWeight.w400,
          height: 1.63,
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════
  // 4. Choose Size (only shown when food has sizes)
  // ══════════════════════════════════════════════

  Widget _buildChooseSize() {
    final sizes = widget.food.sizes;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Choose Size',
            style: TextStyle(
              color: Color(0xFF1A1A1A),
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          ...List.generate(sizes.length, (i) {
            return Padding(
              padding: EdgeInsets.only(bottom: i < sizes.length - 1 ? 8 : 0),
              child: _buildSizeCard(i),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSizeCard(int index) {
    final size = widget.food.sizes[index];
    final selected = index == _selectedSize;
    return GestureDetector(
      onTap: () => setState(() => _selectedSize = index),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: ShapeDecoration(
          color: selected ? const Color(0xFFFFF1F0) : Colors.white,
          shape: RoundedRectangleBorder(
            side: BorderSide(
              width: 1,
              color: selected ? const Color(0xFFF5222D) : const Color(0xFFE8E8E8),
            ),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Left: name + weight
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      size.name,
                      style: const TextStyle(
                        color: Color(0xFF1A1A1A),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (size.isPopular) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: const ShapeDecoration(
                          color: Color(0xFFFFF1F0),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.all(Radius.circular(4)),
                          ),
                        ),
                        child: const Text(
                          'Most Popular',
                          style: TextStyle(
                            color: Color(0xFFF5222D),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  size.weight,
                  style: const TextStyle(
                    color: Color(0xFF999999),
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
            // Right: price + radio
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'रु${size.price.toStringAsFixed(0)}',
                  style: const TextStyle(
                    color: Color(0xFF333333),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 20,
                  height: 20,
                  decoration: ShapeDecoration(
                    shape: RoundedRectangleBorder(
                      side: BorderSide(
                        width: 2,
                        color: selected
                            ? const Color(0xFFF5222D)
                            : const Color(0xFFD9D9D9),
                      ),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  child: selected
                      ? Center(
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: const ShapeDecoration(
                              color: Color(0xFFF5222D),
                              shape: CircleBorder(),
                            ),
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════
  // 5. Customize Your Order (only shown when add-on set exists)
  // ══════════════════════════════════════════════

  Widget _buildCustomizeSection() {
    final addOns = _addOnSet!.addOns;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Customize Your Order',
            style: TextStyle(
              color: Color(0xFF1A1A1A),
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 3),
          const Text(
            'Optional add-ons',
            style: TextStyle(
              color: Color(0xFF999999),
              fontSize: 13,
              fontWeight: FontWeight.w400,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 9),
          ...List.generate(addOns.length, (i) {
            return Padding(
              padding: EdgeInsets.only(bottom: i < addOns.length - 1 ? 12 : 0),
              child: _buildAddOnCard(i),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildAddOnCard(int index) {
    final addOn = _addOnSet!.addOns[index];
    final selected = _selectedAddOns.contains(index);
    return GestureDetector(
      onTap: () {
        setState(() {
          if (selected) {
            _selectedAddOns.remove(index);
          } else {
            _selectedAddOns.add(index);
          }
        });
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 6.75),
        decoration: const ShapeDecoration(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Left: image + name + price
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: ShapeDecoration(
                    image: DecorationImage(
                      image: NetworkImage(addOn.imageUrl),
                      fit: BoxFit.fill,
                    ),
                    shape: const CircleBorder(),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      addOn.name,
                      style: const TextStyle(
                        color: Color(0xFF1A1A1A),
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        height: 1.5,
                      ),
                    ),
                    Text(
                      '+ रु${addOn.price.toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: Color(0xFF666666),
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        height: 1.43,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            // Right: toggle switch
            Container(
              width: 48,
              height: 24,
              padding: EdgeInsets.only(
                left: selected ? 26 : 2,
                right: selected ? 2 : 26,
              ),
              decoration: ShapeDecoration(
                color: selected
                    ? const Color(0xFFF5222D)
                    : const Color(0xFFD9D9D9),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              child: Container(
                width: 20,
                height: 20,
                decoration: const ShapeDecoration(
                  color: Colors.white,
                  shape: CircleBorder(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════
  // 6. Special Instructions
  // ══════════════════════════════════════════════

  Widget _buildSpecialInstructions() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Special Instructions',
            style: TextStyle(
              color: Color(0xFF666666),
              fontSize: 14,
              fontWeight: FontWeight.w500,
              height: 1.43,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 88),
            child: TextField(
              controller: _instructionsController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Any specific requests? (Optional)',
                hintStyle: const TextStyle(
                  color: Color(0xFF999999),
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFE8E8E8)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFFE8E8E8)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      const BorderSide(color: Color(0xFFF5222D), width: 1.5),
                ),
                contentPadding:
                    const EdgeInsets.fromLTRB(12, 11.5, 12, 11.5),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════
  // 7. Bottom Bar (Quantity + Add to Cart)
  // ══════════════════════════════════════════════

  Widget _buildBottomBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
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
            // ── Quantity row ──
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Quantity',
                  style: TextStyle(
                    color: Color(0xFF666666),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    height: 1.5,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Minus button
                    GestureDetector(
                      onTap: () {
                        if (_quantity > 1) setState(() => _quantity--);
                      },
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: ShapeDecoration(
                          shape: RoundedRectangleBorder(
                            side: BorderSide(
                              width: 1,
                              color: _quantity > 1
                                  ? const Color(0xFFE8E8E8)
                                  : const Color(0xFFF0F0F0),
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.remove,
                            size: 20,
                            color: _quantity > 1
                                ? const Color(0xFF1A1A1A)
                                : const Color(0xFFCCCCCC),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 24,
                      child: Text(
                        '$_quantity',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF1A1A1A),
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          height: 1.56,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Plus button
                    GestureDetector(
                      onTap: () => setState(() => _quantity++),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: const ShapeDecoration(
                          color: Color(0xFFF5222D),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.all(Radius.circular(8)),
                          ),
                        ),
                        child: const Center(
                          child: Icon(Icons.add, size: 20, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            // ── Add to Cart ──
            GestureDetector(
              onTap: _addToCart,
              child: Container(
                width: double.infinity,
                height: 52,
                decoration: const ShapeDecoration(
                  color: Color(0xFFF5222D),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(),
                    const Text(
                      'Add to Cart',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1.5,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'रु${_totalPrice.toStringAsFixed(0)}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(width: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
