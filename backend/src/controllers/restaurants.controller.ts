import { Request, Response } from 'express';
import { supabase } from '../db/supabase';

// ──────────────────────────────────────────────
// GET /api/restaurants
// Get all approved restaurants with their menu items
// ──────────────────────────────────────────────
export const getRestaurants = async (_req: Request, res: Response): Promise<void> => {
  try {
    // Fetch all approved restaurant applications
    const { data: restaurants, error } = await supabase.admin
      .from('restaurant_applications')
      .select('*')
      .eq('status', 'APPROVED')
      .order('created_at', { ascending: false });

    if (error) {
      console.error('Fetch restaurants error:', error);
      res.status(500).json({ error: 'Failed to fetch restaurants.' });
      return;
    }

    if (!restaurants || restaurants.length === 0) {
      res.status(200).json({ restaurants: [] });
      return;
    }

    // Get all restaurant IDs
    const restaurantIds = restaurants.map((r: any) => r.id);

    // Fetch menu items for all these restaurants
    const { data: menuItems, error: menuError } = await supabase.admin
      .from('menu_items')
      .select('*')
      .in('restaurant_id', restaurantIds)
      .eq('is_available', true)
      .order('name');

    if (menuError) {
      console.error('Fetch menu items error:', menuError);
      // Non-fatal — return restaurants without menu items
    }

    // Group menu items by restaurant_id
    const menuByRestaurant: Record<string, any[]> = {};
    if (menuItems) {
      for (const item of menuItems) {
        const rid = item.restaurant_id;
        if (!menuByRestaurant[rid]) menuByRestaurant[rid] = [];
        menuByRestaurant[rid].push(item);
      }
    }

    // Build the response with a consistent shape
    const result = restaurants.map((r: any) => ({
      id: r.id,
      name: r.restaurant_name,
      description: r.description || '',
      logo_url: r.logo_url || '',
      banner_url: r.cover_image_url || r.logo_url || '',
      rating: (r.average_rating as number) ?? 4.5,
      total_reviews: (r.total_reviews as number) ?? 0,
      delivery_time_minutes: 30, // Default — can be set per restaurant later
      cuisine_type: r.cuisine_type || '',
      open_time: r.open_time || '9:00 AM',
      close_time: r.close_time || '11:00 PM',
      address: r.address || '',
      is_accepting_orders: r.is_accepting_orders !== false,
      foods: (menuByRestaurant[r.id] || []).map((item: any) => ({
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
    }));

    res.status(200).json({ restaurants: result });
  } catch (error) {
    console.error('Get restaurants error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};
