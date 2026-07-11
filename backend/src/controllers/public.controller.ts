import { Request, Response } from 'express';
import { supabase } from '../db/supabase';

// ──────────────────────────────────────────────
// GET /api/restaurants
// Get all approved restaurants with their basic info (public, no auth needed)
// ──────────────────────────────────────────────
export const getAllRestaurants = async (_req: Request, res: Response): Promise<void> => {
  try {
    const { data: restaurants, error } = await supabase.admin
      .from('restaurants')
      .select('id, name, description, logo_url, cover_image_url, cuisine_type, address, is_accepting_orders, open_time, close_time, rating, delivery_time_minutes')
      .order('name', { ascending: true });

    if (error) {
      console.error('Fetch restaurants error:', error);
      res.status(500).json({ error: 'Failed to fetch restaurants.' });
      return;
    }

    res.status(200).json({ restaurants: restaurants || [] });
  } catch (error) {
    console.error('Get all restaurants error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// GET /api/restaurants/:id/menu
// Get menu items for a specific restaurant (public)
// ──────────────────────────────────────────────
export const getRestaurantMenu = async (req: Request, res: Response): Promise<void> => {
  try {
    const { id } = req.params;

    const { data: items, error } = await supabase.admin
      .from('menu_items')
      .select('*')
      .eq('restaurant_id', id)
      .order('category', { ascending: true })
      .order('created_at', { ascending: true });

    if (error) {
      console.error('Fetch menu error:', error);
      res.status(500).json({ error: 'Failed to fetch menu.' });
      return;
    }

    res.status(200).json({ items: items || [] });
  } catch (error) {
    console.error('Get restaurant menu error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// GET /api/restaurants/:id
// Get a single restaurant by ID (public)
// ──────────────────────────────────────────────
export const getRestaurantById = async (req: Request, res: Response): Promise<void> => {
  try {
    const { id } = req.params;

    const { data: restaurant, error } = await supabase.admin
      .from('restaurants')
      .select('id, name, description, logo_url, cover_image_url, cuisine_type, address, is_accepting_orders, open_time, close_time, rating, delivery_time_minutes')
      .eq('id', id)
      .maybeSingle();

    if (error) {
      console.error('Fetch restaurant error:', error);
      res.status(500).json({ error: 'Failed to fetch restaurant.' });
      return;
    }

    if (!restaurant) {
      res.status(404).json({ error: 'Restaurant not found.' });
      return;
    }

    res.status(200).json({ restaurant });
  } catch (error) {
    console.error('Get restaurant error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};
