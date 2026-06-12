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

function getUserRole(req: Request): string | null {
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) return null;

  try {
    const payload = jwt.verify(authHeader.slice(7), JWT_SECRET) as JwtPayload;
    return payload.role;
  } catch {
    return null;
  }
}

// ──────────────────────────────────────────────
// GET /api/orders/restaurant
// Get all orders for the authenticated owner's restaurant
// ──────────────────────────────────────────────
export const getRestaurantOrders = async (req: Request, res: Response): Promise<void> => {
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

    const restaurantId = application.id;

    // Fetch orders for this restaurant, newest first
    const { data: orders, error } = await supabase.admin
      .from('orders')
      .select('*')
      .eq('restaurant_id', restaurantId)
      .order('created_at', { ascending: false });

    if (error) {
      console.error('Fetch orders error:', error);
      res.status(500).json({ error: 'Failed to fetch orders.' });
      return;
    }

    res.status(200).json({ orders });
  } catch (error) {
    console.error('Get restaurant orders error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// GET /api/orders/:id
// Get a single order by ID
// ──────────────────────────────────────────────
export const getOrderById = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const { id } = req.params;

    const { data: order, error } = await supabase.admin
      .from('orders')
      .select('*')
      .eq('id', id)
      .maybeSingle();

    if (error) {
      console.error('Fetch order error:', error);
      res.status(500).json({ error: 'Failed to fetch order.' });
      return;
    }

    if (!order) {
      res.status(404).json({ error: 'Order not found.' });
      return;
    }

    res.status(200).json({ order });
  } catch (error) {
    console.error('Get order error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// PATCH /api/orders/:id/accept
// Accept a pending order
// ──────────────────────────────────────────────
export const acceptOrder = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const { id } = req.params;
    const { estimated_prep_time } = req.body; // optional prep time in minutes

    // Verify the order exists and belongs to this owner's restaurant
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

    const { data: order } = await supabase.admin
      .from('orders')
      .select('id, status')
      .eq('id', id)
      .eq('restaurant_id', application.id)
      .eq('status', 'PENDING')
      .maybeSingle();

    if (!order) {
      res.status(404).json({ error: 'Order not found or already processed.' });
      return;
    }

    const updateData: Record<string, any> = {
      status: 'ACCEPTED',
      accepted_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    };

    if (estimated_prep_time) {
      updateData.estimated_prep_time = estimated_prep_time;
    }

    const { data: updated, error } = await supabase.admin
      .from('orders')
      .update(updateData)
      .eq('id', id)
      .select()
      .single();

    if (error) {
      console.error('Accept order error:', error);
      res.status(500).json({ error: 'Failed to accept order.' });
      return;
    }

    res.status(200).json({
      message: 'Order accepted successfully.',
      order: updated,
    });
  } catch (error) {
    console.error('Accept order error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// PATCH /api/orders/:id/reject
// Reject a pending order
// ──────────────────────────────────────────────
export const rejectOrder = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const { id } = req.params;
    const { reason } = req.body;

    // Verify the order exists and belongs to this owner's restaurant
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

    const { data: order } = await supabase.admin
      .from('orders')
      .select('id, status')
      .eq('id', id)
      .eq('restaurant_id', application.id)
      .eq('status', 'PENDING')
      .maybeSingle();

    if (!order) {
      res.status(404).json({ error: 'Order not found or already processed.' });
      return;
    }

    const { data: updated, error } = await supabase.admin
      .from('orders')
      .update({
        status: 'REJECTED',
        rejection_reason: reason || null,
        cancelled_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq('id', id)
      .select()
      .single();

    if (error) {
      console.error('Reject order error:', error);
      res.status(500).json({ error: 'Failed to reject order.' });
      return;
    }

    res.status(200).json({
      message: 'Order rejected.',
      order: updated,
    });
  } catch (error) {
    console.error('Reject order error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// PATCH /api/orders/:id/preparing
// Mark an order as being prepared
// ──────────────────────────────────────────────
export const markAsPreparing = async (req: Request, res: Response): Promise<void> => {
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

    const { data: updated, error } = await supabase.admin
      .from('orders')
      .update({
        status: 'PREPARING',
        preparing_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq('id', id)
      .eq('restaurant_id', application.id)
      .in('status', ['ACCEPTED'])
      .select()
      .single();

    if (error || !updated) {
      res.status(404).json({ error: 'Order not found or cannot be marked as preparing.' });
      return;
    }

    res.status(200).json({
      message: 'Order is now being prepared.',
      order: updated,
    });
  } catch (error) {
    console.error('Mark as preparing error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// PATCH /api/orders/:id/ready
// Mark an order as ready for pickup/delivery
// ──────────────────────────────────────────────
export const markAsReady = async (req: Request, res: Response): Promise<void> => {
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

    const { data: updated, error } = await supabase.admin
      .from('orders')
      .update({
        status: 'READY',
        ready_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq('id', id)
      .eq('restaurant_id', application.id)
      .in('status', ['ACCEPTED', 'PREPARING'])
      .select()
      .single();

    if (error || !updated) {
      res.status(404).json({ error: 'Order not found or cannot be marked as ready.' });
      return;
    }

    res.status(200).json({
      message: 'Order is ready!',
      order: updated,
    });
  } catch (error) {
    console.error('Mark as ready error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// GET /api/delivery-boys
// Get all available delivery boys
// ──────────────────────────────────────────────
export const getDeliveryBoys = async (_req: Request, res: Response): Promise<void> => {
  try {
    const { data: drivers, error } = await supabase.admin
      .from('users')
      .select('id, username, email, phone, status')
      .eq('role', 'DELIVERY_BOY')
      .eq('status', 'ACTIVE');

    if (error) {
      console.error('Fetch delivery boys error:', error);
      res.status(500).json({ error: 'Failed to fetch delivery boys.' });
      return;
    }

    res.status(200).json({ delivery_boys: drivers });
  } catch (error) {
    console.error('Get delivery boys error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// PATCH /api/orders/:id/assign
// Assign a delivery boy to an order
// ──────────────────────────────────────────────
export const assignDeliveryBoy = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const { id } = req.params;
    const { delivery_boy_id } = req.body;

    if (!delivery_boy_id) {
      res.status(400).json({ error: 'delivery_boy_id is required.' });
      return;
    }

    // Verify the order exists and belongs to this owner's restaurant
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
      .from('orders')
      .update({
        delivery_boy_id,
        assigned_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq('id', id)
      .eq('restaurant_id', application.id)
      .in('status', ['READY', 'PREPARING'])
      .select()
      .single();

    if (error || !updated) {
      res.status(404).json({ error: 'Order not found or cannot be assigned.' });
      return;
    }

    res.status(200).json({
      message: 'Delivery boy assigned successfully.',
      order: updated,
    });
  } catch (error) {
    console.error('Assign delivery boy error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};
