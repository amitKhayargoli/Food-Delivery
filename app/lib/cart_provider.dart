import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  Map<String, dynamic> toJson() => {
        'id': id,
        'foodId': foodId,
        'name': name,
        'price': price,
        'restaurantId': restaurantId,
        'restaurantName': restaurantName,
        'imageUrl': imageUrl,
        'specialInstructions': specialInstructions,
        'quantity': quantity,
      };

  factory CartItem.fromJson(Map<String, dynamic> json) => CartItem(
        id: json['id'] as String,
        foodId: json['foodId'] as String,
        name: json['name'] as String,
        price: (json['price'] as num).toDouble(),
        restaurantId: json['restaurantId'] as String,
        restaurantName: json['restaurantName'] as String,
        imageUrl: json['imageUrl'] as String?,
        specialInstructions: json['specialInstructions'] as String? ?? '',
        quantity: json['quantity'] as int? ?? 1,
      );
}

class CartProvider with ChangeNotifier, WidgetsBindingObserver {
  final SharedPreferences _prefs;
  static const String _storageKey = 'cart_items';

  final Map<String, CartItem> _items = {};
  // Tracks whether a save is in-flight so we can flush it on lifecycle events
  Future<void>? _pendingSave;

  CartProvider(this._prefs) {
    _loadFromPrefs();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Flush any pending save when the app is paused or detached.
  /// This ensures the cart is persisted before a hot restart or app kill.
  @override
  Future<void> didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      await _pendingSave;
    }
  }

  Map<String, CartItem> get items => {..._items};

  int get itemCount => _items.length;

  double get subtotal {
    double total = 0.0;
    _items.forEach((key, item) {
      total += item.price * item.quantity;
    });
    return total;
  }

  void _loadFromPrefs() {
    final jsonStr = _prefs.getString(_storageKey);
    if (jsonStr == null) return;
    try {
      final List<dynamic> decoded = json.decode(jsonStr) as List<dynamic>;
      _items.clear();
      for (final entry in decoded) {
        final item = CartItem.fromJson(entry as Map<String, dynamic>);
        _items[item.id] = item;
      }
    } catch (_) {
      // If data is corrupted, just start with an empty cart
    }
    // Notify listeners so the UI reflects the loaded data
    notifyListeners();
  }

  Future<void> _saveToPrefs() async {
    try {
      final List<Map<String, dynamic>> data =
          _items.values.map((item) => item.toJson()).toList();
      await _prefs.setString(_storageKey, json.encode(data));
    } catch (e) {
      debugPrint('CartProvider._saveToPrefs error: $e');
    }
  }

  /// Initiates a save and tracks the future so it can be awaited on lifecycle events.
  void _scheduleSave() {
    _pendingSave = _saveToPrefs();
  }

  void addItem(CartItem item) {
    if (_items.containsKey(item.id)) {
      _items[item.id]!.quantity += item.quantity;
    } else {
      _items[item.id] = item;
    }
    notifyListeners();
    _scheduleSave();
  }

  void removeItem(String id) {
    _items.remove(id);
    notifyListeners();
    _scheduleSave();
  }

  void updateQuantity(String id, int quantity) {
    if (!_items.containsKey(id)) return;
    if (quantity <= 0) {
      removeItem(id);
    } else {
      _items[id]!.quantity = quantity;
      notifyListeners();
      _scheduleSave();
    }
  }

  void clearCart() {
    _items.clear();
    notifyListeners();
    _scheduleSave();
  }
}

