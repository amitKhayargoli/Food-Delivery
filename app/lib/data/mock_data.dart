import '../models/models.dart';

final List<Category> mockCategories = [
  Category(id: 'c1', name: 'Burger', imageUrl: '🍔', hasSizeSelection: true),
  Category(id: 'c2', name: 'Pizza', imageUrl: '🍕', hasSizeSelection: true),
  Category(id: 'c3', name: 'Momo', imageUrl: '🥟', hasSizeSelection: true),
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
        sizes: [
          FoodSize(name: 'Single', weight: '1 patty (200g)', price: 350.0),
          FoodSize(name: 'Double', weight: '2 patties (350g)', price: 450.0, isPopular: true),
          FoodSize(name: 'Triple', weight: '3 patties (500g)', price: 550.0),
        ],
      ),
      Food(
        id: 'f2',
        restaurantId: 'r1',
        name: 'Crispy Chicken Burger',
        description: 'Fried chicken breast, pickles, mayo',
        price: 320.0,
        imageUrl: 'https://images.unsplash.com/photo-1525648199074-cee30ba79a4a?auto=format&fit=crop&w=400&q=80',
        categoryId: 'c1',
        sizes: [
          FoodSize(name: 'Single', weight: '1 patty (200g)', price: 320.0),
          FoodSize(name: 'Double', weight: '2 patties (350g)', price: 420.0, isPopular: true),
          FoodSize(name: 'Triple', weight: '3 patties (500g)', price: 520.0),
        ],
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
        sizes: [
          FoodSize(name: 'Small', weight: '250g', price: 399.0),
          FoodSize(name: 'Medium', weight: '350g', price: 650.0, isPopular: true),
          FoodSize(name: 'Large', weight: '500g', price: 999.0),
        ],
      ),
      Food(
        id: 'f4',
        restaurantId: 'r2',
        name: 'Pepperoni Pizza',
        description: 'Tomato sauce, mozzarella, spicy pepperoni',
        price: 750.0,
        imageUrl: 'https://images.unsplash.com/photo-1628840042765-356cda07504e?auto=format&fit=crop&w=400&q=80',
        categoryId: 'c2',
        sizes: [
          FoodSize(name: 'Small', weight: '250g', price: 499.0),
          FoodSize(name: 'Medium', weight: '350g', price: 750.0, isPopular: true),
          FoodSize(name: 'Large', weight: '500g', price: 1099.0),
        ],
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
        sizes: [
          FoodSize(name: 'Half', weight: '6 pcs (300g)', price: 100.0),
          FoodSize(name: 'Full', weight: '10 pcs (500g)', price: 150.0, isPopular: true),
          FoodSize(name: 'Jumbo', weight: '15 pcs (750g)', price: 230.0),
        ],
      ),
      Food(
        id: 'f6',
        restaurantId: 'r3',
        name: 'Jhol Momo',
        description: '10 pcs momo dipped in spicy sesame tomato broth',
        price: 180.0,
        imageUrl: 'https://images.unsplash.com/photo-1630175860333-514210f92271?auto=format&fit=crop&w=400&q=80',
        categoryId: 'c3',
        sizes: [
          FoodSize(name: 'Half', weight: '6 pcs (300g)', price: 120.0),
          FoodSize(name: 'Full', weight: '10 pcs (500g)', price: 180.0, isPopular: true),
          FoodSize(name: 'Jumbo', weight: '15 pcs (750g)', price: 260.0),
        ],
      ),
    ],
  ),
];

final List<AddOnSet> mockAddOnSets = [
  AddOnSet(
    id: 'aos_pizza',
    categoryId: 'c2',
    addOns: [
      const AddOn(
        name: 'Double Cheese',
        price: 40.0,
        imageUrl: 'https://placehold.co/40x40/FFF1F0/F5222D?text=🧀',
      ),
      const AddOn(
        name: 'Double Chicken',
        price: 60.0,
        imageUrl: 'https://placehold.co/40x40/FFF1F0/F5222D?text=🍗',
      ),
      const AddOn(
        name: 'Extra Jalapenos',
        price: 20.0,
        imageUrl: 'https://placehold.co/40x40/FFF1F0/F5222D?text=🌶',
      ),
      const AddOn(
        name: 'Bacon Strips',
        price: 50.0,
        imageUrl: 'https://placehold.co/40x40/FFF1F0/F5222D?text=🥓',
      ),
      const AddOn(
        name: 'Extra Sauce',
        price: 10.0,
        imageUrl: 'https://placehold.co/40x40/FFF1F0/F5222D?text=🥫',
      ),
    ],
  ),
  AddOnSet(
    id: 'aos_burger',
    categoryId: 'c1',
    addOns: [
      const AddOn(
        name: 'Extra Patty',
        price: 80.0,
        imageUrl: 'https://placehold.co/40x40/FFF1F0/F5222D?text=🍔',
      ),
      const AddOn(
        name: 'Bacon Strips',
        price: 50.0,
        imageUrl: 'https://placehold.co/40x40/FFF1F0/F5222D?text=🥓',
      ),
      const AddOn(
        name: 'Extra Cheese',
        price: 30.0,
        imageUrl: 'https://placehold.co/40x40/FFF1F0/F5222D?text=🧀',
      ),
      const AddOn(
        name: 'Jalapenos',
        price: 20.0,
        imageUrl: 'https://placehold.co/40x40/FFF1F0/F5222D?text=🌶',
      ),
      const AddOn(
        name: 'Special Sauce',
        price: 15.0,
        imageUrl: 'https://placehold.co/40x40/FFF1F0/F5222D?text=🥫',
      ),
    ],
  ),
  AddOnSet(
    id: 'aos_momo',
    categoryId: 'c3',
    addOns: [
      const AddOn(
        name: 'Extra Achar',
        price: 15.0,
        imageUrl: 'https://placehold.co/40x40/FFF1F0/F5222D?text=🥣',
      ),
      const AddOn(
        name: 'Extra Mayo',
        price: 10.0,
        imageUrl: 'https://placehold.co/40x40/FFF1F0/F5222D?text=🥛',
      ),
      const AddOn(
        name: 'Spicy Dip',
        price: 20.0,
        imageUrl: 'https://placehold.co/40x40/FFF1F0/F5222D?text=🌶',
      ),
    ],
  ),
];
