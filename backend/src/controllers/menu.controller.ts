import { Request, Response } from 'express';
import jwt from 'jsonwebtoken';
import { supabase } from '../db/supabase';

const JWT_SECRET = process.env.JWT_SECRET || 'supersecretkey';

interface JwtPayload {
  id: string;
  role: string;
}

function getUserId(req: Request): string | null {
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) return null;

  try {
    const payload = jwt.verify(authHeader.slice(7), JWT_SECRET) as JwtPayload;
    return payload.id;
  } catch {
    return null;
  }
}

// ──────────────────────────────────────────────
// GET /api/menu
// Get all menu items for the authenticated owner's restaurant
// ──────────────────────────────────────────────
export const getMenuItems = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    // Get the owner's restaurant application ID
    const { data: application } = await supabase.admin
      .from('restaurant_applications')
      .select('id')
      .eq('user_id', userId)
      .eq('status', 'APPROVED')
      .limit(1)
      .maybeSingle();

    if (!application) {
      res.status(404).json({ error: 'No approved restaurant found for this user.' });
      return;
    }

    const { data: items, error } = await supabase.admin
      .from('menu_items')
      .select('*')
      .eq('restaurant_id', application.id)
      .order('created_at', { ascending: false });

    if (error) {
      console.error('Fetch menu items error:', error);
      res.status(500).json({ error: 'Failed to fetch menu items.' });
      return;
    }

    res.status(200).json({ items });
  } catch (error) {
    console.error('Get menu items error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// GET /api/menu/:id
// Get a single menu item by ID
// ──────────────────────────────────────────────
export const getMenuItemById = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const { id } = req.params;

    const { data: item, error } = await supabase.admin
      .from('menu_items')
      .select('*')
      .eq('id', id)
      .maybeSingle();

    if (error) {
      res.status(500).json({ error: 'Failed to fetch menu item.' });
      return;
    }

    if (!item) {
      res.status(404).json({ error: 'Menu item not found.' });
      return;
    }

    res.status(200).json({ item });
  } catch (error) {
    console.error('Get menu item error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// POST /api/menu
// Create a new menu item
// ──────────────────────────────────────────────
export const createMenuItem = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const { data: application } = await supabase.admin
      .from('restaurant_applications')
      .select('id')
      .eq('user_id', userId)
      .eq('status', 'APPROVED')
      .limit(1)
      .maybeSingle();

    if (!application) {
      res.status(404).json({ error: 'No approved restaurant found.' });
      return;
    }

    const {
      name,
      description,
      base_price,
      category,
      is_available,
      images,
      calories,
      portion_weight,
      allergens,
      ingredients,
      sizes,
      prep_time,
    } = req.body;

    if (!name || !name.trim()) {
      res.status(400).json({ error: 'Item name is required.' });
      return;
    }

    const { data: item, error } = await supabase.admin
      .from('menu_items')
      .insert({
        restaurant_id: application.id,
        name: name.trim(),
        description: description || null,
        base_price: base_price ?? 0,
        category: category || null,
        is_available: is_available ?? true,
        images: images || [],
        calories: calories || null,
        portion_weight: portion_weight || null,
        allergens: allergens || [],
        ingredients: ingredients || [],
        sizes: sizes || [],
        prep_time: prep_time || null,
      })
      .select()
      .single();

    if (error) {
      console.error('Create menu item error:', error);
      res.status(500).json({ error: 'Failed to create menu item.' });
      return;
    }

    res.status(201).json({
      message: 'Menu item created successfully.',
      item,
    });
  } catch (error) {
    console.error('Create menu item error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// PUT /api/menu/:id
// Update an existing menu item
// ──────────────────────────────────────────────
export const updateMenuItem = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const { id } = req.params;

    // Verify ownership
    const { data: application } = await supabase.admin
      .from('restaurant_applications')
      .select('id')
      .eq('user_id', userId)
      .eq('status', 'APPROVED')
      .limit(1)
      .maybeSingle();

    if (!application) {
      res.status(404).json({ error: 'No approved restaurant found.' });
      return;
    }

    const { data: existing } = await supabase.admin
      .from('menu_items')
      .select('id')
      .eq('id', id)
      .eq('restaurant_id', application.id)
      .maybeSingle();

    if (!existing) {
      res.status(404).json({ error: 'Menu item not found or not owned by you.' });
      return;
    }

    const allowedFields = [
      'name', 'description', 'base_price', 'category', 'is_available',
      'images', 'calories', 'portion_weight', 'allergens', 'ingredients',
      'sizes', 'prep_time',
    ];

    const updates: Record<string, any> = {};
    for (const field of allowedFields) {
      if (req.body[field] !== undefined) {
        updates[field] = req.body[field];
      }
    }
    updates.updated_at = new Date().toISOString();

    const { data: updated, error } = await supabase.admin
      .from('menu_items')
      .update(updates)
      .eq('id', id)
      .select()
      .single();

    if (error) {
      console.error('Update menu item error:', error);
      res.status(500).json({ error: 'Failed to update menu item.' });
      return;
    }

    res.status(200).json({
      message: 'Menu item updated successfully.',
      item: updated,
    });
  } catch (error) {
    console.error('Update menu item error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// DELETE /api/menu/:id
// Delete a menu item
// ──────────────────────────────────────────────
export const deleteMenuItem = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const { id } = req.params;

    const { data: application } = await supabase.admin
      .from('restaurant_applications')
      .select('id')
      .eq('user_id', userId)
      .eq('status', 'APPROVED')
      .limit(1)
      .maybeSingle();

    if (!application) {
      res.status(404).json({ error: 'No approved restaurant found.' });
      return;
    }

    const { error } = await supabase.admin
      .from('menu_items')
      .delete()
      .eq('id', id)
      .eq('restaurant_id', application.id);

    if (error) {
      console.error('Delete menu item error:', error);
      res.status(500).json({ error: 'Failed to delete menu item.' });
      return;
    }

    res.status(200).json({ message: 'Menu item deleted successfully.' });
  } catch (error) {
    console.error('Delete menu item error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// PATCH /api/menu/:id/availability
// Toggle item availability
// ──────────────────────────────────────────────
export const toggleAvailability = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const { id } = req.params;
    const { is_available } = req.body;

    if (typeof is_available !== 'boolean') {
      res.status(400).json({ error: 'is_available must be a boolean.' });
      return;
    }

    const { data: application } = await supabase.admin
      .from('restaurant_applications')
      .select('id')
      .eq('user_id', userId)
      .eq('status', 'APPROVED')
      .limit(1)
      .maybeSingle();

    if (!application) {
      res.status(404).json({ error: 'No approved restaurant found.' });
      return;
    }

    const { data: updated, error } = await supabase.admin
      .from('menu_items')
      .update({
        is_available,
        updated_at: new Date().toISOString(),
      })
      .eq('id', id)
      .eq('restaurant_id', application.id)
      .select()
      .single();

    if (error || !updated) {
      res.status(404).json({ error: 'Menu item not found.' });
      return;
    }

    res.status(200).json({
      message: is_available ? 'Item is now available.' : 'Item is now unavailable.',
      item: updated,
    });
  } catch (error) {
    console.error('Toggle availability error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};
