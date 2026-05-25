import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state_providers.dart';
import 'delivery_address_map_screen.dart';
import 'selected_delivery_location.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  SelectedDeliveryLocation? _selectedAddress;

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

    // In a real app, this would make an API call to create the order.
    // For now, we just clear the cart and show success.
    ref.read(cartStateProvider.notifier).clearCart();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Order Placed Successfully!'),
        backgroundColor: Colors.green,
      ),
    );

    // Pop back to home screen
    Navigator.of(context).popUntil((route) => route.isFirst);
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
    final restaurantIds = cart.items.values.map((i) => i.restaurantId).toSet();
    final deliveryFee = restaurantIds.length * 50.0;
    final total = cart.subtotal + deliveryFee;

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
            Card(
              child: ListTile(
                leading: const Icon(Icons.location_on, color: Colors.red),
                title: Text(_selectedAddress?.address ?? 'Select an address'),
                subtitle: _selectedAddress != null
                    ? const Text('Tap to change')
                    : const Text('Required to place order'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final result = await Navigator.push<SelectedDeliveryLocation>(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const DeliveryAddressMapScreen(),
                    ),
                  );

                  if (result != null) {
                    setState(() {
                      _selectedAddress = result;
                    });
                  }
                },
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Order Summary',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Items Total'),
                        Text('Rs ${cart.subtotal.toStringAsFixed(2)}'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Delivery Fee (${restaurantIds.length} location${restaurantIds.length > 1 ? 's' : ''})'),
                        Text('Rs ${deliveryFee.toStringAsFixed(2)}'),
                      ],
                    ),
                    const Divider(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total to Pay',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Text(
                          'Rs ${total.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
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
