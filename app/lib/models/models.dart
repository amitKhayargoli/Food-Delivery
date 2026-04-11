class Category {
  final String id;
  final String name;
  final String imageUrl;

  Category({
    required this.id,
    required this.name,
    required this.imageUrl,
  });
}

class Food {
  final String id;
  final String restaurantId;
  final String name;
  final String description;
  final double price;
  final String imageUrl;
  final String categoryId;
  final bool isAvailable;

  Food({
    required this.id,
    required this.restaurantId,
    required this.name,
    required this.description,
    required this.price,
    required this.imageUrl,
    required this.categoryId,
    this.isAvailable = true,
  });
}

class Restaurant {
  final String id;
  final String name;
  final String description;
  final String logoUrl;
  final String bannerUrl;
  final double rating;
  final int deliveryTimeMinutes;
  final List<Food> foods;

  Restaurant({
    required this.id,
    required this.name,
    required this.description,
    required this.logoUrl,
    required this.bannerUrl,
    required this.rating,
    required this.deliveryTimeMinutes,
    required this.foods,
  });
}
