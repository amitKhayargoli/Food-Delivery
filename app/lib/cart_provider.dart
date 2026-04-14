import 'package:flutter/material.dart';

class CartItem {
  final String id; // unique id combining foodId and specialInstructions
  final String foodId;
  final String name;
  final double price;
  final String restaurantId;
  final String restaurantName;
  final String? imageUrl;
  final String specialInstructions;
  int quantity;

  CartItem({
    required this.id,
    required this.foodId,
    required this.name,
    required this.price,
    required this.restaurantId,
    required this.restaurantName,
    this.imageUrl,
    this.specialInstructions = '',
    this.quantity = 1,
  });
}

class CartProvider with ChangeNotifier {
  final Map<String, CartItem> _items = {};

  Map<String, CartItem> get items => {..._items};

  int get itemCount => _items.length;

  double get subtotal {
    double total = 0.0;
    _items.forEach((key, item) {
      total += item.price * item.quantity;
    });
    return total;
  }

  void addItem(CartItem item) {
    if (_items.containsKey(item.id)) {
      _items[item.id]!.quantity += item.quantity;
    } else {
      _items[item.id] = item;
    }
    notifyListeners();
  }

  void removeItem(String id) {
    _items.remove(id);
    notifyListeners();
  }

  void updateQuantity(String id, int quantity) {
    if (!_items.containsKey(id)) return;
    if (quantity <= 0) {
      removeItem(id);
    } else {
      _items[id]!.quantity = quantity;
      notifyListeners();
    }
  }

  void clearCart() {
    _items.clear();
    notifyListeners();
  }
}
