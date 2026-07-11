import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart';
import '../../core/services/delivery_location_service.dart';
import '../../core/services/api_service.dart';
import '../../injection_container.dart' as di;
import '../../providers/auth_provider.dart';
import '../../providers/coupon_provider.dart';
import '../../state_providers.dart';
import 'select_address_screen.dart';
import 'selected_delivery_location.dart';
import 'payment_screen.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  SelectedDeliveryLocation? _selectedAddress;
  final _deliveryNotesCtrl = TextEditingController();
  final _couponCtrl = TextEditingController();
  late final DeliveryLocationService _locationService;
  late final CouponProvider _couponProvider;
  late final ApiService _api;

  List<Map<String, dynamic>> _availableCoupons = [];
  bool _isLoadingCoupons = true;

  @override
  void initState() {
    super.initState();
    _api = di.sl<ApiService>();
    _locationService = di.sl<DeliveryLocationService>();
    _couponProvider = CouponProvider(_api);
    // Restore the pinned location from SharedPreferences
    final saved = _locationService.loadLocation();
    if (saved != null) {
      _selectedAddress = saved;
    }

    // Fetch available coupons after the first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchAvailableCoupons();
    });
  }

  @override
  void dispose() {
    _deliveryNotesCtrl.dispose();
    _couponCtrl.dispose();
    _couponProvider.dispose();
    super.dispose();
  }

  String? get _token => context.read<AuthProvider>().token;

  // ── Available Coupons ──────────────────────────

  Future<void> _fetchAvailableCoupons() async {
    final token = _token;
    if (token == null) {
      setState(() { _isLoadingCoupons = false; });
      return;
    }

    final cart = ref.read(cartStateProvider);
    if (cart.items.isEmpty) {
      setState(() { _isLoadingCoupons = false; });
      return;
    }

    final restaurantIds = cart.items.values.map((i) => i.restaurantId).toSet();
    if (restaurantIds.length != 1) {
      setState(() { _isLoadingCoupons = false; });
      return;
    }

    try {
      final coupons = await _api.getAvailableCoupons(
        restaurantId: restaurantIds.first,
        token: token,
      );
      if (mounted) {
        setState(() {
          _availableCoupons = coupons;
          _isLoadingCoupons = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingCoupons = false;
        });
      }
    }
  }

  /// Apply a coupon by code — called from manual input or tapping a card.
  void _applyCouponCode(String code) {
    _couponCtrl.text = code;
    _applyCoupon();
  }

  // ── Coupon Validation ────────────────────────

  Future<void> _applyCoupon() async {
    final token = _token;
    if (token == null) return;

    final code = _couponCtrl.text.trim();
    if (code.isEmpty) return;

    final cart = ref.read(cartStateProvider);
    final subtotal = cart.subtotal;

    // Derive the restaurant ID from the cart (first item's restaurant)
    final restaurantIds = cart.items.values.map((i) => i.restaurantId).toSet();
    final restaurantId = restaurantIds.length == 1 ? restaurantIds.first : null;

    await _couponProvider.applyCoupon(
      code: code,
      orderTotal: subtotal,
      restaurantId: restaurantId,
      token: token,
    );

    if (_couponProvider.hasAppliedCoupon && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Coupon "${_couponProvider.appliedCode}" applied!'),
          backgroundColor: const Color(0xFF1E8E3E),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _removeCoupon() {
    _couponProvider.clearCoupon();
    _couponCtrl.clear();
  }

  // ── Order Summary ────────────────────────────

  Widget _buildOrderSummary(
    double subtotal,
    double deliveryFee,
    double discount,
    double total,
    int restaurantCount,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: ShapeDecoration(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          side: const BorderSide(width: 1, color: Color(0xFFF0F0F0)),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Title ──
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: SizedBox(
              width: double.infinity,
              child: Text(
                'Order Details',
                style: TextStyle(
                  color: Color(0xFF1C1B1B),
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  height: 1.50,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // ── Item Total ──
          _buildRow('Item Total', 'रु${subtotal.toStringAsFixed(0)}'),
          const SizedBox(height: 10),
          // ── Delivery Fee (with Free Delivery badge) ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Text(
                    'Delivery Fee',
                    style: TextStyle(
                      color: Color(0xFF5E3F3C),
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  if (deliveryFee == 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFF52C41A).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'FREE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF52C41A),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              Text(
                deliveryFee > 0 ? 'रु${deliveryFee.toStringAsFixed(0)}' : 'रु0',
                style: TextStyle(
                  color: deliveryFee == 0 ? const Color(0xFF52C41A) : const Color(0xFF5E3F3C),
                  fontSize: 14,
                  fontWeight: deliveryFee == 0 ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // ── Coupon Discount ──
          if (discount > 0)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text(
                      'Coupon Discount',
                      style: TextStyle(
                        color: Color(0xFF52C41A),
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        height: 1.50,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE6F4EA),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _couponProvider.appliedCode ?? '',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E8E3E),
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  '- रु${discount.toStringAsFixed(0)}',
                  style: const TextStyle(
                    color: Color(0xFF52C41A),
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    height: 1.50,
                  ),
                ),
              ],
            ),
          if (discount > 0) const SizedBox(height: 10),
          // ── Divider ──
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(
              width: double.infinity,
              child: Divider(
                height: 1,
                color: Color(0xFFF0F0F0),
                thickness: 1,
              ),
            ),
          ),
          // ── Total Amount ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Amount',
                style: TextStyle(
                  color: Color(0xFFBB0018),
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  height: 1.50,
                ),
              ),
              Text(
                'रु${total.toStringAsFixed(0)}',
                style: const TextStyle(
                  color: Color(0xFFBB0018),
                  fontSize: 16,
                  fontWeight: FontWeight.w400,
                  height: 1.50,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF5E3F3C),
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFF5E3F3C),
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  // ── Available Coupons Cards ────────────────────

  Widget _buildAvailableCouponsSection() {
    if (_isLoadingCoupons) {
      return const Padding(
        padding: EdgeInsets.only(top: 12),
        child: Row(
          children: [
            SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 8),
            Text('Loading offers...', style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93))),
          ],
        ),
      );
    }

    if (_availableCoupons.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Available Offers',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF262626)),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 88,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _availableCoupons.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) => _buildCouponCard(_availableCoupons[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCouponCard(Map<String, dynamic> coupon) {
    final code = coupon['code'] as String? ?? '';
    final isThisApplied = _couponProvider.hasAppliedCoupon &&
        _couponProvider.appliedCode == code;
    final discountType = coupon['discount_type'] as String? ?? 'PERCENTAGE';
    final discountValue = (coupon['discount_value'] as num?)?.toDouble() ?? 0;
    final description = coupon['description'] as String?;
    final minOrder = (coupon['min_order_amount'] as num?)?.toDouble();
    final discountLabel = discountType == 'PERCENTAGE'
        ? '${discountValue.toStringAsFixed(0)}% OFF'
        : 'रु${discountValue.toStringAsFixed(0)} OFF';

    // Build a subtitle from description and min order
    final subtitle = <String>[
      discountLabel,
      if (minOrder != null && minOrder > 0) 'Min. रु${minOrder.toStringAsFixed(0)}',
    ].join(' • ');

    return GestureDetector(
      onTap: _couponProvider.hasAppliedCoupon ? null : () => _applyCouponCode(code),
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE8E8E8)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Code badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F0),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                code,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFBB0018),
                  letterSpacing: 1,
                ),
              ),
            ),
            const Spacer(),
            // Discount + description
            Text(
              description ?? subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Color(0xFF5C5C5C)),
            ),
            const SizedBox(height: 2),
            // Show Applied / Tap to apply based on state
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isThisApplied
                    ? const Color(0xFFE6F4EA)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                isThisApplied ? 'Applied ✓' : 'Tap to apply',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isThisApplied
                      ? const Color(0xFF1E8E3E)
                      : _couponProvider.hasAppliedCoupon
                          ? const Color(0xFFBFBFBF)
                          : const Color(0xFF1967D2),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Place Order ──────────────────────────────

  void _placeOrder() {
    if (_selectedAddress == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a delivery address'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PaymentScreen(
          deliveryAddress: {
            'full_address': _selectedAddress!.address,
            'latitude': _selectedAddress!.latitude,
            'longitude': _selectedAddress!.longitude,
          },
          deliveryNotes: _deliveryNotesCtrl.text.trim().isNotEmpty
              ? _deliveryNotesCtrl.text.trim()
              : null,
          couponId: _couponProvider.couponId,
          couponDiscount: _couponProvider.discountAmount,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartStateProvider);
    final theme = Theme.of(context);

    if (cart.items.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Checkout')),
        body: const Center(
          child: Text('Your cart is empty.'),
        ),
      );
    }

    return ListenableBuilder(
      listenable: _couponProvider,
      builder: (context, _) {
        final hasCoupon = _couponProvider.hasAppliedCoupon;
        final discount = _couponProvider.discountAmount;

        // Calculate delivery fee (Rs 50 per restaurant, free if subtotal >= Rs 500)
        final double freeDeliveryThreshold = 500.0;
        final restaurantIds = cart.items.values.map((i) => i.restaurantId).toSet();
        final isFreeDelivery = cart.subtotal >= freeDeliveryThreshold;
        final deliveryFee = isFreeDelivery ? 0.0 : restaurantIds.length * 50.0;
        final total = cart.subtotal + deliveryFee - discount;

        return Scaffold(
          appBar: AppBar(title: const Text('Checkout')),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Delivery Address ──
                Text(
                  'Delivery Address',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () async {
                    final result = await Navigator.push<SelectedDeliveryLocation>(
                      context,
                      MaterialPageRoute(
                        builder: (context) => SelectAddressScreen(
                          initialLocation: _selectedAddress,
                        ),
                      ),
                    );

                    if (result != null) {
                      setState(() {
                        _selectedAddress = result;
                      });
                      _locationService.saveLocation(result);
                    }
                  },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: ShapeDecoration(
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        side: const BorderSide(width: 1, color: Color(0xFFF0F0F0)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on, color: Color(0xFFF5222D)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selectedAddress?.address ?? 'Select an address',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFF1C1B1B),
                                ),
                              ),
                              if (_selectedAddress != null)
                                const Text(
                                  'Tap to change',
                                  style: TextStyle(fontSize: 12, color: Color(0xFF999999)),
                                )
                              else
                                const Text(
                                  'Required to place order',
                                  style: TextStyle(fontSize: 12, color: Color(0xFFF5222D)),
                                ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: Color(0xFFBFBFBF)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // ── Apply Coupon ──
                const Text(
                  'Apply Coupon',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF262626),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: hasCoupon
                          ? const Color(0xFF1E8E3E)
                          : _couponProvider.error != null
                              ? const Color(0xFFF5222D)
                              : const Color(0xFFF0F0F0),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _couponCtrl,
                          enabled: !hasCoupon,
                          textCapitalization: TextCapitalization.characters,
                          style: const TextStyle(fontSize: 14, letterSpacing: 1.5),
                          decoration: InputDecoration(
                            hintText: 'Enter coupon code',
                            hintStyle: const TextStyle(color: Color(0xFFBFBFBF), fontSize: 14),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onSubmitted: (_) => _applyCoupon(),
                        ),
                      ),
                      // X remove button (outside TextField so taps always work)
                      if (hasCoupon)
                        GestureDetector(
                          onTap: _removeCoupon,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            child: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF8E8E93)),
                          ),
                        ),
                      if (!hasCoupon)
                        GestureDetector(
                          onTap: _couponProvider.isValidating ? null : _applyCoupon,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFBB0018),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: _couponProvider.isValidating
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text(
                                    'Apply',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                    ],
                  ),
                ),
                // Coupon feedback messages
                if (hasCoupon)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 4),
                    child: Text(
                      '${_couponProvider.discountDescription ?? 'Discount applied!'} tap ✕ to remove',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF1E8E3E),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                if (_couponProvider.error != null && !hasCoupon)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 4),
                    child: Text(
                      _couponProvider.error!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFFF5222D),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),

                // ── Available Coupons ──
                _buildAvailableCouponsSection(),

                const SizedBox(height: 24),

                // ── Delivery Notes ──
                const Text(
                  'Delivery Notes (Optional)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF262626),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFF0F0F0)),
                  ),
                  child: TextField(
                    controller: _deliveryNotesCtrl,
                    maxLines: 2,
                    style: const TextStyle(fontSize: 14),
                    decoration: const InputDecoration(
                      hintText: 'e.g. Near the temple, gate code: 1234',
                      hintStyle: TextStyle(color: Color(0xFFBFBFBF), fontSize: 14),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                _buildOrderSummary(cart.subtotal, deliveryFee, discount, total, restaurantIds.length),
                // Bottom padding to clear the bottomSheet
                SizedBox(height: 100 + MediaQuery.of(context).padding.bottom),
              ],
            ),
          ),
          bottomSheet: Container(
            padding: const EdgeInsets.all(16.0),
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
            ),
            child: SafeArea(
              child: GestureDetector(
                onTap: _placeOrder,
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
                      'Place Order',
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
            ),
          ),
        );
      },
    );
  }
}
