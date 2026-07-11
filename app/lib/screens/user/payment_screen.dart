import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart';
import '../../state_providers.dart';
import '../../core/services/api_service.dart';
import '../../injection_container.dart' as di;
import '../../providers/auth_provider.dart';
import 'order_confirmed_screen.dart';

class PaymentScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic>? deliveryAddress;
  final String? deliveryNotes;
  final String? couponId;
  final double couponDiscount;

  const PaymentScreen({
    super.key,
    this.deliveryAddress,
    this.deliveryNotes,
    this.couponId,
    this.couponDiscount = 0.0,
  });

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  String _selectedMethod = 'eSewa';

  final List<_PaymentMethod> _digitalWallets = const [
    _PaymentMethod(
      id: 'eSewa',
      name: 'eSewa',
      subtitle: 'Instant digital payment',
      iconAsset: 'assets/icons/esewa.png',
    ),
    _PaymentMethod(
      id: 'khalti',
      name: 'Khalti',
      subtitle: 'Pay with Khalti Wallet',
      iconAsset: 'assets/icons/khalti.png',
    ),
  ];

  final List<_PaymentMethod> _otherMethods = const [
    _PaymentMethod(
      id: 'cod',
      name: 'Cash on Delivery',
      subtitle: 'Pay when you receive food',
      iconAsset: 'assets/icons/cashondelivery.svg',
    ),
  ];

  /// Validate that delivery address coordinates are valid and within Nepal bounds.
  /// Returns null if valid, or an error message string if invalid.
  String? _validateDeliveryAddress() {
    final addr = widget.deliveryAddress;
    if (addr == null) {
      return 'Delivery address is missing. Please set your delivery location.';
    }

    final lat = addr['latitude'];
    final lng = addr['longitude'];

    if (lat == null || lng == null) {
      return 'Delivery address has no coordinates. Please select a location on the map.';
    }

    final latNum = (lat is num) ? lat.toDouble() : double.tryParse(lat.toString());
    final lngNum = (lng is num) ? lng.toDouble() : double.tryParse(lng.toString());

    if (latNum == null || lngNum == null) {
      return 'Delivery address has invalid coordinates. Please select your location again.';
    }

    // Reject (0, 0) — default/unset coordinate
    if (latNum == 0.0 && lngNum == 0.0) {
      return 'Delivery address has default coordinates. Please set your delivery location on the map.';
    }

    // Reject coordinates outside Nepal bounds (~26–30°N, ~80–88°E)
    if (latNum < 26.0 || latNum > 30.0 || lngNum < 80.0 || lngNum > 88.0) {
      return 'Delivery address appears to be outside Nepal. Please select a valid location.';
    }

    return null;
  }

  Future<void> _confirmOrder() async {
    // Validate delivery address before placing the order
    final addressError = _validateDeliveryAddress();
    if (addressError != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.location_off_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text(addressError)),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        ),
      );
      return;
    }

    final cart = ref.read(cartStateProvider);
    final subtotal = cart.subtotal;
    final restaurantIds = cart.items.values.map((i) => i.restaurantId).toSet();
    final deliveryFee = restaurantIds.length * 50.0;
    final discount = widget.couponDiscount;
    final total = subtotal + deliveryFee - discount;

    // Get the auth token
    final token = context.read<AuthProvider>().token;
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please log in to place an order.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Take the first restaurant (grouped orders not supported yet)
    final firstItem = cart.items.values.first;
    final restaurantId = firstItem.restaurantId;

    // Build items payload matching what the backend expects
    final itemsPayload = cart.items.values.map((item) => ({
      'foodId': item.foodId,
      'name': item.name,
      'price': item.price,
      'quantity': item.quantity,
      if (item.imageUrl != null) 'imageUrl': item.imageUrl,
      if (item.specialInstructions.isNotEmpty)
        'specialInstructions': item.specialInstructions,
    })).toList();

    try {
      final api = di.sl<ApiService>();
      await api.createOrder(
        restaurantId: restaurantId,
        items: itemsPayload,
        subtotal: subtotal,
        deliveryFee: deliveryFee,
        total: total,
        deliveryAddress: widget.deliveryAddress,
        deliveryNotes: widget.deliveryNotes,
        paymentMethod: _selectedMethod,
        token: token,
      );

      // Apply coupon usage count if a coupon was applied
      if (widget.couponId != null && widget.couponId!.isNotEmpty) {
        try {
          await api.applyCoupon(couponId: widget.couponId!, token: token);
        } catch (_) {
          // Non-fatal — order is already created
          debugPrint('[Payment] Failed to mark coupon as used.');
        }
      }

      // Order created successfully — clear cart and navigate
      ref.read(cartStateProvider.notifier).clearCart();

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => OrderConfirmedScreen(
            paymentMethod: _selectedMethod,
            totalAmount: total,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to place order: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartStateProvider);    final restaurantIds = cart.items.values.map((i) => i.restaurantId).toSet();
    final deliveryFee = restaurantIds.length * 50.0;
    final subtotal = cart.subtotal;
    final discount = widget.couponDiscount;
    final total = subtotal + deliveryFee - discount;

    return Scaffold(
      backgroundColor: const Color(0xFFFBF9F9),
      appBar: _buildAppBar(),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 200),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildProgressStepper(),
            const SizedBox(height: 24),
            _buildSectionTitle('Select Digital Wallet'),
            const SizedBox(height: 16),
            ..._digitalWallets.map((m) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildPaymentCard(m),
                )),
            const SizedBox(height: 4),
            _buildSectionTitle('Other Methods'),
            const SizedBox(height: 16),
            ..._otherMethods.map((m) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _buildPaymentCard(m),
                )),
            const SizedBox(height: 4),
            _buildPromotionCard(),
          ],
        ),
      ),
      bottomSheet: _buildBottomBar(total, subtotal, deliveryFee),
    );
  }

  // ──────────────────────────────────────────────
  // App Bar
  // ──────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
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
                  onTap: () {
                    final navigator = Navigator.of(context);
                    Future.microtask(() {
                      navigator.maybePop();
                    });
                  },
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 16,
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                ),
                const Spacer(),
                const Text(
                  'Checkout',
                  style: TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                const SizedBox(width: 36),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Progress Stepper: Address → Payment → Review
  // ──────────────────────────────────────────────

  Widget _buildProgressStepper() {
    return Row(
      children: [
        _buildStep(
          number: null,
          label: 'Address',
          isCompleted: true,
          isActive: false,
        ),
        _buildConnector(isActive: true),
        _buildStep(
          number: '2',
          label: 'Payment',
          isCompleted: false,
          isActive: true,
        ),
        _buildConnector(isActive: false),
        _buildStep(
          number: '3',
          label: 'Review',
          isCompleted: false,
          isActive: false,
        ),
      ],
    );
  }

  Widget _buildStep({
    required String? number,
    required String label,
    required bool isCompleted,
    required bool isActive,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: ShapeDecoration(
            color: isCompleted || isActive
                ? const Color(0xFFF5222D)
                : const Color(0xFFE3E2E2),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(9999),
            ),
          ),
          child: Center(
            child: isCompleted
                ? const Icon(Icons.check, color: Colors.white, size: 18)
                : Text(
                    number ?? '',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isActive ? Colors.white : const Color(0xFF5D3F3C),
                      fontSize: 16,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: isActive
                ? const Color(0xFFF5222D)
                : const Color(0xFF5D3F3C),
            fontSize: 10,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            letterSpacing: 0.20,
          ),
        ),
      ],
    );
  }

  Widget _buildConnector({required bool isActive}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.only(left: 8, right: 8, bottom: 16),
        child: Container(
          height: 2,
          decoration: BoxDecoration(
            color: isActive
                ? const Color(0xFFF5222D)
                : const Color(0xFFE3E2E2),
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Section Title
  // ──────────────────────────────────────────────

  Widget _buildSectionTitle(String title) {
    return SizedBox(
      width: double.infinity,
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFF5D3F3C),
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Payment Method Card
  // ──────────────────────────────────────────────

  Widget _buildPaymentCard(_PaymentMethod method) {
    final isSelected = _selectedMethod == method.id;

    return GestureDetector(
      onTap: () => setState(() => _selectedMethod = method.id),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: ShapeDecoration(
          color: isSelected ? const Color(0xFFF5F3F3) : Colors.white,
          shape: RoundedRectangleBorder(
            side: BorderSide(
              width: 1,
              color: isSelected
                  ? const Color(0xFFF5222D)
                  : const Color(0xFFE3E2E2),
            ),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Row(
          children: [
            // Icon
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                method.iconAsset,
                width: 48,
                height: 48,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const SizedBox(
                  width: 48,
                  height: 48,
                  child: Center(
                    child: Icon(Icons.wallet, color: Color(0xFF5D3F3C), size: 30),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            // Name & subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    method.name,
                    style: const TextStyle(
                      color: Color(0xFF1B1C1C),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    method.subtitle,
                    style: const TextStyle(
                      color: Color(0xFF5D3F3C),
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Radio button
            Container(
              width: 24,
              height: 24,
              decoration: ShapeDecoration(
                shape: RoundedRectangleBorder(
                  side: BorderSide(
                    width: 2,
                    color: isSelected
                        ? const Color(0xFFF5222D)
                        : const Color(0xFFE3E2E2),
                  ),
                  borderRadius: BorderRadius.circular(9999),
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: ShapeDecoration(
                          color: const Color(0xFFF5222D),
                          shape: const RoundedRectangleBorder(
                            borderRadius: BorderRadius.all(Radius.circular(9999.0)),
                          ),
                        ),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Promotion Card (Green Gradient)
  // ──────────────────────────────────────────────

  Widget _buildPromotionCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        gradient: const LinearGradient(
          begin: Alignment(0.41, -0.41),
          end: Alignment(0.59, 1.41),
          colors: [Color(0xFF4CAF50), Color(0xFF52C41A)],
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12.0)),
        ),
      ),
      child: Stack(
        children: [
          // Decorative circle
          Positioned(
            right: -10,
            top: -10,
            child: Container(
              width: 100,
              height: 100,
              decoration: ShapeDecoration(
                color: const Color(0x1AFFFFFF),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.all(Radius.circular(9999.0)),
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'PROMOTION',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.20,
                ),
              ),
              const SizedBox(height: 4),
              const SizedBox(
                width: 338,
                child: Text(
                  'Get 15% cashback via eSewa Jatra!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: ShapeDecoration(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9999),
                  ),
                ),
                child: const Center(
                  child: Text(
                    'Link Wallet',
                    style: TextStyle(
                      color: Color(0xFF4CAF50),
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Bottom Bar (Subtotal + Delivery Fee + Total + Confirm)
  // ──────────────────────────────────────────────

  Widget _buildBottomBar(double total, double subtotal, double deliveryFee) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: const BoxDecoration(
        color: Color(0xFFFBF9F9),
        boxShadow: [
          BoxShadow(
            color: Color(0x3F000000),
            blurRadius: 50,
            offset: Offset(0, 25),
            spreadRadius: -12,
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
                    color: Color(0xFF5D3F3C),
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                Text(
                  'रु${subtotal.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Color(0xFF5D3F3C),
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Delivery Fee row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Delivery Fee',
                  style: TextStyle(
                    color: Color(0xFF5D3F3C),
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                Text(
                  'रु${deliveryFee.toStringAsFixed(2)}',
                  style: const TextStyle(
                    color: Color(0xFFF5222D),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Total row
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Total',
                    style: TextStyle(
                      color: Color(0xFF1B1C1C),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'रु${total.toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Color(0xFF1B1C1C),
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Confirm Order button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _confirmOrder,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF5222D),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                  shadowColor: const Color(0x33BB0013),
                ),
                child: const Text(
                  'Confirm Order',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
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

// ──────────────────────────────────────────────
// Data class for payment methods
// ──────────────────────────────────────────────

class _PaymentMethod {
  final String id;
  final String name;
  final String subtitle;
  final String iconAsset;

  const _PaymentMethod({
    required this.id,
    required this.name,
    required this.subtitle,
    required this.iconAsset,
  });
}
