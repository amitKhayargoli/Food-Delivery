/// Status of an order throughout its lifecycle
enum OrderStatus {
  pending('PENDING'),
  accepted('ACCEPTED'),
  preparing('PREPARING'),
  ready('READY'),
  pickedUp('PICKED_UP'),
  delivered('DELIVERED'),
  cancelled('CANCELLED'),
  rejected('REJECTED');

  final String value;
  const OrderStatus(this.value);

  static OrderStatus fromString(String s) {
    return OrderStatus.values.firstWhere(
      (e) => e.value == s,
      orElse: () => OrderStatus.pending,
    );
  }
}

/// A single item within an order
class OrderItem {
  final String foodId;
  final String name;
  final double price;
  final int quantity;
  final String? imageUrl;
  final String? size;
  final List<OrderItemAddOn>? addOns;
  final String? specialInstructions;

  const OrderItem({
    required this.foodId,
    required this.name,
    required this.price,
    required this.quantity,
    this.imageUrl,
    this.size,
    this.addOns,
    this.specialInstructions,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      foodId: json['food_id'] as String? ?? json['foodId'] as String? ?? '',
      name: json['name'] as String? ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      imageUrl: json['image_url'] as String? ?? json['imageUrl'] as String?,
      size: json['size'] as String?,
      addOns: json['add_ons'] != null
          ? (json['add_ons'] as List)
              .map((a) => OrderItemAddOn.fromJson(a as Map<String, dynamic>))
              .toList()
          : null,
      specialInstructions:
          json['special_instructions'] as String? ?? json['specialInstructions'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'food_id': foodId,
        'name': name,
        'price': price,
        'quantity': quantity,
        if (imageUrl != null) 'image_url': imageUrl,
        if (size != null) 'size': size,
        if (addOns != null) 'add_ons': addOns!.map((a) => a.toJson()).toList(),
        if (specialInstructions != null) 'special_instructions': specialInstructions,
      };
}

/// An add-on within an order item
class OrderItemAddOn {
  final String name;
  final double price;

  const OrderItemAddOn({required this.name, required this.price});

  factory OrderItemAddOn.fromJson(Map<String, dynamic> json) {
    return OrderItemAddOn(
      name: json['name'] as String? ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'price': price};
}

/// Delivery address stored with the order
class OrderDeliveryAddress {
  final String? fullAddress;
  final double? latitude;
  final double? longitude;
  final String? landmark;

  const OrderDeliveryAddress({
    this.fullAddress,
    this.latitude,
    this.longitude,
    this.landmark,
  });

  factory OrderDeliveryAddress.fromJson(Map<String, dynamic> json) {
    return OrderDeliveryAddress(
      fullAddress: json['full_address'] as String? ?? json['fullAddress'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      landmark: json['landmark'] as String?,
    );
  }
}

/// A complete order record
class Order {
  final String id;
  final String userId;
  final String restaurantId;
  final String orderNumber;
  final OrderStatus status;
  final List<OrderItem> items;
  final double subtotal;
  final double deliveryFee;
  final double total;
  final OrderDeliveryAddress? deliveryAddress;
  final String? deliveryNotes;
  final String? specialInstructions;
  final int? estimatedPrepTime;
  final String? deliveryBoyId;
  final DateTime? assignedAt;
  final DateTime? acceptedAt;
  final DateTime? preparingAt;
  final DateTime? readyAt;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;
  final DateTime? cancelledAt;
  final String? rejectionReason;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Order({
    required this.id,
    required this.userId,
    required this.restaurantId,
    required this.orderNumber,
    required this.status,
    required this.items,
    required this.subtotal,
    required this.deliveryFee,
    required this.total,
    this.deliveryAddress,
    this.deliveryNotes,
    this.specialInstructions,
    this.estimatedPrepTime,
    this.deliveryBoyId,
    this.assignedAt,
    this.acceptedAt,
    this.preparingAt,
    this.readyAt,
    this.pickedUpAt,
    this.deliveredAt,
    this.cancelledAt,
    this.rejectionReason,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    final itemsRaw = json['items'];
    final List<dynamic> itemsList = itemsRaw is List
        ? itemsRaw
        : (itemsRaw is String ? [] : []);

    return Order(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? json['userId'] as String? ?? '',
      restaurantId:
          json['restaurant_id'] as String? ?? json['restaurantId'] as String? ?? '',
      orderNumber:
          json['order_number'] as String? ?? json['orderNumber'] as String? ?? '',
      status: OrderStatus.fromString(
          json['status'] as String? ?? 'PENDING'),
      items: itemsList
          .map((e) => OrderItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0.0,
      deliveryFee: (json['delivery_fee'] as num?)?.toDouble() ?? 0.0,
      total: (json['total'] as num?)?.toDouble() ?? 0.0,
      deliveryAddress: json['delivery_address'] != null
          ? OrderDeliveryAddress.fromJson(
              json['delivery_address'] as Map<String, dynamic>)
          : null,
      deliveryNotes:
          json['delivery_notes'] as String? ?? json['deliveryNotes'] as String?,
      specialInstructions: json['special_instructions'] as String? ??
          json['specialInstructions'] as String?,
      estimatedPrepTime: (json['estimated_prep_time'] as num?)?.toInt() ??
          (json['estimatedPrepTime'] as num?)?.toInt(),
      deliveryBoyId: json['delivery_boy_id'] as String? ??
          json['deliveryBoyId'] as String?,
      assignedAt: _parseDateTime(
          json['assigned_at'] as String? ?? json['assignedAt'] as String?),
      acceptedAt: _parseDateTime(
          json['accepted_at'] as String? ?? json['acceptedAt'] as String?),
      preparingAt: _parseDateTime(
          json['preparing_at'] as String? ?? json['preparingAt'] as String?),
      readyAt: _parseDateTime(
          json['ready_at'] as String? ?? json['readyAt'] as String?),
      pickedUpAt: _parseDateTime(
          json['picked_up_at'] as String? ?? json['pickedUpAt'] as String?),
      deliveredAt: _parseDateTime(
          json['delivered_at'] as String? ?? json['deliveredAt'] as String?),
      cancelledAt: _parseDateTime(
          json['cancelled_at'] as String? ?? json['cancelledAt'] as String?),
      rejectionReason: json['rejection_reason'] as String? ??
          json['rejectionReason'] as String?,
      createdAt: _parseDateTime(
              json['created_at'] as String? ?? json['createdAt'] as String?) ??
          DateTime.now(),
      updatedAt: _parseDateTime(
              json['updated_at'] as String? ?? json['updatedAt'] as String?) ??
          DateTime.now(),
    );
  }

  static DateTime? _parseDateTime(String? s) {
    if (s == null || s.isEmpty) return null;
    return DateTime.tryParse(s);
  }
}
