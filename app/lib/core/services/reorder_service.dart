import '../../cart_provider.dart';
import '../../models/order.dart';

/// Utility that re-adds all items from a completed order back into the cart.
class ReorderService {
  /// Re-add all items from the given order to the cart.
  /// Returns the number of items successfully added.
  int reorder({
    required Order order,
    required CartProvider cart,
  }) {
    int addedCount = 0;

    for (final item in order.items) {
      // Create a CartItem matching the original order item
      final cartItem = CartItem(
        id: '${item.foodId}_${item.specialInstructions ?? ''}',
        foodId: item.foodId,
        name: item.name,
        price: item.price,
        restaurantId: order.restaurantId,
        restaurantName: '', // Restaurant name isn't stored in order items
        imageUrl: item.imageUrl,
        specialInstructions: item.specialInstructions ?? '',
        quantity: item.quantity,
      );

      cart.addItem(cartItem);
      addedCount++;
    }

    return addedCount;
  }
}
