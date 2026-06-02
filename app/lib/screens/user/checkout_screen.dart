import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

  Widget _buildOrderSummary(
    double subtotal,
    double deliveryFee,
    double couponDiscount,
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
          // ── Delivery Fee ──
          _buildRow(
            'Delivery Fee',
            deliveryFee > 0 ? 'रु${deliveryFee.toStringAsFixed(0)}' : 'रु0',
          ),
          const SizedBox(height: 10),
          // ── Coupon Discount ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Coupon Discount (50%)',
                style: TextStyle(
                  color: Color(0xFF52C41A),
                  fontSize: 14,
                  
                  fontWeight: FontWeight.w400,
                  height: 1.50,
                ),
              ),
              Text(
                '- रु${couponDiscount.toStringAsFixed(0)}',
                style: const TextStyle(
                  color: Color(0xFF52C41A),
                  fontSize: 14,
                  
                  fontWeight: FontWeight.w400,
                  height: 1.50,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
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
      MaterialPageRoute(builder: (context) => const PaymentScreen()),
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

    // Calculate delivery fee per restaurant (Rs 50 each for now)
    final restaurantIds =      cart.items.values.map((i) => i.restaurantId).toSet();
    final deliveryFee = restaurantIds.length * 50.0;
    final couponDiscount = cart.subtotal * 0.5; // 50% coupon
    final total = cart.subtotal + deliveryFee - couponDiscount;

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                    builder: (context) => const SelectAddressScreen(),
                  ),
                );

                if (result != null) {
                  setState(() {
                    _selectedAddress = result;
                  });
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
            _buildOrderSummary(cart.subtotal, deliveryFee, couponDiscount, total, restaurantIds.length),
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
          child: ElevatedButton(
            onPressed: _placeOrder,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Place Order', style: TextStyle(fontSize: 16)),
          ),
        ),
      ),
    );
  }
}
