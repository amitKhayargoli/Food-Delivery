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

  factory FoodSize.fromJson(Map<String, dynamic> json) {
    return FoodSize(
      name: json['name'] as String? ?? '',
      weight: json['weight'] as String? ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      isPopular: json['is_popular'] as bool? ?? json['isPopular'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'weight': weight,
        'price': price,
        'is_popular': isPopular,
      };
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

/// A food/menu item. Supports legacy single-image and enhanced multi-image,
/// nutrition, ingredient, and size-variant fields.
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

  // Enhanced fields (US-15, US-16)
  final List<String> imageUrls;
  final int? calories;
  final String? portionWeight;
  final List<String>? allergens;
  final List<String>? ingredients;
  final int? prepTime;

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
    this.imageUrls = const [],
    this.calories,
    this.portionWeight,
    this.allergens,
    this.ingredients,
    this.prepTime,
  });

  factory Food.fromJson(Map<String, dynamic> json) {
    // Parse sizes from JSONB
    final sizesRaw = json['sizes'];
    final List<FoodSize> parsedSizes = sizesRaw is List
        ? sizesRaw
            .whereType<Map<String, dynamic>>()
            .map((s) => FoodSize.fromJson(s))
            .toList()
        : [];

    // Parse multi-image array
    final imagesRaw = json['images'];
    final List<String> parsedImages = imagesRaw is List
        ? imagesRaw.whereType<String>().toList()
        : [];

    // Parse allergens
    final allergensRaw = json['allergens'];
    final List<String> parsedAllergens = allergensRaw is List
        ? allergensRaw.whereType<String>().toList()
        : [];

    // Parse ingredients
    final ingredientsRaw = json['ingredients'];
    final List<String> parsedIngredients = ingredientsRaw is List
        ? ingredientsRaw.whereType<String>().toList()
        : [];

    return Food(
      id: json['id'] as String? ?? '',
      restaurantId: json['restaurant_id'] as String? ??
          json['restaurantId'] as String? ??
          '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      price: (json['base_price'] as num?)?.toDouble() ??
          (json['price'] as num?)?.toDouble() ??
          0.0,
      imageUrl: json['image_url'] as String? ??
          json['imageUrl'] as String? ??
          (parsedImages.isNotEmpty ? parsedImages.first : ''),
      categoryId: json['category_id'] as String? ??
          json['categoryId'] as String? ??
          json['category'] as String? ??
          '',
      isAvailable: json['is_available'] as bool? ??
          json['isAvailable'] as bool? ??
          true,
      sizes: parsedSizes,
      imageUrls: parsedImages,
      calories: (json['calories'] as num?)?.toInt(),
      portionWeight: json['portion_weight'] as String? ??
          json['portionWeight'] as String?,
      allergens: parsedAllergens.isNotEmpty ? parsedAllergens : null,
      ingredients: parsedIngredients.isNotEmpty ? parsedIngredients : null,
      prepTime: (json['prep_time'] as num?)?.toInt() ??
          (json['prepTime'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'base_price': price,
        'category': categoryId,
        'is_available': isAvailable,
        'images': imageUrls.isEmpty && imageUrl.isNotEmpty
            ? [imageUrl]
            : imageUrls,
        'calories': calories,
        'portion_weight': portionWeight,
        'allergens': allergens ?? [],
        'ingredients': ingredients ?? [],
        'sizes': sizes.map((s) => s.toJson()).toList(),
        'prep_time': prepTime,
      };
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
