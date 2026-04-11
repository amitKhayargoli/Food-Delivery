import '../models/models.dart';

final List<Category> mockCategories = [
  Category(id: 'c1', name: 'Burger', imageUrl: '🍔'),
  Category(id: 'c2', name: 'Pizza', imageUrl: '🍕'),
  Category(id: 'c3', name: 'Momo', imageUrl: '🥟'),
  Category(id: 'c4', name: 'Sushi', imageUrl: '🍣'),
  Category(id: 'c5', name: 'Dessert', imageUrl: '🍰'),
];

final List<Restaurant> mockRestaurants = [
  Restaurant(
    id: 'r1',
    name: 'Burger Point',
    description: 'Best smash burgers in town',
    logoUrl: 'https://images.unsplash.com/photo-1550547660-d9450f859349?auto=format&fit=crop&w=200&q=80',
    bannerUrl: 'https://images.unsplash.com/photo-1550547660-d9450f859349?auto=format&fit=crop&w=800&q=80',
    rating: 4.8,
    deliveryTimeMinutes: 30,
    foods: [
      Food(
        id: 'f1',
        restaurantId: 'r1',
        name: 'Classic Smash Burger',
        description: 'Double beef patty, cheddar, house sauce',
        price: 350.0,
        imageUrl: 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?auto=format&fit=crop&w=400&q=80',
        categoryId: 'c1',
      ),
      Food(
        id: 'f2',
        restaurantId: 'r1',
        name: 'Crispy Chicken Burger',
        description: 'Fried chicken breast, pickles, mayo',
        price: 320.0,
        imageUrl: 'https://images.unsplash.com/photo-1525648199074-cee30ba79a4a?auto=format&fit=crop&w=400&q=80',
        categoryId: 'c1',
      ),
    ],
  ),
  Restaurant(
    id: 'r2',
    name: 'Napoli Pizza',
    description: 'Authentic wood-fired pizzas',
    logoUrl: 'https://images.unsplash.com/photo-1513104890138-7c749659a591?auto=format&fit=crop&w=200&q=80',
    bannerUrl: 'https://images.unsplash.com/photo-1513104890138-7c749659a591?auto=format&fit=crop&w=800&q=80',
    rating: 4.6,
    deliveryTimeMinutes: 45,
    foods: [
      Food(
        id: 'f3',
        restaurantId: 'r2',
        name: 'Margherita Pizza',
        description: 'San Marzano tomato sauce, fresh mozzarella, basil',
        price: 650.0,
        imageUrl: 'https://images.unsplash.com/photo-1574071318508-1cdbab80d002?auto=format&fit=crop&w=400&q=80',
        categoryId: 'c2',
      ),
      Food(
        id: 'f4',
        restaurantId: 'r2',
        name: 'Pepperoni Pizza',
        description: 'Tomato sauce, mozzarella, spicy pepperoni',
        price: 750.0,
        imageUrl: 'https://images.unsplash.com/photo-1628840042765-356cda07504e?auto=format&fit=crop&w=400&q=80',
        categoryId: 'c2',
      ),
    ],
  ),
  Restaurant(
    id: 'r3',
    name: 'Kathmandu Momo House',
    description: 'Delicious authentic Nepali momos',
    logoUrl: 'https://images.unsplash.com/photo-1496116218417-1a781b1c416c?auto=format&fit=crop&w=200&q=80',
    bannerUrl: 'https://images.unsplash.com/photo-1496116218417-1a781b1c416c?auto=format&fit=crop&w=800&q=80',
    rating: 4.9,
    deliveryTimeMinutes: 25,
    foods: [
      Food(
        id: 'f5',
        restaurantId: 'r3',
        name: 'Steamed Buff Momo',
        description: '10 pcs steamed buffalo dumplings with special achar',
        price: 150.0,
        imageUrl: 'https://images.unsplash.com/photo-1626804475297-4160ebea14ee?auto=format&fit=crop&w=400&q=80',
        categoryId: 'c3',
      ),
      Food(
        id: 'f6',
        restaurantId: 'r3',
        name: 'Jhol Momo',
        description: '10 pcs momo dipped in spicy sesame tomato broth',
        price: 180.0,
        imageUrl: 'https://images.unsplash.com/photo-1630175860333-514210f92271?auto=format&fit=crop&w=400&q=80',
        categoryId: 'c3',
      ),
    ],
  ),
];
