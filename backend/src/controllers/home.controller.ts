import { Request, Response } from 'express';
import { supabase } from '../db/supabase';
import { getUserId } from '../utils/auth';

/**
 * Mapping from time-of-day to relevant menu item categories.
 * Menu items with these category names (case-insensitive) will be
 * suggested for each time period. Falls back to ALL categories
 * for night / unknown periods.
 */
const TIME_OF_DAY_CATEGORIES: Record<string, string[]> = {
  morning: ['Breakfast', 'Morning', 'Brunch'],
  afternoon: ['Lunch', 'Main Course', 'Rice', 'Noodles', 'Biriyani'],
  evening: ['Dinner', 'Main Course', 'Rice', 'Noodles', 'Pizza', 'Momo', 'Burger'],
  night: [], // empty = show all
};

/**
 * Time boundaries: hour ranges that map to a time-of-day label.
 */
function getTimeOfDay(): string {
  const hour = new Date().getHours();
  if (hour >= 5 && hour < 12) return 'morning';
  if (hour >= 12 && hour < 17) return 'afternoon';
  if (hour >= 17 && hour < 21) return 'evening';
  return 'night';
}

/**
 * GET /api/home/suggestions
 *
 * Returns curated home-screen data based on the current time of day:
 *   - time_of_day       – current period label
 *   - greeting          – friendly greeting with emoji
 *   - suggested_restaurants – restaurants whose menu items match the period
 *   - all_restaurants   – complete restaurant list (for fallback / other sections)
 *   - favorite_cuisines – cuisine types the user has ordered most (requires auth)
 *
 * Query params:
 *   time_of_day - optional override (morning|afternoon|evening|night).
 *                 Defaults to the actual current time.
 */
/**
 * GET /api/home/surprise-me
 *
 * Picks a random restaurant the authenticated user hasn't ordered from yet.
 * If the user has ordered from every restaurant, picks one of their favorites
 * (highest-rated restaurants they've ordered from).
 *
 * Returns:
 *   - restaurant — the randomly selected restaurant (full object)
 *   - already_ordered_from_all — true if user has tried every restaurant
 */
export const surpriseMe = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    // ── Fetch all approved restaurants with menu items ──
    const { data: restaurants, error } = await supabase.admin
      .from('restaurant_applications')
      .select('*')
      .eq('status', 'APPROVED')
      .eq('is_accepting_orders', true)
      .order('created_at', { ascending: false });

    if (error || !restaurants || restaurants.length === 0) {
      res.status(200).json({ restaurant: null, already_ordered_from_all: false });
      return;
    }

    const restaurantIds = restaurants.map((r: any) => r.id);

    // ── Fetch menu items ──
    const { data: menuItems } = await supabase.admin
      .from('menu_items')
      .select('*')
      .in('restaurant_id', restaurantIds)
      .eq('is_available', true);

    const menuByRestaurant: Record<string, any[]> = {};
    if (menuItems) {
      for (const item of menuItems) {
        const rid = item.restaurant_id;
        if (!menuByRestaurant[rid]) menuByRestaurant[rid] = [];
        menuByRestaurant[rid].push(item);
      }
    }

    // ── Fetch restaurant IDs the user has already ordered from ──
    const { data: pastOrders } = await supabase.admin
      .from('orders')
      .select('restaurant_id')
      .eq('user_id', userId)
      .in('status', ['DELIVERED', 'CANCELLED']);

    const orderedRestaurantIds = new Set<string>();
    if (pastOrders) {
      for (const order of pastOrders) {
        if (order.restaurant_id) orderedRestaurantIds.add(order.restaurant_id);
      }
    }

    // ── Filter to restaurants the user hasn't ordered from ──
    const untried = restaurants.filter((r: any) => !orderedRestaurantIds.has(r.id));

    let chosen: any;
    let alreadyOrderedFromAll = false;

    if (untried.length > 0) {
      // Pick a random untried restaurant
      chosen = untried[Math.floor(Math.random() * untried.length)];
    } else {
      // Tried everything — pick the highest rated they've ordered from
      alreadyOrderedFromAll = true;
      const tried = restaurants.filter((r: any) => orderedRestaurantIds.has(r.id));
      tried.sort((a: any, b: any) => (b.rating || 0) - (a.rating || 0));
      chosen = tried.length > 0 ? tried[0] : restaurants[0];
    }

    // ── Build response ──
    const foods = menuByRestaurant[chosen.id] || [];

    const restaurant = {
      id: chosen.id,
      name: chosen.restaurant_name,
      description: chosen.description || '',
      logo_url: chosen.logo_url || '',
      banner_url: chosen.cover_image_url || chosen.logo_url || '',
      rating: 4.5,
      delivery_time_minutes: 30,
      cuisine_type: chosen.cuisine_type || '',
      open_time: chosen.open_time || '9:00 AM',
      close_time: chosen.close_time || '11:00 PM',
      address: chosen.address || '',
      is_accepting_orders: chosen.is_accepting_orders !== false,
      foods: foods.map((item: any) => ({
        id: item.id,
        restaurant_id: item.restaurant_id,
        name: item.name,
        description: item.description || '',
        price: item.base_price,
        image_url: (item.images && item.images.length > 0) ? item.images[0] : (item.image_url || ''),
        images: item.images || [],
        category: item.category || '',
        is_available: item.is_available,
        sizes: item.sizes || [],
        calories: item.calories,
        portion_weight: item.portion_weight,
        allergens: item.allergens || [],
        ingredients: item.ingredients || [],
        prep_time: item.prep_time,
        created_at: item.created_at,
      })),
    };

    res.status(200).json({
      restaurant,
      already_ordered_from_all: alreadyOrderedFromAll,
    });
  } catch (error) {
    console.error('[SurpriseMe] Error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

/**
 * GET /api/home/personalized
 *
 * Returns personalized home-screen data based on the user's order history:
 *   - favorite_restaurants — restaurants the user has ordered from most
 *                            (sorted by order count, with full menu items)
 *   - most_ordered_items   — specific menu items the user has ordered repeatedly
 *                            (sorted by order count)
 *   - recent_restaurants   — restaurants from the user's most recent delivered orders
 *
 * All sections are empty arrays when the user has no order history.
 * Only restaurants that are still APPROVED and accepting orders are included.
 */
export const getPersonalized = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    // ── Fetch the user's delivered orders ──
    const { data: orders, error: ordersError } = await supabase.admin
      .from('orders')
      .select('*')
      .eq('user_id', userId)
      .eq('status', 'DELIVERED')
      .order('created_at', { ascending: false });

    if (ordersError) {
      console.error('[Personalized] Fetch orders error:', ordersError);
      res.status(200).json({
        favorite_restaurants: [],
        most_ordered_items: [],
        recent_restaurants: [],
      });
      return;
    }

    if (!orders || orders.length === 0) {
      res.status(200).json({
        favorite_restaurants: [],
        most_ordered_items: [],
        recent_restaurants: [],
      });
      return;
    }

    // ── Count restaurant order frequency ──
    const restaurantCounts: Record<string, number> = {};
    for (const order of orders) {
      if (order.restaurant_id) {
        restaurantCounts[order.restaurant_id] = (restaurantCounts[order.restaurant_id] || 0) + 1;
      }
    }

    // ── Count item order frequency (from order items JSON) ──
    const itemCounts: Record<string, { name: string; count: number; restaurant_id: string }> = {};
    for (const order of orders) {
      if (order.items && Array.isArray(order.items)) {
        for (const item of order.items) {
          const foodId = item.food_id || item.foodId;
          if (!foodId) continue;
          if (!itemCounts[foodId]) {
            itemCounts[foodId] = {
              name: item.name || 'Unknown',
              count: 0,
              restaurant_id: order.restaurant_id,
            };
          }
          itemCounts[foodId].count += item.quantity || 1;
        }
      }
    }

    // ── Get most ordered restaurant IDs (up to 5) ──
    const favoriteIds = Object.entries(restaurantCounts)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 5)
      .map(([id]) => id);

    // ── Get recent restaurant IDs (up to 4, deduplicated) ──
    const recentIds: string[] = [];
    for (const order of orders) {
      if (order.restaurant_id && !recentIds.includes(order.restaurant_id)) {
        recentIds.push(order.restaurant_id);
      }
      if (recentIds.length >= 4) break;
    }

    // ── Fetch restaurant details ──
    const allRequestedIds = [...new Set([...favoriteIds, ...recentIds])];
    const { data: restaurants } = await supabase.admin
      .from('restaurant_applications')
      .select('*')
      .eq('status', 'APPROVED')
      .eq('is_accepting_orders', true)
      .in('id', allRequestedIds);

    // Build a map for quick lookup
    const restaurantMap: Record<string, any> = {};
    if (restaurants) {
      for (const r of restaurants) {
        restaurantMap[r.id] = r;
      }
    }

    // ── Fetch menu items for these restaurants ──
    const { data: menuItems } = await supabase.admin
      .from('menu_items')
      .select('*')
      .in('restaurant_id', allRequestedIds)
      .eq('is_available', true);

    const menuByRestaurant: Record<string, any[]> = {};
    if (menuItems) {
      for (const item of menuItems) {
        const rid = item.restaurant_id;
        if (!menuByRestaurant[rid]) menuByRestaurant[rid] = [];
        menuByRestaurant[rid].push(item);
      }
    }

    // ── Helper: build restaurant response ──
    function buildRestaurant(r: any, foods: any[]) {
      return {
        id: r.id,
        name: r.restaurant_name,
        description: r.description || '',
        logo_url: r.logo_url || '',
        banner_url: r.cover_image_url || r.logo_url || '',
        rating: 4.5,
        delivery_time_minutes: 30,
        cuisine_type: r.cuisine_type || '',
        open_time: r.open_time || '9:00 AM',
        close_time: r.close_time || '11:00 PM',
        address: r.address || '',
        is_accepting_orders: r.is_accepting_orders !== false,
        order_count: restaurantCounts[r.id] || 0,
        foods: foods.map((item: any) => ({
          id: item.id,
          restaurant_id: item.restaurant_id,
          name: item.name,
          description: item.description || '',
          price: item.base_price,
          image_url: (item.images && item.images.length > 0) ? item.images[0] : (item.image_url || ''),
          images: item.images || [],
          category: item.category || '',
          is_available: item.is_available,
          sizes: item.sizes || [],
          calories: item.calories,
          portion_weight: item.portion_weight,
          allergens: item.allergens || [],
          ingredients: item.ingredients || [],
          prep_time: item.prep_time,
          created_at: item.created_at,
        })),
        user_order_count: restaurantCounts[r.id] || 0,
      };
    }

    // ── Build favorite restaurants (sorted by order count) ──
    const favoriteRestaurants = favoriteIds
      .map((id) => {
        const r = restaurantMap[id];
        if (!r) return null;
        const foods = menuByRestaurant[id] || [];
        return buildRestaurant(r, foods);
      })
      .filter(Boolean);

    // ── Build recent restaurants (preserving order) ──
    const recentRestaurants = recentIds
      .map((id) => {
        const r = restaurantMap[id];
        if (!r) return null;
        const foods = menuByRestaurant[id] || [];
        return buildRestaurant(r, foods);
      })
      .filter(Boolean);

    // ── Build most ordered items ──
    const mostOrderedItems = Object.entries(itemCounts)
      .sort((a, b) => b[1].count - a[1].count)
      .slice(0, 10)
      .map(([foodId, data]) => ({
        food_id: foodId,
        name: data.name,
        count: data.count,
        restaurant_id: data.restaurant_id,
      }));

    res.status(200).json({
      favorite_restaurants: favoriteRestaurants,
      most_ordered_items: mostOrderedItems,
      recent_restaurants: recentRestaurants,
    });
  } catch (error) {
    console.error('[Personalized] Error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

export const getHomeSuggestions = async (req: Request, res: Response): Promise<void> => {
  try {
    const timeOfDay = (req.query.time_of_day as string) || getTimeOfDay();
    const userId = await getUserId(req);

    // ── Greeting ──────────────────────────────
    const greeting = buildGreeting(timeOfDay);

    // ── Fetch all approved restaurants with menu items ──
    const { data: restaurants, error } = await supabase.admin
      .from('restaurant_applications')
      .select('*')
      .eq('status', 'APPROVED')
      .order('created_at', { ascending: false });

    if (error) {
      console.error('[HomeSuggestions] Fetch restaurants error:', error);
      res.status(500).json({ error: 'Failed to fetch suggestions.' });
      return;
    }

    if (!restaurants || restaurants.length === 0) {
      res.status(200).json({
        time_of_day: timeOfDay,
        greeting,
        suggested_restaurants: [],
        all_restaurants: [],
        favorite_cuisines: [],
      });
      return;
    }

    const restaurantIds = restaurants.map((r: any) => r.id);

    // ── Fetch all available menu items ──
    const { data: menuItems, error: menuError } = await supabase.admin
      .from('menu_items')
      .select('*')
      .in('restaurant_id', restaurantIds)
      .eq('is_available', true)
      .order('name');

    if (menuError) {
      console.error('[HomeSuggestions] Fetch menu items error:', menuError);
    }

    // ── Get target categories for this time of day ──
    const targetCategories = TIME_OF_DAY_CATEGORIES[timeOfDay] || [];

    // ── Group menu items by restaurant ──
    const menuByRestaurant: Record<string, any[]> = {};
    if (menuItems) {
      for (const item of menuItems) {
        const rid = item.restaurant_id;
        if (!menuByRestaurant[rid]) menuByRestaurant[rid] = [];
        menuByRestaurant[rid].push(item);
      }
    }

    // ── Helper: build a restaurant response object ──
    function buildRestaurant(r: any, foods: any[]) {
      return {
        id: r.id,
        name: r.restaurant_name,
        description: r.description || '',
        logo_url: r.logo_url || '',
        banner_url: r.cover_image_url || r.logo_url || '',
        rating: 4.5,
        delivery_time_minutes: 30,
        cuisine_type: r.cuisine_type || '',
        open_time: r.open_time || '9:00 AM',
        close_time: r.close_time || '11:00 PM',
        address: r.address || '',
        is_accepting_orders: r.is_accepting_orders !== false,
        foods: foods.map((item: any) => ({
          id: item.id,
          restaurant_id: item.restaurant_id,
          name: item.name,
          description: item.description || '',
          price: item.base_price,
          image_url: (item.images && item.images.length > 0) ? item.images[0] : (item.image_url || ''),
          images: item.images || [],
          category: item.category || '',
          is_available: item.is_available,
          sizes: item.sizes || [],
          calories: item.calories,
          portion_weight: item.portion_weight,
          allergens: item.allergens || [],
          ingredients: item.ingredients || [],
          prep_time: item.prep_time,
          created_at: item.created_at,
        })),
      };
    }

    // ── Build all_restaurants ──
    const allRestaurants = restaurants.map((r: any) => {
      const foods = menuByRestaurant[r.id] || [];
      return buildRestaurant(r, foods);
    });

    // ── Build suggested_restaurants (filtered by time-of-day categories) ──
    const suggestedRestaurants = targetCategories.length > 0
      ? restaurants
          .map((r: any) => {
            const allFoods = menuByRestaurant[r.id] || [];
            const matched = allFoods.filter((item: any) => {
              const cat = (item.category || '').toLowerCase();
              return targetCategories.some((tc) => cat.includes(tc.toLowerCase()));
            });
            return matched.length > 0 ? buildRestaurant(r, matched) : null;
          })
          .filter(Boolean)
      : allRestaurants; // Night time: show all

    // ── Favorite cuisines (from authenticated user's order history) ──
    let favoriteCuisines: string[] = [];
    if (userId) {
      favoriteCuisines = await getFavoriteCuisines(userId);
    }

    res.status(200).json({
      time_of_day: timeOfDay,
      greeting,
      suggested_restaurants: suggestedRestaurants,
      all_restaurants: allRestaurants,
      favorite_cuisines: favoriteCuisines,
    });
  } catch (error) {
    console.error('[HomeSuggestions] Error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

/**
 * Build a friendly greeting string based on the time of day.
 */
function buildGreeting(timeOfDay: string): string {
  switch (timeOfDay) {
    case 'morning':
      return 'Good Morning ☀️';
    case 'afternoon':
      return 'Good Afternoon 🌤️';
    case 'evening':
      return 'Good Evening 🌅';
    case 'night':
      return 'Good Night 🌙';
    default:
      return 'Hello! 👋';
  }
}

/**
 * Query the user's completed orders to determine their most-ordered
 * cuisine types.  Joins via restaurant_applications.cuisine_type.
 *
 * Returns up to 3 unique cuisine types, sorted by frequency descending.
 */
async function getFavoriteCuisines(userId: string): Promise<string[]> {
  try {
    // Fetch the user's delivered orders, joined with restaurant cuisine_type
    const { data: orders, error } = await supabase.admin
      .from('orders')
      .select(`
        restaurant_id,
        restaurant_applications!inner(cuisine_type)
      `)
      .eq('user_id', userId)
      .eq('status', 'DELIVERED')
      .not('restaurant_applications.cuisine_type', 'is', null);

    if (error || !orders || orders.length === 0) {
      return [];
    }

    // Count cuisine frequency
    const counts: Record<string, number> = {};
    for (const order of orders) {
      const cuisineType = (order as any).restaurant_applications?.cuisine_type;
      if (cuisineType && typeof cuisineType === 'string') {
        // Split comma-separated cuisines (e.g. "Italian, Chinese")
        const cuisines = cuisineType.split(',').map((c: string) => c.trim()).filter(Boolean);
        for (const c of cuisines) {
          counts[c] = (counts[c] || 0) + 1;
        }
      }
    }

    // Sort by frequency descending
    return Object.entries(counts)
      .sort((a, b) => b[1] - a[1])
      .slice(0, 3)
      .map(([cuisine]) => cuisine);
  } catch (e) {
    console.error('[HomeSuggestions] getFavoriteCuisines error:', e);
    return [];
  }
}
