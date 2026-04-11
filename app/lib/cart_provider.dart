import 'package:flutter/material.dart';

class CartItem {
  final String foodId;
  final String name;
  final double price;
  int quantity;

  CartItem({
    required this.foodId,
    required this.name,
    required this.price,
    this.quantity = 1,
  });
}

class CartProvider with ChangeNotifier {
  String? _restaurantId;
  final Map<String, CartItem> _items = {};

  String? get restaurantId => _restaurantId;
  Map<String, CartItem> get items => {..._items};

  int get itemCount => _items.length;

  double get subtotal {
    double total = 0.0;
    _items.forEach((key, item) {
      total += item.price * item.quantity;
    });
    return total;
  }

  void addItem(String restaurantId, CartItem item) {
    if (_restaurantId != null && _restaurantId != restaurantId) {
      throw Exception('You can only order from one restaurant at a time. Please clear your cart to order from a different restaurant.');
    }

    _restaurantId = restaurantId;

    if (_items.containsKey(item.foodId)) {
      _items[item.foodId]!.quantity += item.quantity;
    } else {
      _items[item.foodId] = item;
    }
    notifyListeners();
  }

  void removeItem(String foodId) {
    _items.remove(foodId);
    if (_items.isEmpty) {
      _restaurantId = null;
    }
    notifyListeners();
  }

  void updateQuantity(String foodId, int quantity) {
    if (!_items.containsKey(foodId)) return;
    if (quantity <= 0) {
      removeItem(foodId);
    } else {
      _items[foodId]!.quantity = quantity;
      notifyListeners();
    }
  }

  void clearCart() {
    _items.clear();
    _restaurantId = null;
    notifyListeners();
  }
}
