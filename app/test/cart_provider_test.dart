import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app/cart_provider.dart';

void main() {
  test('CartProvider allows mixing items from different restaurants', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final cart = CartProvider(prefs);
    cart.addItem(
      CartItem(
        id: 'item1', foodId: 'f1', name: 'Momo', price: 100, 
        restaurantId: 'r1', restaurantName: 'R1'
      )
    );
    cart.addItem(
      CartItem(
        id: 'item2', foodId: 'f2', name: 'Pizza', price: 200, 
        restaurantId: 'r2', restaurantName: 'R2'
      )
    );
    
    expect(cart.items.length, 2);
    expect(cart.subtotal, 300);
  });
}
