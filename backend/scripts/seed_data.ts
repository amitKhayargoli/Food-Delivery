/**
 * Seed Script — Real Nepali Restaurants, Menus & Sample Orders
 *
 * Run:
 *   cd backend && npx ts-node scripts/seed_data.ts
 *
 * This script:
 *   1. Finds existing users to assign restaurants/orders to
 *   2. Creates 8+ real Nepali restaurants with APPROVED status
 *   3. Creates 6-8 menu items per restaurant with real Nepali food
 *   4. Creates sample orders in various statuses
 *   5. Uses high-quality Unsplash images for all assets
 */

import dotenv from 'dotenv';
import * as path from 'path';
dotenv.config({ path: path.join(__dirname, '..', '.env') });

import { supabase } from '../src/db/supabase';

// ─── Helpers ───────────────────────────────────

function rupiah(amount: number): number {
  return amount; // Already in NPR
}

function now(offsetMinutes = 0): string {
  return new Date(Date.now() - offsetMinutes * 60 * 1000).toISOString();
}

function randomId(): string {
  return crypto.randomUUID();
}

// ─── Restaurant Data ───────────────────────────

interface RestaurantSeed {
  name: string;
  ownerName: string;
  phone: string;
  email: string;
  address: string;
  description: string;
  cuisine: string;
  openTime: string;
  closeTime: string;
  logoUrl: string;
  coverUrl: string;
  menuItems: MenuItemSeed[];
}

interface MenuItemSeed {
  name: string;
  description: string;
  basePrice: number;
  category: string;
  images: string[];
  calories: number;
  portionWeight: string;
  allergens: string[];
  ingredients: string[];
  prepTime: number;
  sizes: { name: string; weight: string; price: number; is_popular: boolean }[];
}

const RESTAURANTS: RestaurantSeed[] = [
  {
    name: 'Kathmandu Momo House',
    ownerName: 'Rajesh Shrestha',
    phone: '9801234567',
    email: 'rajesh@ktmmomo.com',
    address: 'Thamel, Kathmandu 44600',
    description: 'The undisputed king of momos in Kathmandu. Serving authentic buffalo, chicken, and veg momos with secret family-recipe achar since 2005. Our steamed, fried, and jhol momos are made fresh daily with locally sourced ingredients.',
    cuisine: 'Nepali, Newari',
    openTime: '10:00 AM',
    closeTime: '10:00 PM',
    logoUrl: 'https://images.unsplash.com/photo-1553621042-f6e147245754?auto=format&fit=crop&w=200&q=80',
    coverUrl: 'https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?auto=format&fit=crop&w=800&q=80',
    menuItems: [
      { name: 'Steamed Buff Momo', description: '10 pieces of traditional buffalo momo steamed to perfection, served with spicy tomato achar and sesame dip', basePrice: 180, category: 'Momo', images: ['https://images.unsplash.com/photo-1626804475297-4160ebea14ee?auto=format&fit=crop&w=400&q=80', 'https://images.unsplash.com/photo-1534468016-19b78c6a7a0a?auto=format&fit=crop&w=400&q=80', 'https://images.unsplash.com/photo-1601050690597-df0568f70950?auto=format&fit=crop&w=400&q=80'], calories: 450, portionWeight: '10 pcs (400g)', allergens: ['Gluten', 'Soy'], ingredients: ['Buffalo meat', 'Flour', 'Onion', 'Ginger', 'Garlic', 'Coriander', 'Green chillies'], prepTime: 20, sizes: [{ name: 'Half Plate', weight: '6 pcs (250g)', price: 120, is_popular: false }, { name: 'Full Plate', weight: '10 pcs (400g)', price: 180, is_popular: true }, { name: 'Jumbo', weight: '15 pcs (600g)', price: 260, is_popular: false }] },
      { name: 'Chicken Steam Momo', description: 'Tender minced chicken momo with herbs and spices, served with tangy achar', basePrice: 200, category: 'Momo', images: ['https://images.unsplash.com/photo-1534422298391-e4f8c172dddb?auto=format&fit=crop&w=400&q=80', 'https://images.unsplash.com/photo-1601050690597-df0568f70950?auto=format&fit=crop&w=400&q=80'], calories: 380, portionWeight: '10 pcs (350g)', allergens: ['Gluten'], ingredients: ['Chicken', 'Flour', 'Onion', 'Ginger', 'Garlic', 'Coriander', 'Soy sauce'], prepTime: 20, sizes: [{ name: 'Half Plate', weight: '6 pcs (220g)', price: 130, is_popular: false }, { name: 'Full Plate', weight: '10 pcs (350g)', price: 200, is_popular: true }] },
      { name: 'Jhol Momo', description: 'Buff momo served in a spicy sesame-tomato broth with timur (Sichuan pepper) — a Kathmandu specialty', basePrice: 220, category: 'Momo', images: ['https://images.unsplash.com/photo-1630175860333-514210f92271?auto=format&fit=crop&w=400&q=80', 'https://images.unsplash.com/photo-1601050690597-df0568f70950?auto=format&fit=crop&w=400&q=80', 'https://images.unsplash.com/photo-1626804475297-4160ebea14ee?auto=format&fit=crop&w=400&q=80'], calories: 420, portionWeight: '10 pcs with soup (500g)', allergens: ['Gluten', 'Sesame', 'Soy'], ingredients: ['Buffalo meat', 'Flour', 'Tomato', 'Sesame', 'Timur', 'Garlic', 'Green chillies'], prepTime: 25, sizes: [{ name: 'Regular', weight: '10 pcs (500g)', price: 220, is_popular: true }] },
      { name: 'Fried Momo', description: 'Crispy pan-fried buff momo with golden brown bottom, served with special achar', basePrice: 210, category: 'Momo', images: ['https://images.unsplash.com/photo-1601050690597-df0568f70950?auto=format&fit=crop&w=400&q=80'], calories: 520, portionWeight: '8 pcs (300g)', allergens: ['Gluten', 'Soy'], ingredients: ['Buffalo meat', 'Flour', 'Oil', 'Onion', 'Ginger', 'Garlic', 'Coriander'], prepTime: 25, sizes: [{ name: 'Half Plate', weight: '5 pcs (180g)', price: 140, is_popular: false }, { name: 'Full Plate', weight: '8 pcs (300g)', price: 210, is_popular: true }] },
      { name: 'Veg Momo', description: 'Fresh vegetable momo stuffed with cabbage, carrot, and mushroom', basePrice: 160, category: 'Momo', images: ['https://images.unsplash.com/photo-1534422298391-e4f8c172dddb?auto=format&fit=crop&w=400&q=80'], calories: 280, portionWeight: '10 pcs (350g)', allergens: ['Gluten'], ingredients: ['Cabbage', 'Carrot', 'Mushroom', 'Flour', 'Onion', 'Garlic', 'Ginger'], prepTime: 20, sizes: [{ name: 'Half Plate', weight: '6 pcs (220g)', price: 100, is_popular: false }, { name: 'Full Plate', weight: '10 pcs (350g)', price: 160, is_popular: true }] },
      { name: 'Chicken Chow Mein', description: 'Hakka-style stir-fried noodles with chicken, vegetables, and soy sauce', basePrice: 200, category: 'Noodles', images: ['https://images.unsplash.com/photo-1552611052-33e04de1b100?auto=format&fit=crop&w=400&q=80'], calories: 480, portionWeight: 'Large plate (400g)', allergens: ['Gluten', 'Soy', 'Egg'], ingredients: ['Noodles', 'Chicken', 'Cabbage', 'Carrot', 'Capsicum', 'Soy sauce', 'Spring onion'], prepTime: 15, sizes: [{ name: 'Regular', weight: '300g', price: 200, is_popular: true }, { name: 'Large', weight: '500g', price: 300, is_popular: false }] },
      { name: 'Buff Sekuwa', description: 'Traditional Newari-style grilled buffalo meat marinated with timur, garlic, and herbs', basePrice: 350, category: 'Newari', images: ['https://images.unsplash.com/photo-1544025162-d76694265947?auto=format&fit=crop&w=400&q=80'], calories: 380, portionWeight: '200g', allergens: [], ingredients: ['Buffalo meat', 'Timur', 'Garlic', 'Ginger', 'Cumin', 'Coriander', 'Mustard oil'], prepTime: 30, sizes: [{ name: 'Half', weight: '100g', price: 200, is_popular: false }, { name: 'Full', weight: '200g', price: 350, is_popular: true }] },
      { name: 'Chiya (Nepali Tea)', description: 'Traditional Nepali milk tea with cardamom, ginger, and cinnamon', basePrice: 40, category: 'Beverages', images: ['https://images.unsplash.com/photo-1571934811356-5cc061b6821f?auto=format&fit=crop&w=400&q=80'], calories: 60, portionWeight: '1 cup (200ml)', allergens: ['Milk'], ingredients: ['Tea leaves', 'Milk', 'Sugar', 'Cardamom', 'Ginger', 'Cinnamon'], prepTime: 5, sizes: [{ name: 'Small Cup', weight: '150ml', price: 30, is_popular: false }, { name: 'Regular Cup', weight: '200ml', price: 40, is_popular: true }, { name: 'Large Cup', weight: '300ml', price: 55, is_popular: false }] },
    ],
  },

  {
    name: 'Thamel Durbar Restaurant',
    ownerName: 'Binod Gurung',
    phone: '9841234568',
    email: 'binod@thameldurbar.com',
    address: 'Durbar Square, Thamel, Kathmandu 44600',
    description: 'Fine dining experience in the heart of Thamel. Specializing in authentic Nepali and Indian cuisine served in a beautiful traditional setting with live cultural music evenings. Our dal bhat is legendary among locals and trekkers alike.',
    cuisine: 'Nepali, Indian, Mughlai',
    openTime: '8:00 AM',
    closeTime: '11:00 PM',
    logoUrl: 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?auto=format&fit=crop&w=200&q=80',
    coverUrl: 'https://images.unsplash.com/photo-1555396273-367ea4eb4db5?auto=format&fit=crop&w=800&q=80',
    menuItems: [
      { name: 'Dal Bhat Power Set', description: 'Traditional Nepali thali with dal, steamed rice, mixed vegetables, papad, achar, and curry — unlimited servings', basePrice: 350, category: 'Nepali Thali', images: ['https://images.unsplash.com/photo-1565557623262-b51c2513a641?auto=format&fit=crop&w=400&q=80', 'https://images.unsplash.com/photo-1585937421612-70a008356fbe?auto=format&fit=crop&w=400&q=80'], calories: 650, portionWeight: 'Full thali (800g)', allergens: ['Milk', 'Gluten'], ingredients: ['Rice', 'Lentils', 'Mixed vegetables', 'Spices', 'Ghee', 'Yogurt'], prepTime: 20, sizes: [{ name: 'Regular', weight: '800g', price: 350, is_popular: true }, { name: 'Large', weight: '1.2kg', price: 450, is_popular: false }] },
      { name: 'Chicken Butter Masala', description: 'Tender chicken cooked in rich, creamy tomato-based gravy with butter and cream', basePrice: 420, category: 'Main Course', images: ['https://images.unsplash.com/photo-1585937421612-70a008356fbe?auto=format&fit=crop&w=400&q=80', 'https://images.unsplash.com/photo-1565557623262-b51c2513a641?auto=format&fit=crop&w=400&q=80'], calories: 520, portionWeight: '1 serving (300g)', allergens: ['Milk', 'Cream'], ingredients: ['Chicken', 'Tomato', 'Butter', 'Cream', 'Ginger', 'Garlic', 'Spices'], prepTime: 25, sizes: [{ name: 'Half', weight: '150g', price: 250, is_popular: false }, { name: 'Full', weight: '300g', price: 420, is_popular: true }] },
      { name: 'Mutton Curry', description: 'Slow-cooked tender mutton in rich Nepali-style spicy gravy with aromatic spices', basePrice: 550, category: 'Main Course', images: ['https://images.unsplash.com/photo-1544025162-d76694265947?auto=format&fit=crop&w=400&q=80'], calories: 480, portionWeight: '1 serving (250g)', allergens: [], ingredients: ['Mutton', 'Onion', 'Tomato', 'Ginger', 'Garlic', 'Cumin', 'Coriander', 'Garam masala'], prepTime: 40, sizes: [{ name: 'Half', weight: '150g', price: 350, is_popular: false }, { name: 'Full', weight: '250g', price: 550, is_popular: true }] },
      { name: 'Vegetable Biryani', description: 'Fragrant basmati rice cooked with mixed vegetables, saffron, and fried onions', basePrice: 280, category: 'Biryani', images: ['https://images.unsplash.com/photo-1563379091339-03b21ab4a4f8?auto=format&fit=crop&w=400&q=80'], calories: 450, portionWeight: 'Large plate (400g)', allergens: ['Milk'], ingredients: ['Basmati rice', 'Mixed vegetables', 'Saffron', 'Fried onions', 'Ghee', 'Spices'], prepTime: 30, sizes: [{ name: 'Single', weight: '400g', price: 280, is_popular: true }, { name: 'Double', weight: '700g', price: 450, is_popular: false }] },
      { name: 'Chicken Biryani', description: 'Hyderabadi-style chicken biryani with tender marinated chicken and aromatic basmati rice', basePrice: 380, category: 'Biryani', images: ['https://images.unsplash.com/photo-1563379091339-03b21ab4a4f8?auto=format&fit=crop&w=400&q=80'], calories: 550, portionWeight: 'Large plate (450g)', allergens: ['Milk'], ingredients: ['Basmati rice', 'Chicken', 'Yogurt', 'Saffron', 'Fried onions', 'Ghee', 'Biryani masala'], prepTime: 35, sizes: [{ name: 'Single', weight: '450g', price: 380, is_popular: true }, { name: 'Double', weight: '800g', price: 650, is_popular: false }] },
      { name: 'Garlic Naan', description: 'Soft leavened bread brushed with garlic butter and fresh coriander', basePrice: 60, category: 'Bread', images: ['https://images.unsplash.com/photo-1565557623262-b51c2513a641?auto=format&fit=crop&w=400&q=80'], calories: 180, portionWeight: '1 piece (80g)', allergens: ['Gluten', 'Milk'], ingredients: ['Flour', 'Garlic', 'Butter', 'Yogurt', 'Coriander'], prepTime: 10, sizes: [{ name: '1 Piece', weight: '80g', price: 60, is_popular: true }, { name: '2 Pieces', weight: '160g', price: 110, is_popular: false }] },
      { name: 'Lassi', description: 'Traditional sweet yogurt drink blended with cardamom and rose water', basePrice: 120, category: 'Beverages', images: ['https://images.unsplash.com/photo-1558002038-1055907df827?auto=format&fit=crop&w=400&q=80'], calories: 150, portionWeight: '1 glass (300ml)', allergens: ['Milk'], ingredients: ['Yogurt', 'Sugar', 'Cardamom', 'Rose water'], prepTime: 5, sizes: [{ name: 'Regular', weight: '300ml', price: 120, is_popular: true }, { name: 'Large', weight: '500ml', price: 180, is_popular: false }] },
    ],
  },

  {
    name: 'Newa Lahana',
    ownerName: 'Sujan Maharjan',
    phone: '9812345670',
    email: 'sujan@newalahana.com',
    address: 'Patan Durbar Square, Lalitpur 44700',
    description: 'Authentic Newari cuisine served in a restored 200-year-old Patan courtyard. Experience the rich culinary heritage of the Newar community with traditional dishes passed down through generations.',
    cuisine: 'Newari, Traditional Nepali',
    openTime: '11:00 AM',
    closeTime: '9:30 PM',
    logoUrl: 'https://images.unsplash.com/photo-1555396273-367ea4eb4db5?auto=format&fit=crop&w=200&q=80',
    coverUrl: 'https://images.unsplash.com/photo-1466978913421-dad2ebd01d17?auto=format&fit=crop&w=800&q=80',
    menuItems: [
      { name: 'Newari Khaja Set', description: 'Traditional Newari snack platter with chiura (beaten rice), buff choila, aloo achar, soyabean, and egg — a festive meal', basePrice: 400, category: 'Newari Thali', images: ['https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?auto=format&fit=crop&w=400&q=80'], calories: 580, portionWeight: 'Full set (600g)', allergens: ['Egg', 'Soy'], ingredients: ['Beaten rice', 'Buffalo meat', 'Potato', 'Soybean', 'Egg', 'Timur', 'Mustard oil'], prepTime: 20, sizes: [{ name: 'Regular', weight: '600g', price: 400, is_popular: true }, { name: 'Large', weight: '900g', price: 550, is_popular: false }] },
      { name: 'Buff Choila', description: 'Spiced smoked buffalo meat marinated with timur, ginger, garlic, and green chillies — a Newari classic', basePrice: 280, category: 'Newari Starter', images: ['https://images.unsplash.com/photo-1544025162-d76694265947?auto=format&fit=crop&w=400&q=80'], calories: 320, portionWeight: '1 serving (150g)', allergens: [], ingredients: ['Buffalo meat', 'Timur', 'Ginger', 'Garlic', 'Green chillies', 'Mustard oil', 'Coriander'], prepTime: 15, sizes: [{ name: 'Half', weight: '80g', price: 160, is_popular: false }, { name: 'Full', weight: '150g', price: 280, is_popular: true }] },
      { name: 'Yomari', description: 'Traditional Newari sweet dumpling made from rice flour, filled with chaku (molasses) and sesame seeds — a festivity favorite', basePrice: 120, category: 'Newari Sweets', images: ['https://images.unsplash.com/photo-1558961363-fa8fdf82db35?auto=format&fit=crop&w=400&q=80'], calories: 250, portionWeight: '4 pieces (200g)', allergens: ['Gluten', 'Sesame'], ingredients: ['Rice flour', 'Chaku (molasses)', 'Sesame seeds', 'Ghee'], prepTime: 25, sizes: [{ name: '2 Pieces', weight: '100g', price: 70, is_popular: false }, { name: '4 Pieces', weight: '200g', price: 120, is_popular: true }] },
      { name: 'Bara (Newari Rice Pancake)', description: 'Savory lentil pancake topped with spiced minced buff, egg, and fresh coriander', basePrice: 150, category: 'Newari Snacks', images: ['https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?auto=format&fit=crop&w=400&q=80'], calories: 200, portionWeight: '2 pieces (150g)', allergens: ['Egg'], ingredients: ['Black lentils', 'Buffalo meat', 'Egg', 'Cumin', 'Coriander', 'Green chillies', 'Oil'], prepTime: 15, sizes: [{ name: '1 Piece', weight: '75g', price: 80, is_popular: false }, { name: '2 Pieces', weight: '150g', price: 150, is_popular: true }] },
      { name: 'Chatamari (Newari Pizza)', description: 'Crispy rice flour crepe topped with spiced minced buff, egg, chopped onions, and fresh coriander', basePrice: 200, category: 'Newari Snacks', images: ['https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?auto=format&fit=crop&w=400&q=80'], calories: 300, portionWeight: '1 large (200g)', allergens: ['Egg'], ingredients: ['Rice flour', 'Buffalo meat', 'Egg', 'Onion', 'Coriander', 'Cumin', 'Turmeric'], prepTime: 20, sizes: [{ name: 'Regular', weight: '200g', price: 200, is_popular: true }, { name: 'Large', weight: '350g', price: 320, is_popular: false }] },
      { name: 'Samaya Baji', description: 'Traditional Newari ceremonial platter with beaten rice, roasted soybeans, ginger, garlic, buff choila, and achar', basePrice: 500, category: 'Newari Thali', images: ['https://images.unsplash.com/photo-1546069901-ba9599a7e63c?auto=format&fit=crop&w=400&q=80'], calories: 650, portionWeight: 'Full set (700g)', allergens: ['Soy', 'Egg'], ingredients: ['Beaten rice', 'Buff choila', 'Soybean', 'Ginger', 'Garlic', 'Egg', 'Mustard oil'], prepTime: 25, sizes: [{ name: '1 Person', weight: '700g', price: 500, is_popular: true }, { name: '2 Person', weight: '1.2kg', price: 900, is_popular: false }] },
      { name: 'Aila (Local Selection)', description: 'Traditional Newali homemade liquor, distilled from rice or millet — served in a traditional khadko', basePrice: 200, category: 'Beverages', images: ['https://images.unsplash.com/photo-1514362545857-3bc16c4c7d1b?auto=format&fit=crop&w=400&q=80'], calories: 120, portionWeight: '1 small bottle (180ml)', allergens: [], ingredients: ['Fermented rice', 'Millet', 'Traditional starter culture'], prepTime: 2, sizes: [{ name: 'Small Glass', weight: '60ml', price: 80, is_popular: false }, { name: 'Large Glass', weight: '120ml', price: 150, is_popular: true }, { name: 'Bottle', weight: '180ml', price: 200, is_popular: false }] },
    ],
  },

  {
    name: 'Boudha Bites Cafe',
    ownerName: 'Tenzin Dolma',
    phone: '9851234569',
    email: 'tenzin@boudhabites.com',
    address: 'Boudha, Kathmandu 44600 (Near the Stupa)',
    description: 'A cozy cafe with a stunning view of Boudhanath Stupa. We serve continental cuisine, artisanal coffee, and Tibetan-inspired dishes in a peaceful, relaxing atmosphere. Perfect for digital nomads and travelers.',
    cuisine: 'Continental, Tibetan, Cafe',
    openTime: '7:00 AM',
    closeTime: '9:00 PM',
    logoUrl: 'https://images.unsplash.com/photo-1554118811-1e0d58224f24?auto=format&fit=crop&w=200&q=80',
    coverUrl: 'https://images.unsplash.com/photo-1554118811-1e0d58224f24?auto=format&fit=crop&w=800&q=80',
    menuItems: [
      { name: 'Tibetan Thukpa', description: 'Hearty Tibetan noodle soup with vegetables or chicken, flavored with ginger, garlic, and Tibetan spices', basePrice: 250, category: 'Tibetan', images: ['https://images.unsplash.com/photo-1569718212165-3a8278d5f624?auto=format&fit=crop&w=400&q=80'], calories: 380, portionWeight: 'Large bowl (500ml)', allergens: ['Gluten'], ingredients: ['Noodles', 'Chicken or Vegetables', 'Ginger', 'Garlic', 'Spring onion', 'Tibetan spices'], prepTime: 20, sizes: [{ name: 'Vegetable', weight: '500ml', price: 220, is_popular: false }, { name: 'Chicken', weight: '500ml', price: 250, is_popular: true }] },
      { name: 'Club Sandwich', description: 'Toasted triple-decker sandwich with grilled chicken, bacon, lettuce, tomato, egg, and mayo', basePrice: 320, category: 'Continental', images: ['https://images.unsplash.com/photo-1528735602780-2552fd46c7af?auto=format&fit=crop&w=400&q=80'], calories: 520, portionWeight: '1 sandwich (300g)', allergens: ['Gluten', 'Egg', 'Milk'], ingredients: ['Bread', 'Chicken', 'Bacon', 'Lettuce', 'Tomato', 'Egg', 'Mayonnaise'], prepTime: 15, sizes: [{ name: 'Single', weight: '300g', price: 320, is_popular: true }] },
      { name: 'Spaghetti Carbonara', description: 'Classic Italian carbonara with cream, parmesan, pancetta, and egg yolk', basePrice: 380, category: 'Pasta', images: ['https://images.unsplash.com/photo-1612874742237-6526221588e3?auto=format&fit=crop&w=400&q=80'], calories: 580, portionWeight: '1 plate (350g)', allergens: ['Gluten', 'Egg', 'Milk'], ingredients: ['Spaghetti', 'Cream', 'Parmesan', 'Pancetta', 'Egg yolk', 'Black pepper'], prepTime: 20, sizes: [{ name: 'Regular', weight: '350g', price: 380, is_popular: true }, { name: 'Large', weight: '500g', price: 480, is_popular: false }] },
      { name: 'Avocado Toast', description: 'Smashed avocado on sourdough with cherry tomatoes, feta cheese, and chili flakes', basePrice: 280, category: 'Breakfast', images: ['https://images.unsplash.com/photo-1541519227354-08fa5d50c44d?auto=format&fit=crop&w=400&q=80'], calories: 350, portionWeight: '2 slices (200g)', allergens: ['Gluten', 'Milk'], ingredients: ['Sourdough bread', 'Avocado', 'Cherry tomato', 'Feta cheese', 'Chili flakes', 'Lemon'], prepTime: 10, sizes: [{ name: 'Single', weight: '200g', price: 280, is_popular: true }] },
      { name: 'Masala Omelette', description: 'Fluffy 3-egg omelette with onions, tomatoes, green chillies, and coriander, served with toast', basePrice: 180, category: 'Breakfast', images: ['https://images.unsplash.com/photo-1510693206972-df098062cb71?auto=format&fit=crop&w=400&q=80'], calories: 280, portionWeight: '1 omelette + 2 toast (250g)', allergens: ['Egg', 'Gluten'], ingredients: ['Eggs', 'Onion', 'Tomato', 'Green chillies', 'Coriander', 'Spices'], prepTime: 10, sizes: [{ name: 'Regular', weight: '250g', price: 180, is_popular: true }] },
      { name: 'Cold Brew Coffee', description: 'Smooth 16-hour slow-steeped cold brew coffee served over ice', basePrice: 180, category: 'Beverages', images: ['https://images.unsplash.com/photo-1517701550927-30cf4ba1dba5?auto=format&fit=crop&w=400&q=80'], calories: 15, portionWeight: '1 glass (350ml)', allergens: [], ingredients: ['Coffee beans', 'Filtered water'], prepTime: 5, sizes: [{ name: 'Regular', weight: '350ml', price: 180, is_popular: true }, { name: 'Large', weight: '500ml', price: 250, is_popular: false }] },
      { name: 'Blueberry Pancakes', description: 'Fluffy American-style pancakes with fresh blueberries, maple syrup, and whipped cream', basePrice: 320, category: 'Breakfast', images: ['https://images.unsplash.com/photo-1567620905732-2d1ec7ab7445?auto=format&fit=crop&w=400&q=80'], calories: 450, portionWeight: '4 pancakes (300g)', allergens: ['Gluten', 'Milk', 'Egg'], ingredients: ['Pancake batter', 'Blueberries', 'Maple syrup', 'Cream', 'Butter', 'Eggs'], prepTime: 20, sizes: [{ name: 'Short Stack', weight: '2 pcs (150g)', price: 180, is_popular: false }, { name: 'Full Stack', weight: '4 pcs (300g)', price: 320, is_popular: true }] },
    ],
  },

  {
    name: 'Himalayan Grill House',
    ownerName: 'Kiran Thapa',
    phone: '9861234570',
    email: 'kiran@himalayangrill.com',
    address: 'Lakeside, Pokhara 33700',
    description: 'Premium grill and steakhouse with stunning Himalayan views. Specializing in wood-fired grilled meats, fresh from the Himalayas, paired with fine wines and craft beers. The perfect sunset dining destination.',
    cuisine: 'Continental, Steakhouse, BBQ',
    openTime: '12:00 PM',
    closeTime: '10:30 PM',
    logoUrl: 'https://images.unsplash.com/photo-1550966871-3ed3cdb51f3a?auto=format&fit=crop&w=200&q=80',
    coverUrl: 'https://images.unsplash.com/photo-1514933651103-005eec06c04b?auto=format&fit=crop&w=800&q=80',
    menuItems: [
      { name: 'Grilled Chicken Steak', description: 'Marinated chicken breast grilled to perfection, served with mashed potatoes, seasonal vegetables, and mushroom sauce', basePrice: 450, category: 'Grill', images: ['https://images.unsplash.com/photo-1432139509613-5c4255a1d7f6?auto=format&fit=crop&w=400&q=80', 'https://images.unsplash.com/photo-1544025162-d76694265947?auto=format&fit=crop&w=400&q=80'], calories: 550, portionWeight: '1 steak (350g)', allergens: ['Milk'], ingredients: ['Chicken breast', 'Potato', 'Mixed vegetables', 'Mushroom', 'Cream', 'Butter', 'Herbs'], prepTime: 25, sizes: [{ name: 'Regular', weight: '350g', price: 450, is_popular: true }, { name: 'Large', weight: '500g', price: 600, is_popular: false }] },
      { name: 'BBQ Pork Ribs', description: 'Slow-cooked pork ribs glazed with house BBQ sauce, served with coleslaw and fries', basePrice: 650, category: 'BBQ', images: ['https://images.unsplash.com/photo-1528597464907-47e2e4f12b39?auto=format&fit=crop&w=400&q=80'], calories: 720, portionWeight: 'Full rack (500g)', allergens: [], ingredients: ['Pork ribs', 'BBQ sauce', 'Honey', 'Garlic', 'Paprika', 'Cumin', 'Brown sugar'], prepTime: 40, sizes: [{ name: 'Half Rack', weight: '300g', price: 400, is_popular: false }, { name: 'Full Rack', weight: '500g', price: 650, is_popular: true }] },
      { name: 'Grilled Fish with Lemon Butter', description: 'Fresh Himalayan trout grilled with lemon butter sauce, served with herb rice and steamed vegetables', basePrice: 550, category: 'Seafood', images: ['https://images.unsplash.com/photo-1519708227418-c8fd9a32b7a2?auto=format&fit=crop&w=400&q=80'], calories: 420, portionWeight: '1 fillet (300g)', allergens: ['Fish', 'Milk'], ingredients: ['Trout', 'Lemon', 'Butter', 'Garlic', 'Parsley', 'Rice', 'Mixed vegetables'], prepTime: 25, sizes: [{ name: 'Regular', weight: '300g', price: 550, is_popular: true }] },
      { name: 'Grilled Vegetable Platter', description: 'Assorted seasonal vegetables marinated in herbs and olive oil, char-grilled and served with couscous', basePrice: 350, category: 'Grill', images: ['https://images.unsplash.com/photo-1540420773420-3366772f4999?auto=format&fit=crop&w=400&q=80'], calories: 280, portionWeight: 'Large platter (400g)', allergens: ['Gluten'], ingredients: ['Capsicum', 'Zucchini', 'Eggplant', 'Mushroom', 'Couscous', 'Olive oil', 'Herbs'], prepTime: 20, sizes: [{ name: 'Regular', weight: '400g', price: 350, is_popular: true }] },
      { name: 'Sizzling Brownie', description: 'Warm chocolate brownie served on a sizzling skillet with vanilla ice cream, chocolate sauce, and nuts', basePrice: 280, category: 'Desserts', images: ['https://images.unsplash.com/photo-1564355808539-22e526464b25?auto=format&fit=crop&w=400&q=80'], calories: 520, portionWeight: '1 sizzler (250g)', allergens: ['Gluten', 'Milk', 'Nuts', 'Egg'], ingredients: ['Chocolate', 'Brownie', 'Vanilla ice cream', 'Nuts', 'Chocolate sauce'], prepTime: 15, sizes: [{ name: 'Single', weight: '250g', price: 280, is_popular: true }, { name: 'Double', weight: '400g', price: 450, is_popular: false }] },
      { name: 'Craft Beer (Local)', description: 'Selection of Nepali craft beers — Everest, Gorkha, Sherpa, and seasonal brews', basePrice: 250, category: 'Beverages', images: ['https://images.unsplash.com/photo-1559181567-c3190ca9959b?auto=format&fit=crop&w=400&q=80'], calories: 150, portionWeight: '1 pint (330ml)', allergens: ['Gluten'], ingredients: ['Barley', 'Hops', 'Yeast', 'Water'], prepTime: 2, sizes: [{ name: 'Everest Lager', weight: '330ml', price: 250, is_popular: true }, { name: 'Gorkha Strong', weight: '330ml', price: 280, is_popular: false }, { name: 'Sherpa Dark', weight: '330ml', price: 300, is_popular: false }] },
      { name: 'Mojito', description: 'Classic mojito with fresh mint, lime, and soda', basePrice: 300, category: 'Beverages', images: ['https://images.unsplash.com/photo-1551538827-9c037cb4f1b8?auto=format&fit=crop&w=400&q=80'], calories: 120, portionWeight: '1 glass (350ml)', allergens: [], ingredients: ['Mint', 'Lime', 'Sugar', 'Soda water', 'Ice'], prepTime: 5, sizes: [{ name: 'Regular', weight: '350ml', price: 300, is_popular: true }] },
    ],
  },

  {
    name: 'Asan Chwok Sweets & Snacks',
    ownerName: 'Hari Sharma',
    phone: '9809876543',
    email: 'hari@asanchwok.com',
    address: 'Asan Chowk, Kathmandu 44600',
    description: 'A beloved Kathmandu institution since 1985. Famous for our traditional Nepali sweets, samosas, and quick bites. Located in the historic Asan market, we serve the best street food in the valley with hygienic standards.',
    cuisine: 'Nepali Street Food, Sweets',
    openTime: '6:00 AM',
    closeTime: '8:00 PM',
    logoUrl: 'https://images.unsplash.com/photo-1585032226651-759b368d7246?auto=format&fit=crop&w=200&q=80',
    coverUrl: 'https://images.unsplash.com/photo-1555939594-58d7cb561ad1?auto=format&fit=crop&w=800&q=80',
    menuItems: [
      { name: 'Veg Samosa (2 pcs)', description: 'Crispy fried pastry filled with spiced potatoes and peas, served with tamarind and mint chutney', basePrice: 60, category: 'Snacks', images: ['https://images.unsplash.com/photo-1601050690597-df0568f70950?auto=format&fit=crop&w=400&q=80'], calories: 200, portionWeight: '2 pieces (120g)', allergens: ['Gluten'], ingredients: ['Flour', 'Potato', 'Peas', 'Cumin', 'Coriander', 'Garam masala', 'Oil'], prepTime: 10, sizes: [{ name: '2 Pieces', weight: '120g', price: 60, is_popular: true }, { name: '4 Pieces', weight: '240g', price: 110, is_popular: false }] },
      { name: 'Pani Puri (6 pcs)', description: 'Crispy hollow puri filled with spicy tamarind water, chickpeas, and potatoes', basePrice: 80, category: 'Chaats', images: ['https://images.unsplash.com/photo-1585032226651-759b368d7246?auto=format&fit=crop&w=400&q=80'], calories: 180, portionWeight: '6 pieces (200g)', allergens: ['Gluten'], ingredients: ['Puri', 'Tamarind', 'Chickpeas', 'Potato', 'Mint', 'Chili powder', 'Cumin'], prepTime: 8, sizes: [{ name: '6 Pieces', weight: '200g', price: 80, is_popular: true }, { name: '12 Pieces', weight: '400g', price: 150, is_popular: false }] },
      { name: 'Aloo Chop (2 pcs)', description: 'Deep-fried spicy potato cutlets with lentils and aromatic spices', basePrice: 50, category: 'Snacks', images: ['https://images.unsplash.com/photo-1601050690597-df0568f70950?auto=format&fit=crop&w=400&q=80'], calories: 220, portionWeight: '2 pieces (100g)', allergens: [], ingredients: ['Potato', 'Lentils', 'Cumin', 'Coriander', 'Green chillies', 'Ginger', 'Oil'], prepTime: 10, sizes: [{ name: '2 Pieces', weight: '100g', price: 50, is_popular: true }, { name: '4 Pieces', weight: '200g', price: 95, is_popular: false }] },
      { name: 'Jalebi (250g)', description: 'Crispy deep-fried pretzels soaked in saffron sugar syrup — hot and fresh', basePrice: 100, category: 'Sweets', images: ['https://images.unsplash.com/photo-1589119908995-c6837e14860a?auto=format&fit=crop&w=400&q=80'], calories: 350, portionWeight: '250g', allergens: ['Gluten'], ingredients: ['Flour', 'Sugar', 'Saffron', 'Cardamom', 'Oil', 'Rose water'], prepTime: 15, sizes: [{ name: '250g', weight: '250g', price: 100, is_popular: true }, { name: '500g', weight: '500g', price: 180, is_popular: false }] },
      { name: 'Rasgulla (4 pcs)', description: 'Soft spongy cottage cheese balls in sweet rose-flavored syrup', basePrice: 120, category: 'Sweets', images: ['https://images.unsplash.com/photo-1589119908995-c6837e14860a?auto=format&fit=crop&w=400&q=80'], calories: 280, portionWeight: '4 pieces (200g)', allergens: ['Milk'], ingredients: ['Cottage cheese', 'Sugar', 'Rose water', 'Cardamom'], prepTime: 5, sizes: [{ name: '4 Pieces', weight: '200g', price: 120, is_popular: true }, { name: '8 Pieces', weight: '400g', price: 220, is_popular: false }] },
      { name: 'Chicken MoMo (Fried)', description: 'Our famous crispy fried chicken momo with achar — a customer favorite', basePrice: 220, category: 'Momo', images: ['https://images.unsplash.com/photo-1601050690597-df0568f70950?auto=format&fit=crop&w=400&q=80'], calories: 420, portionWeight: '8 pieces (280g)', allergens: ['Gluten'], ingredients: ['Chicken', 'Flour', 'Onion', 'Ginger', 'Garlic', 'Coriander', 'Oil'], prepTime: 20, sizes: [{ name: 'Half Plate', weight: '5 pcs (180g)', price: 150, is_popular: false }, { name: 'Full Plate', weight: '8 pcs (280g)', price: 220, is_popular: true }] },
      { name: 'Lassi (Sweet)', description: 'Thick and creamy sweet yogurt drink with cardamom', basePrice: 80, category: 'Beverages', images: ['https://images.unsplash.com/photo-1558002038-1055907df827?auto=format&fit=crop&w=400&q=80'], calories: 150, portionWeight: '1 glass (250ml)', allergens: ['Milk'], ingredients: ['Yogurt', 'Sugar', 'Cardamom', 'Water'], prepTime: 3, sizes: [{ name: 'Small', weight: '200ml', price: 60, is_popular: false }, { name: 'Regular', weight: '250ml', price: 80, is_popular: true }, { name: 'Large', weight: '400ml', price: 120, is_popular: false }] },
    ],
  },

  {
    name: 'Basantapur Bojho',
    ownerName: 'Maya Rai',
    phone: '9812340987',
    email: 'maya@basantapurbojho.com',
    address: 'Basantapur Durbar Square, Kathmandu 44600',
    description: 'A rooftop restaurant with breathtaking views of Basantapur Durbar Square. We serve authentic Nepali homestyle cooking using organic ingredients from our family farm. Experience Nepal through our food.',
    cuisine: 'Nepali, Organic, Homestyle',
    openTime: '9:00 AM',
    closeTime: '9:00 PM',
    logoUrl: 'https://images.unsplash.com/photo-1542528180-d1c3d1a69b4a?auto=format&fit=crop&w=200&q=80',
    coverUrl: 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?auto=format&fit=crop&w=800&q=80',
    menuItems: [
      { name: 'Gundruk Pakoda', description: 'Crispy fritters made from fermented leafy greens (gundruk) — a traditional Nepali delicacy', basePrice: 150, category: 'Starters', images: ['https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?auto=format&fit=crop&w=400&q=80'], calories: 250, portionWeight: '6 pieces (150g)', allergens: ['Gluten'], ingredients: ['Gundruk', 'Rice flour', 'Cumin', 'Turmeric', 'Green chillies', 'Oil'], prepTime: 15, sizes: [{ name: 'Regular', weight: '150g', price: 150, is_popular: true }] },
      { name: 'Kwati (Mixed Bean Soup)', description: 'Traditional Newari soup made from 9 types of sprouted beans — a protein-rich comfort food', basePrice: 200, category: 'Soups', images: ['https://images.unsplash.com/photo-1547592166-23ac45744acd?auto=format&fit=crop&w=400&q=80'], calories: 280, portionWeight: '1 bowl (350ml)', allergens: [], ingredients: ['Mixed beans', 'Cumin', 'Ginger', 'Garlic', 'Turmeric', 'Ghee', 'Coriander'], prepTime: 25, sizes: [{ name: 'Bowl', weight: '350ml', price: 200, is_popular: true }, { name: 'Large Bowl', weight: '500ml', price: 280, is_popular: false }] },
      { name: 'Sisno Ko Jhol (Nettle Soup)', description: 'Traditional Nepali stinging nettle soup with garlic and butter — a nutrient powerhouse', basePrice: 180, category: 'Soups', images: ['https://images.unsplash.com/photo-1547592166-23ac45744acd?auto=format&fit=crop&w=400&q=80'], calories: 120, portionWeight: '1 bowl (300ml)', allergens: [], ingredients: ['Stinging nettle', 'Garlic', 'Butter', 'Cumin', 'Rice flour', 'Salt'], prepTime: 20, sizes: [{ name: 'Bowl', weight: '300ml', price: 180, is_popular: true }] },
      { name: 'Organic Dal Bhat', description: 'Our farm-to-table dal bhat with organic black lentils, mountain rice, seasonal vegetables, and homemade achar', basePrice: 300, category: 'Main Course', images: ['https://images.unsplash.com/photo-1565557623262-b51c2513a641?auto=format&fit=crop&w=400&q=80', 'https://images.unsplash.com/photo-1585937421612-70a008356fbe?auto=format&fit=crop&w=400&q=80', 'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?auto=format&fit=crop&w=400&q=80'], calories: 550, portionWeight: 'Full thali (750g)', allergens: ['Milk'], ingredients: ['Organic rice', 'Black lentils', 'Seasonal vegetables', 'Ghee', 'Spices', 'Homemade achar'], prepTime: 25, sizes: [{ name: 'Regular', weight: '750g', price: 300, is_popular: true }, { name: 'Large', weight: '1kg', price: 400, is_popular: false }] },
      { name: 'Nepali Khasi Ko Masu', description: 'Slow-cooked organic goat curry with traditional spices, timur, and mountain herbs', basePrice: 500, category: 'Main Course', images: ['https://images.unsplash.com/photo-1544025162-d76694265947?auto=format&fit=crop&w=400&q=80'], calories: 420, portionWeight: '1 serving (250g)', allergens: [], ingredients: ['Goat meat', 'Onion', 'Tomato', 'Timur', 'Cumin', 'Coriander', 'Garlic', 'Ginger', 'Mustard oil'], prepTime: 45, sizes: [{ name: 'Half', weight: '150g', price: 300, is_popular: false }, { name: 'Full', weight: '250g', price: 500, is_popular: true }] },
      { name: 'Aloo Tama Bodi', description: 'Traditional Newari curry with potato, bamboo shoots, and black-eyed peas in a tangy gravy', basePrice: 220, category: 'Main Course', images: ['https://images.unsplash.com/photo-1565557623262-b51c2513a641?auto=format&fit=crop&w=400&q=80'], calories: 320, portionWeight: '1 serving (300g)', allergens: [], ingredients: ['Potato', 'Bamboo shoots', 'Black-eyed peas', 'Cumin', 'Turmeric', 'Garlic', 'Mustard oil'], prepTime: 30, sizes: [{ name: 'Regular', weight: '300g', price: 220, is_popular: true }] },
      { name: 'Sel Roti', description: 'Traditional Nepali homemade sweet ring-shaped rice bread, fried to golden perfection', basePrice: 80, category: 'Snacks', images: ['https://images.unsplash.com/photo-1558961363-fa8fdf82db35?auto=format&fit=crop&w=400&q=80'], calories: 180, portionWeight: '3 pieces (100g)', allergens: ['Gluten'], ingredients: ['Rice flour', 'Sugar', 'Banana', 'Ghee', 'Cardamom', 'Oil'], prepTime: 15, sizes: [{ name: '3 Pieces', weight: '100g', price: 80, is_popular: true }, { name: '6 Pieces', weight: '200g', price: 150, is_popular: false }] },
    ],
  },

  {
    name: 'Pizza Pizza Pasta',
    ownerName: 'Arun Basnet',
    phone: '9865432101',
    email: 'arun@pizzapizza.com',
    address: 'Jawalakhel, Lalitpur 44700 (Near Zoo)',
    description: 'Kathmandu\'s favorite Italian restaurant serving authentic wood-fired pizzas, homemade pasta, and classic Italian desserts. Our wood-fired oven was imported from Naples, and our pasta is made fresh daily.',
    cuisine: 'Italian, Pizza, Pasta',
    openTime: '11:00 AM',
    closeTime: '10:30 PM',
    logoUrl: 'https://images.unsplash.com/photo-1513104890138-7c749659a591?auto=format&fit=crop&w=200&q=80',
    coverUrl: 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4?auto=format&fit=crop&w=800&q=80',
    menuItems: [
      { name: 'Margherita Pizza', description: 'Authentic Neapolitan pizza with San Marzano tomato sauce, fresh mozzarella, and basil from our garden', basePrice: 450, category: 'Pizza', images: ['https://images.unsplash.com/photo-1574071318508-1cdbab80d002?auto=format&fit=crop&w=400&q=80', 'https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?auto=format&fit=crop&w=400&q=80', 'https://images.unsplash.com/photo-1628840042765-356cda07504e?auto=format&fit=crop&w=400&q=80'], calories: 720, portionWeight: '1 pizza (350g)', allergens: ['Gluten', 'Milk'], ingredients: ['Pizza dough', 'San Marzano tomatoes', 'Mozzarella', 'Fresh basil', 'Olive oil', 'Salt'], prepTime: 20, sizes: [{ name: 'Small', weight: '250g (8\")', price: 350, is_popular: false }, { name: 'Medium', weight: '350g (10\")', price: 450, is_popular: true }, { name: 'Large', weight: '500g (12\")', price: 650, is_popular: false }] },
      { name: 'Pepperoni Pizza', description: 'Classic pepperoni pizza with mozzarella, tomato sauce, and spicy Italian pepperoni', basePrice: 550, category: 'Pizza', images: ['https://images.unsplash.com/photo-1628840042765-356cda07504e?auto=format&fit=crop&w=400&q=80'], calories: 820, portionWeight: '1 pizza (400g)', allergens: ['Gluten', 'Milk'], ingredients: ['Pizza dough', 'Tomato sauce', 'Mozzarella', 'Pepperoni', 'Olive oil', 'Oregano'], prepTime: 20, sizes: [{ name: 'Small', weight: '250g (8\")', price: 400, is_popular: false }, { name: 'Medium', weight: '400g (10\")', price: 550, is_popular: true }, { name: 'Large', weight: '600g (12\")', price: 750, is_popular: false }] },
      { name: 'Pasta Alfredo', description: 'Creamy fettuccine alfredo with parmesan, garlic, and fresh parsley', basePrice: 380, category: 'Pasta', images: ['https://images.unsplash.com/photo-1645112411341-6c4fd023714a?auto=format&fit=crop&w=400&q=80', 'https://images.unsplash.com/photo-1612874742237-6526221588e3?auto=format&fit=crop&w=400&q=80'], calories: 580, portionWeight: '1 plate (350g)', allergens: ['Gluten', 'Milk'], ingredients: ['Fettuccine', 'Cream', 'Parmesan', 'Garlic', 'Butter', 'Parsley'], prepTime: 18, sizes: [{ name: 'Regular', weight: '350g', price: 380, is_popular: true }, { name: 'Large', weight: '500g', price: 500, is_popular: false }] },
      { name: 'Penne Arrabiata', description: 'Penne pasta in spicy tomato sauce with garlic, chili flakes, and fresh basil', basePrice: 320, category: 'Pasta', images: ['https://images.unsplash.com/photo-1612874742237-6526221588e3?auto=format&fit=crop&w=400&q=80'], calories: 420, portionWeight: '1 plate (350g)', allergens: ['Gluten'], ingredients: ['Penne', 'Tomato', 'Garlic', 'Chili flakes', 'Olive oil', 'Basil'], prepTime: 18, sizes: [{ name: 'Regular', weight: '350g', price: 320, is_popular: true }, { name: 'Large', weight: '500g', price: 420, is_popular: false }] },
      { name: 'Lasagna', description: 'Classic Italian lasagna with layers of pasta, béchamel sauce, Bolognese ragù, and melted mozzarella', basePrice: 480, category: 'Pasta', images: ['https://images.unsplash.com/photo-1619895092538-128341789043?auto=format&fit=crop&w=400&q=80'], calories: 680, portionWeight: '1 slice (350g)', allergens: ['Gluten', 'Milk', 'Egg'], ingredients: ['Pasta sheets', 'Beef mince', 'Béchamel', 'Mozzarella', 'Tomato', 'Onion', 'Garlic'], prepTime: 30, sizes: [{ name: 'Single', weight: '350g', price: 480, is_popular: true }, { name: 'Double', weight: '600g', price: 780, is_popular: false }] },
      { name: 'Garlic Bread with Cheese', description: 'Toasted Italian bread with garlic butter, melted mozzarella, and herbs', basePrice: 180, category: 'Starters', images: ['https://images.unsplash.com/photo-1619535860376-5f268430a92b?auto=format&fit=crop&w=400&q=80'], calories: 380, portionWeight: '4 pieces (150g)', allergens: ['Gluten', 'Milk'], ingredients: ['Italian bread', 'Garlic', 'Butter', 'Mozzarella', 'Oregano', 'Parsley'], prepTime: 10, sizes: [{ name: '4 Pieces', weight: '150g', price: 180, is_popular: true }, { name: '8 Pieces', weight: '300g', price: 320, is_popular: false }] },
      { name: 'Tiramisu', description: 'Classic Italian tiramisu with mascarpone, espresso-soaked ladyfingers, and cocoa', basePrice: 250, category: 'Desserts', images: ['https://images.unsplash.com/photo-1571877227200-a0d98ea607e9?auto=format&fit=crop&w=400&q=80'], calories: 380, portionWeight: '1 slice (150g)', allergens: ['Milk', 'Gluten', 'Egg'], ingredients: ['Mascarpone', 'Espresso', 'Ladyfingers', 'Cocoa', 'Eggs', 'Sugar'], prepTime: 5, sizes: [{ name: 'Slice', weight: '150g', price: 250, is_popular: true }] },
    ],
  },

  {
    name: 'Doko Fresh Juice Corner',
    ownerName: 'Sarita Karki',
    phone: '9845678901',
    email: 'sarita@dokofresh.com',
    address: 'Kupondole, Lalitpur 44700',
    description: 'Fresh, healthy, and affordable! We serve cold-pressed juices, smoothie bowls, fresh fruit salads, and healthy light meals. Everything is organic and sourced from local farmers. Your daily dose of wellness.',
    cuisine: 'Healthy, Juices, Smoothies',
    openTime: '7:00 AM',
    closeTime: '7:00 PM',
    logoUrl: 'https://images.unsplash.com/photo-1505252585461-04db1eb84625?auto=format&fit=crop&w=200&q=80',
    coverUrl: 'https://images.unsplash.com/photo-1498837167922-ddd27525d352?auto=format&fit=crop&w=800&q=80',
    menuItems: [
      { name: 'Green Detox Juice', description: 'Cold-pressed juice with spinach, celery, green apple, ginger, and lemon', basePrice: 180, category: 'Juices', images: ['https://images.unsplash.com/photo-1610970881699-44a5587cabec?auto=format&fit=crop&w=400&q=80'], calories: 95, portionWeight: '1 glass (350ml)', allergens: [], ingredients: ['Spinach', 'Celery', 'Green apple', 'Ginger', 'Lemon'], prepTime: 5, sizes: [{ name: 'Small', weight: '250ml', price: 130, is_popular: false }, { name: 'Regular', weight: '350ml', price: 180, is_popular: true }, { name: 'Large', weight: '500ml', price: 250, is_popular: false }] },
      { name: 'Tropical Fruit Bowl', description: 'Fresh mango, papaya, banana, dragon fruit, and granola topped with honey and chia seeds', basePrice: 280, category: 'Bowls', images: ['https://images.unsplash.com/photo-1511690743698-d9d41f3f6d99?auto=format&fit=crop&w=400&q=80'], calories: 320, portionWeight: '1 bowl (350g)', allergens: ['Milk'], ingredients: ['Mango', 'Papaya', 'Banana', 'Dragon fruit', 'Granola', 'Honey', 'Chia seeds'], prepTime: 8, sizes: [{ name: 'Regular', weight: '350g', price: 280, is_popular: true }, { name: 'Large', weight: '500g', price: 380, is_popular: false }] },
      { name: 'Acai Smoothie Bowl', description: 'Blended acai berries with banana, topped with fresh fruits, coconut flakes, and granola', basePrice: 350, category: 'Bowls', images: ['https://images.unsplash.com/photo-1590301157890-4810ed352733?auto=format&fit=crop&w=400&q=80'], calories: 350, portionWeight: '1 bowl (400g)', allergens: ['Milk'], ingredients: ['Acai', 'Banana', 'Mixed berries', 'Granola', 'Coconut flakes', 'Honey'], prepTime: 10, sizes: [{ name: 'Regular', weight: '400g', price: 350, is_popular: true }] },
      { name: 'Mango Lassi', description: 'Thick and creamy yogurt drink blended with fresh Alphonso mangoes and cardamom', basePrice: 180, category: 'Smoothies', images: ['https://images.unsplash.com/photo-1527661591475-527312dd65f5?auto=format&fit=crop&w=400&q=80'], calories: 220, portionWeight: '1 glass (300ml)', allergens: ['Milk'], ingredients: ['Mango', 'Yogurt', 'Sugar', 'Cardamom', 'Milk'], prepTime: 5, sizes: [{ name: 'Small', weight: '200ml', price: 130, is_popular: false }, { name: 'Regular', weight: '300ml', price: 180, is_popular: true }, { name: 'Large', weight: '500ml', price: 280, is_popular: false }] },
      { name: 'Protein Power Smoothie', description: 'Peanut butter, banana, dates, oats, and milk blended into a protein-packed smoothie', basePrice: 220, category: 'Smoothies', images: ['https://images.unsplash.com/photo-1527661591475-527312dd65f5?auto=format&fit=crop&w=400&q=80'], calories: 380, portionWeight: '1 glass (350ml)', allergens: ['Milk', 'Peanuts', 'Gluten'], ingredients: ['Peanut butter', 'Banana', 'Dates', 'Oats', 'Milk', 'Honey'], prepTime: 5, sizes: [{ name: 'Regular', weight: '350ml', price: 220, is_popular: true }] },
      { name: 'Fresh Orange Juice', description: 'Freshly squeezed from locally grown oranges — no sugar, no water added', basePrice: 150, category: 'Juices', images: ['https://images.unsplash.com/photo-1610970881699-44a5587cabec?auto=format&fit=crop&w=400&q=80'], calories: 110, portionWeight: '1 glass (300ml)', allergens: [], ingredients: ['Fresh oranges'], prepTime: 3, sizes: [{ name: 'Small', weight: '200ml', price: 100, is_popular: false }, { name: 'Regular', weight: '300ml', price: 150, is_popular: true }, { name: 'Large', weight: '500ml', price: 220, is_popular: false }] },
      { name: 'Veggie Wrap', description: 'Whole wheat wrap with hummus, roasted vegetables, lettuce, and tahini dressing', basePrice: 250, category: 'Light Meals', images: ['https://images.unsplash.com/photo-1626700051175-6818013e1d4f?auto=format&fit=crop&w=400&q=80'], calories: 320, portionWeight: '1 wrap (250g)', allergens: ['Gluten', 'Sesame'], ingredients: ['Whole wheat tortilla', 'Hummus', 'Roasted vegetables', 'Lettuce', 'Tahini', 'Lemon'], prepTime: 10, sizes: [{ name: '1 Wrap', weight: '250g', price: 250, is_popular: true }] },
    ],
  },
];

// ─── Order Data ────────────────────────────────

function generateOrderNumber(index: number): string {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  let code = '';
  for (let i = 0; i < 5; i++) code += chars[Math.floor(Math.random() * chars.length)];
  return `DAILO-${code}`;
}

// ─── Main Seed Function ────────────────────────

async function main() {
  console.log('🚀 Starting seed...\n');

  // 1. Fetch existing users
  const { data: users, error: ue } = await supabase.admin
    .from('users')
    .select('id, username, role')
    .limit(50);

  if (ue) {
    console.error('❌ Failed to fetch users:', ue.message);
    process.exit(1);
  }

  console.log(`📋 Found ${users?.length || 0} users in database`);
  if (!users || users.length === 0) {
    console.log('⚠️  No users found. Will create seed users...');
    // Can't create users easily without auth flow, so exit
    console.log('❌ Please create at least one user first via the signup flow.');
    process.exit(1);
  }

  // Print users for reference
  const regularUsers = users.filter(u => u.role === 'USER' || u.role === 'CUSTOMER');
  const ownerUsers = users.filter(u => u.role === 'RESTAURANT_OWNER');
  console.log(`   👤 Regular users: ${regularUsers.length}`);
  console.log(`   🏪 Existing owners: ${ownerUsers.length}`);

  // Get existing restaurants to check their user_ids
  const { data: existingRests } = await supabase.admin
    .from('restaurant_applications')
    .select('id, restaurant_name, user_id, status');

  const existingNames = new Set(existingRests?.map(r => r.restaurant_name) || []);
  const existingUserIds = new Set(existingRests?.map(r => r.user_id) || []);
  console.log(`   🏪 Existing restaurants: ${existingRests?.length || 0}`);

  // 2. Assign owners — use existing owner users first, then regular users
  const assignableUsers = [...ownerUsers, ...regularUsers];
  if (assignableUsers.length === 0) {
    console.error('❌ No assignable users found. Create users first!');
    process.exit(1);
  }

  let userIndex = 0;
  const restaurantUserMap: { userId: string; restIndex: number }[] = [];

  for (let i = 0; i < RESTAURANTS.length; i++) {
    const rest = RESTAURANTS[i];
    if (existingNames.has(rest.name)) {
      console.log(`⏩ Skipping "${rest.name}" — already exists`);
      continue;
    }

    const user = assignableUsers[userIndex % assignableUsers.length];
    restaurantUserMap.push({ userId: user.id, restIndex: i });
    userIndex++;

    // If user isn't already an owner, update their role
    if (user.role !== 'RESTAURANT_OWNER' && !existingUserIds.has(user.id)) {
      console.log(`   🔄 Promoting ${user.username || user.id.slice(0, 8)} to RESTAURANT_OWNER`);
      await supabase.admin
        .from('users')
        .update({ role: 'RESTAURANT_OWNER', status: 'ACTIVE' })
        .eq('id', user.id);
    }
  }

  }

  // If restaurants already existed, we still create orders
  if (restaurantUserMap.length > 0) {
    console.log(`\n🍽️  Creating ${restaurantUserMap.length} restaurants...`);

    for (const { userId, restIndex } of restaurantUserMap) {
      const rest = RESTAURANTS[restIndex];

      const { data: application, error } = await supabase.admin
        .from('restaurant_applications')
        .insert({
          user_id: userId,
          restaurant_name: rest.name,
          owner_name: rest.ownerName,
          phone: rest.phone,
          email: rest.email,
          address: rest.address,
          description: rest.description,
          cuisine_type: rest.cuisine,
          pan_number: `PAN-${Math.floor(100000 + Math.random() * 900000)}`,
          pan_certificate_url: 'https://images.unsplash.com/photo-1554224155-8d04cb21cd6c?auto=format&fit=crop&w=400&q=80',
          logo_url: rest.logoUrl,
          cover_image_url: rest.coverUrl,
          open_time: rest.openTime,
          close_time: rest.closeTime,
          status: 'APPROVED',
          is_accepting_orders: true,
        })
        .select('id, restaurant_name')
        .single();

      if (error) {
        console.error(`❌ Failed to create "${rest.name}":`, error.message);
        continue;
      }

      console.log(`   ✅ Created "${rest.name}" (${application.id.slice(0, 8)}...)`);

      // Create menu items for this restaurant
      const restItems = rest.menuItems;
      console.log(`      📝 Adding ${restItems.length} menu items...`);

      for (const item of restItems) {
        const { error: itemError } = await supabase.admin
          .from('menu_items')
          .insert({
            restaurant_id: application.id,
            name: item.name,
            description: item.description,
            base_price: item.basePrice,
            category: item.category,
            is_available: true,
            images: item.images,
            calories: item.calories,
            portion_weight: item.portionWeight,
            allergens: item.allergens,
            ingredients: item.ingredients,
            sizes: item.sizes,
            prep_time: item.prepTime,
          });

        if (itemError) {
          console.error(`         ❌ Failed to create "${item.name}":`, itemError.message);
        }
      }

      console.log(`      ✅ ${restItems.length} menu items created`);
    }
  } else {
    console.log('✅ All restaurants already exist. Skipping restaurant creation.');
  }

  // 5. Create sample orders in various statuses (always attempt)
  console.log(`\n📦 Creating sample orders...`);

  const { data: seededRests } = await supabase.admin
    .from('restaurant_applications')
    .select('id, restaurant_name');

  if (seededRests && seededRests.length > 0 && regularUsers.length > 0) {
    const statuses = ['PENDING', 'ACCEPTED', 'PREPARING', 'READY', 'PICKED_UP', 'DELIVERED'] as const;
    
    for (let i = 0; i < Math.min(12, seededRests.length * 2); i++) {
      const rest = seededRests[i % seededRests.length];
      const user = regularUsers[i % regularUsers.length];
      const status = statuses[i % statuses.length];

      // Get some menu items for this restaurant
      const { data: items } = await supabase.admin
        .from('menu_items')
        .select('id, name, base_price')
        .eq('restaurant_id', rest.id)
        .limit(3);

      if (!items || items.length === 0) continue;

      const orderItems = items.map((item: any) => ({
        food_id: item.id,
        name: item.name,
        price: item.base_price,
        quantity: Math.floor(1 + Math.random() * 3),
        image_url: null as string | null,
      }));

      const subtotal = orderItems.reduce((sum: number, item: any) => sum + item.price * item.quantity, 0);
      const deliveryFee = Math.random() > 0.3 ? 50 : 0;
      const total = subtotal + deliveryFee;

      // Build status timestamps
      const timestamps: Record<string, string> = {
        created_at: now(i * 120),
        updated_at: now(0),
      };

      if (status !== 'PENDING') timestamps.accepted_at = now(i * 120 - 90);
      if (['PREPARING', 'READY', 'PICKED_UP', 'DELIVERED'].includes(status)) timestamps.preparing_at = now(i * 120 - 60);
      if (['READY', 'PICKED_UP', 'DELIVERED'].includes(status)) timestamps.ready_at = now(i * 120 - 30);
      if (['PICKED_UP', 'DELIVERED'].includes(status)) timestamps.picked_up_at = now(i * 120 - 15);
      if (status === 'DELIVERED') timestamps.delivered_at = now(i * 120 - 5);

      const { error: orderError } = await supabase.admin
        .from('orders')
        .insert({
          user_id: user.id,
          restaurant_id: rest.id,
          order_number: generateOrderNumber(i),
          status,
          items: orderItems,
          subtotal,
          delivery_fee: deliveryFee,
          total,
          delivery_address: {
            full_address: 'Thamel, Kathmandu 44600',
            latitude: 27.7172,
            longitude: 85.3240,
          },
          created_at: now(i * 120),
          updated_at: now(0),
        });

      if (orderError) {
        console.error(`   ❌ Failed to create order #${i + 1}:`, orderError.message);
      } else {
        console.log(`   ✅ Created order ${generateOrderNumber(i)} (${status})`);
      }
    }

    console.log(`   ✅ ${Math.min(12, seededRests.length * 2)} sample orders created`);
  }

  // 6. Verify all data
  await verifyData();

  console.log('\n🎉 Seed complete!\n');
}

async function verifyData() {
  console.log('\n📊 VERIFICATION:');

  const { data: rests } = await supabase.admin
    .from('restaurant_applications')
    .select('id, restaurant_name, status, cuisine_type, logo_url')
    .order('created_at', { ascending: false });

  console.log(`🏪 Total restaurants: ${rests?.length || 0}`);
  if (rests) {
    for (const r of rests) {
      const { data: items } = await supabase.admin
        .from('menu_items')
        .select('id')
        .eq('restaurant_id', r.id);
      
      const { data: orders } = await supabase.admin
        .from('orders')
        .select('id, status')
        .eq('restaurant_id', r.id);

      console.log(`   ${r.restaurant_name.padEnd(30)} | ${r.status.padEnd(10)} | ${(items?.length || 0).toString().padStart(2)} items | ${(orders?.length || 0).toString().padStart(2)} orders`);
    }
  }

  const { data: totalItems } = await supabase.admin
    .from('menu_items')
    .select('id');

  console.log(`📝 Total menu items: ${totalItems?.length || 0}`);

  const { data: totalOrders } = await supabase.admin
    .from('orders')
    .select('id');

  console.log(`📦 Total orders: ${totalOrders?.length || 0}`);
}

main().catch(console.error);
