class Category {
  final String id;
  final String name;
  final String imageUrl;
  final bool hasSizeSelection;

  Category({
    required this.id,
    required this.name,
    required this.imageUrl,
    this.hasSizeSelection = false,
  });
}

/// A size option for a food item (e.g., Small 250g, Medium 350g).
class FoodSize {
  final String name;
  final String weight;
  final double price;
  final bool isPopular;

  const FoodSize({
    required this.name,
    required this.weight,
    required this.price,
    this.isPopular = false,
  });
}

/// A set of add-ons shared by a food category (e.g., pizza add-ons).
class AddOnSet {
  final String id;
  final String categoryId;
  final List<AddOn> addOns;

  const AddOnSet({
    required this.id,
    required this.categoryId,
    required this.addOns,
  });
}

/// A single add-on option (e.g., "Extra Cheese" for रु30).
class AddOn {
  final String name;
  final double price;
  final String imageUrl;

  const AddOn({
    required this.name,
    required this.price,
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
  final List<FoodSize> sizes;

  Food({
    required this.id,
    required this.restaurantId,
    required this.name,
    required this.description,
    required this.price,
    required this.imageUrl,
    required this.categoryId,
    this.isAvailable = true,
    this.sizes = const [],
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
