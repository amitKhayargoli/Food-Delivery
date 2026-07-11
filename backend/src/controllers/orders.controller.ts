import { Request, Response } from 'express';
import jwt from 'jsonwebtoken';
import { supabase } from '../db/supabase';
import { getUserId } from '../utils/auth';
import { autoAssignRider } from '../services/dispatch.service';
import { notifyUser } from '../services/fcm.service';

/**
 * Batch-fetch restaurant names for a set of restaurant IDs from
 * the restaurant_applications table and return a Map<id, name>.
 */
async function getRestaurantNames(restaurantIds: string[]): Promise<Map<string, string>> {
  const uniqueIds = [...new Set(restaurantIds)];
  if (uniqueIds.length === 0) return new Map();

  const { data: apps, error } = await supabase.admin
    .from('restaurant_applications')
    .select('id, restaurant_name')
    .in('id', uniqueIds);

  if (error || !apps) {
    console.error('Fetch restaurant names error:', error);
    return new Map();
  }

  const map = new Map<string, string>();
  for (const app of apps) {
    map.set(app.id, app.restaurant_name);
  }
  return map;
}

/**
 * Batch-fetch delivery boy info (username + avatar_url + phone) for a set
 * of user IDs from the users table and return a Map<id, info>.
 */
async function getRiderInfo(riderIds: string[]): Promise<Map<string, { username: string; avatar_url: string | null; phone: string | null }>> {
  const uniqueIds = [...new Set(riderIds.filter(Boolean))];
  if (uniqueIds.length === 0) return new Map();

  const { data: users, error } = await supabase.admin
    .from('users')
    .select('id, username, avatar_url, phone')
    .in('id', uniqueIds);

  if (error || !users) {
    console.error('Fetch rider info error:', error);
    return new Map();
  }

  const map = new Map<string, { username: string; avatar_url: string | null; phone: string | null }>();
  for (const u of users) {
    map.set(u.id, {
      username: u.username || 'Rider',
      avatar_url: u.avatar_url || null,
      phone: u.phone || null,
    });
  }
  return map;
}

/**
 * Batch-fetch delivery boy usernames for a set of user IDs from
 * the users table and return a Map<id, username>.
 */
async function getRiderNames(riderIds: string[]): Promise<Map<string, string>> {
  const infoMap = await getRiderInfo(riderIds);
  const map = new Map<string, string>();
  for (const [id, info] of infoMap) {
    map.set(id, info.username);
  }
  return map;
}

/**
 * Batch-fetch customer info (username + phone) for a set of user IDs
 * from the users table and return a Map<id, info>.
 */
async function getCustomerInfo(customerIds: string[]): Promise<Map<string, { username: string; phone: string | null }>> {
  const uniqueIds = [...new Set(customerIds.filter(Boolean))];
  if (uniqueIds.length === 0) return new Map();

  const { data: users, error } = await supabase.admin
    .from('users')
    .select('id, username, phone')
    .in('id', uniqueIds);

  if (error || !users) {
    console.error('Fetch customer info error:', error);
    return new Map();
  }

  const map = new Map<string, { username: string; phone: string | null }>();
  for (const u of users) {
    map.set(u.id, {
      username: u.username || 'Customer',
      phone: u.phone || null,
    });
  }
  return map;
}

const JWT_SECRET = process.env.JWT_SECRET || 'supersecretkey';

function getUserRole(req: Request): string | null {
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) return null;

  try {
    const payload = jwt.verify(authHeader.slice(7), JWT_SECRET) as { id: string; role: string };
    return payload.role;
  } catch {
    return null;
  }
}

// ──────────────────────────────────────────────
// POST /api/orders
// Create a new order (customer checkout)
// ──────────────────────────────────────────────
export const createOrder = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const {
      restaurant_id,
      items,
      subtotal,
      delivery_fee,
      total,
      delivery_address,
      delivery_notes,
      payment_method,
    } = req.body;

    // Validate required fields
    if (!restaurant_id || !items || !items.length) {
      res.status(400).json({ error: 'restaurant_id and items are required.' });
      return;
    }

    // Generate a unique order number
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    const orderNumber = `#DAILO-${chars[Math.floor(Math.random() * chars.length)]}${Math.floor(Math.random() * 10)}${Math.floor(Math.random() * 10)}${Math.floor(Math.random() * 10)}${Math.floor(Math.random() * 10)}`;

    const now = new Date().toISOString();

    // Insert the order
    const { data: order, error: orderError } = await supabase.admin
      .from('orders')
      .insert({
        user_id: userId,
        restaurant_id,
        order_number: orderNumber,
        status: 'CREATED',
        subtotal: subtotal || 0,
        delivery_fee: delivery_fee || 0,
        total: total || 0,
        delivery_address: delivery_address ? JSON.stringify(delivery_address) : null,
        delivery_notes: delivery_notes || null,
        payment_method: payment_method || 'COD',
        created_at: now,
        updated_at: now,
      })
      .select()
      .single();

    if (orderError) {
      console.error('Create order error:', orderError);
      res.status(500).json({ error: 'Failed to create order.' });
      return;
    }

    // Insert order items
    const orderItems = items.map((item: any) => ({
      order_id: order.id,
      food_id: item.food_id || item.foodId,
      name: item.name,
      unit_price: item.price,
      qty: item.quantity,
      image_url: item.image_url || item.imageUrl || null,
      special_instructions: item.special_instructions || item.specialInstructions || null,
    }));

    const { error: itemsError } = await supabase.admin
      .from('order_items')
      .insert(orderItems);

    if (itemsError) {
      console.error('Create order items error:', itemsError);
      // Order was created but items failed — still return the order
      // The frontend can handle this gracefully
    }

    // Fetch the order with items
    const { data: fullOrder } = await supabase.admin
      .from('orders')
      .select('*')
      .eq('id', order.id)
      .single();

    // Also fetch the items
    const { data: orderItemsData } = await supabase.admin
      .from('order_items')
      .select('*')
      .eq('order_id', order.id);

    // ── Notify restaurant owner: "New order received!" ──
    // Fire-and-forget — don't block the response
    (async () => {
      try {
        const { data: app } = await supabase.admin
          .from('restaurant_applications')
          .select('user_id, restaurant_name')
          .eq('id', restaurant_id)
          .maybeSingle();

        if (app?.user_id) {
          // Fetch customer name for the notification body
          const { data: customer } = await supabase.admin
            .from('users')
            .select('username')
            .eq('id', userId)
            .maybeSingle();

          const customerName = customer?.username || 'A customer';

          notifyUser(app.user_id, supabase.admin, {
            title: 'New Order Received! 🆕',
            body: `${customerName} placed a new order (${orderNumber}). Check your dashboard!`,
            data: { type: 'order_update', order_id: order.id, status: 'CREATED' },
          });
        }
      } catch (notifError) {
        console.error('[FCM] New-order notification failed:', notifError);
      }
    })();

    res.status(201).json({
      message: 'Order created successfully.',
      order: {
        ...fullOrder,
        items: orderItemsData || [],
      },
    });
  } catch (error) {
    console.error('Create order error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// GET /api/orders/restaurant
// Get all orders for the authenticated owner's restaurant
// ──────────────────────────────────────────────
export const getRestaurantOrders = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
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

    if (!orders || orders.length === 0) {
      res.status(200).json({ orders: [] });
      return;
    }

    // Fetch order_items for all returned orders (single query, avoid N+1)
    const orderIds = orders.map((o: any) => o.id);
    const { data: allItems, error: itemsError } = await supabase.admin
      .from('order_items')
      .select('*')
      .in('order_id', orderIds);

    if (itemsError) {
      console.error('Fetch order items error:', itemsError);
    }

    // Batch-fetch restaurant names
    const restaurantIds = orders.map((o: any) => o.restaurant_id);
    const restaurantNames = await getRestaurantNames(restaurantIds);

    // Batch-fetch rider info for orders that have delivery_boy_id set
    const riderIds = orders
      .map((o: any) => o.delivery_boy_id)
      .filter(Boolean) as string[];
    const riderInfo = await getRiderInfo(riderIds);

    // Attach items, restaurant_name, and delivery_boy info (incl. phone) to each order
    const ordersWithDetails = orders.map((order: any) => {
      const info = riderInfo.get(order.delivery_boy_id);
      return {
        ...order,
        items: (allItems || []).filter(
          (item: any) => item.order_id === order.id,
        ),
        restaurant_name: restaurantNames.get(order.restaurant_id) || '',
        delivery_boy_name: info?.username || null,
        delivery_boy_avatar_url: info?.avatar_url || null,
        delivery_boy_phone: info?.phone || null,
      };
    });

    res.status(200).json({ orders: ordersWithDetails });
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
    const userId = await getUserId(req);
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

    // Fetch order_items for this order
    const { data: items, error: itemsError } = await supabase.admin
      .from('order_items')
      .select('*')
      .eq('order_id', id);

    if (itemsError) {
      console.error('Fetch order items error:', itemsError);
    }

    // Fetch restaurant name
    const names = await getRestaurantNames([order.restaurant_id]);
    const restaurantName = names.get(order.restaurant_id) || '';

    // Fetch rider info (includes phone) if assigned
    let deliveryBoyName: string | null = null;
    let deliveryBoyAvatarUrl: string | null = null;
    let deliveryBoyPhone: string | null = null;
    if (order.delivery_boy_id) {
      const riderInfoMap = await getRiderInfo([order.delivery_boy_id]);
      const info = riderInfoMap.get(order.delivery_boy_id);
      deliveryBoyName = info?.username || null;
      deliveryBoyAvatarUrl = info?.avatar_url || null;
      deliveryBoyPhone = info?.phone || null;
    }

    res.status(200).json({
      order: {
        ...order,
        items: items || [],
        restaurant_name: restaurantName,
        delivery_boy_name: deliveryBoyName,
        delivery_boy_avatar_url: deliveryBoyAvatarUrl,
        delivery_boy_phone: deliveryBoyPhone,
      },
    });
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
    const userId = await getUserId(req);
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
      .eq('status', 'CREATED')
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

    // ── Notify customer: "Your order has been accepted!" ──
    if (updated?.user_id) {
      notifyUser(updated.user_id, supabase.admin, {
        title: 'Order Accepted! ✅',
        body: 'Your order has been accepted by the restaurant and is being prepared.',
        data: { type: 'order_update', order_id: id, status: 'ACCEPTED' },
      }).catch((err: any) =>
        console.error('[FCM] Accepted notification failed:', err?.message),
      );
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
    const userId = await getUserId(req);
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
      .eq('status', 'CREATED')
      .maybeSingle();

    if (!order) {
      res.status(404).json({ error: 'Order not found or already processed.' });
      return;
    }

    const { data: updated, error } = await supabase.admin
      .from('orders')
      .update({
        status: 'CANCELLED',
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

    // ── Notify customer: "Your order has been rejected" ──
    if (updated?.user_id) {
      notifyUser(updated.user_id, supabase.admin, {
        title: 'Order Rejected ❌',
        body: reason
          ? `The restaurant could not accept your order: ${reason}`
          : 'The restaurant could not accept your order.',
        data: { type: 'order_update', order_id: id, status: 'CANCELLED' },
      }).catch((err: any) =>
        console.error('[FCM] Rejection notification failed:', err?.message),
      );
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
    const userId = await getUserId(req);
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

    // ── Notify customer: "Your order is being prepared!" ──
    if (updated?.user_id) {
      notifyUser(updated.user_id, supabase.admin, {
        title: 'Preparing Your Order 🍳',
        body: 'The restaurant is now preparing your order!',
        data: { type: 'order_update', order_id: id, status: 'PREPARING' },
      }).catch((err: any) =>
        console.error('[FCM] Preparing notification failed:', err?.message),
      );
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
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const { id } = req.params;

    const { data: application } = await supabase.admin
      .from('restaurant_applications')
      .select('id, auto_dispatch_enabled')
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
        status: 'OUT_FOR_DELIVERY',
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

    // ── Auto-dispatch: if enabled, find and assign nearest rider ──
    if (application.auto_dispatch_enabled) {
      // Fire-and-forget — don't block the response
      autoAssignRider(updated.id, application.id).then((result) => {
        if (result.assigned) {
          console.log(
            `[Dispatch] ✅ Auto-assigned ${result.riderName} to order ${updated.id}`,
          );
        } else {
          console.warn(
            `[Dispatch] ⚠️ Auto-assign failed for order ${updated.id}: ${result.reason}`,
          );
        }
      });
    }

    // ── Notify customer: "Your order is ready for delivery!" ──
    if (updated?.user_id) {
      notifyUser(updated.user_id, supabase.admin, {
        title: 'Order Out for Delivery 🛵',
        body: 'Your order is on its way! A rider will be picking it up shortly.',
        data: { type: 'order_update', order_id: id, status: 'OUT_FOR_DELIVERY' },
      }).catch((err: any) =>
        console.error('[FCM] Ready notification failed:', err?.message),
      );
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
// GET /api/orders/my
// Get orders for the authenticated user (customer)
// ──────────────────────────────────────────────
export const getMyOrders = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const { data: orders, error } = await supabase.admin
      .from('orders')
      .select('*')
      .eq('user_id', userId)
      .order('created_at', { ascending: false });

    if (error) {
      console.error('Fetch my orders error:', error);
      res.status(500).json({ error: 'Failed to fetch orders.' });
      return;
    }

    if (!orders || orders.length === 0) {
      res.status(200).json({ orders: [] });
      return;
    }

    // Fetch order_items for all returned orders (single query, avoid N+1)
    const orderIds = orders.map((o: any) => o.id);
    const { data: allItems, error: itemsError } = await supabase.admin
      .from('order_items')
      .select('*')
      .in('order_id', orderIds);

    if (itemsError) {
      console.error('Fetch order items error:', itemsError);
    }

    // Batch-fetch restaurant names
    const restaurantIds = orders.map((o: any) => o.restaurant_id);
    const restaurantNames = await getRestaurantNames(restaurantIds);

    // Batch-fetch rider info (includes phone)
    const riderIds = orders
      .map((o: any) => o.delivery_boy_id)
      .filter(Boolean) as string[];
    const riderInfo = await getRiderInfo(riderIds);

    // Batch-fetch customer info (for delivery boy to call customer)
    const customerIds = orders
      .map((o: any) => o.user_id)
      .filter(Boolean) as string[];
    const customerInfo = await getCustomerInfo(customerIds);

    // Attach items, restaurant_name, delivery_boy info, and customer info
    const ordersWithDetails = orders.map((order: any) => {
      const info = riderInfo.get(order.delivery_boy_id);
      const cust = customerInfo.get(order.user_id);
      return {
        ...order,
        items: (allItems || []).filter(
          (item: any) => item.order_id === order.id,
        ),
        restaurant_name: restaurantNames.get(order.restaurant_id) || '',
        delivery_boy_name: info?.username || null,
        delivery_boy_avatar_url: info?.avatar_url || null,
        delivery_boy_phone: info?.phone || null,
        customer_name: cust?.username || null,
        customer_phone: cust?.phone || null,
      };
    });

    res.status(200).json({ orders: ordersWithDetails });
  } catch (error) {
    console.error('Get my orders error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// GET /api/orders/search?q=<order_number>
// Search orders by order number for the owner's restaurant
// ──────────────────────────────────────────────
export const searchOrders = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const query = (req.query.q as string || '').trim();
    if (!query) {
      res.status(400).json({ error: 'Search query "q" is required.' });
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

    const { data: orders, error } = await supabase.admin
      .from('orders')
      .select('*')
      .eq('restaurant_id', restaurantId)
      .ilike('order_number', `%${query}%`)
      .order('created_at', { ascending: false })
      .limit(10);

    if (error) {
      console.error('Search orders error:', error);
      res.status(500).json({ error: 'Failed to search orders.' });
      return;
    }

    res.status(200).json({ orders });
  } catch (error) {
    console.error('Search orders error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// GET /api/orders/delivery/my
// Get assigned orders for the authenticated delivery boy
// ──────────────────────────────────────────────
export const getMyDeliveryJobs = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const { data: orders, error } = await supabase.admin
      .from('orders')
      .select('*')
      .eq('delivery_boy_id', userId)
      .not('status', 'in', '(DELIVERED,CANCELLED)')
      .order('created_at', { ascending: false });

    if (error) {
      console.error('Fetch delivery jobs error:', error);
      res.status(500).json({ error: 'Failed to fetch delivery jobs.' });
      return;
    }

    // Fetch restaurant names for each order
    const restaurantIds = orders.map((o: any) => o.restaurant_id);
    const restaurantNames = await getRestaurantNames(restaurantIds);

    // Fetch customer info (name + phone) so the delivery boy can call them
    const customerIds = orders
      .map((o: any) => o.user_id)
      .filter(Boolean) as string[];
    const customerInfo = await getCustomerInfo(customerIds);

    // Attach restaurant_name and customer info to each order
    const ordersWithDetails = orders.map((order: any) => {
      const cust = customerInfo.get(order.user_id);
      return {
        ...order,
        restaurant_name: restaurantNames.get(order.restaurant_id) || '',
        customer_name: cust?.username || null,
        customer_phone: cust?.phone || null,
      };
    });

    res.status(200).json({ orders: ordersWithDetails });
  } catch (error) {
    console.error('Get delivery jobs error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// GET /api/orders/delivery-boys
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
// PATCH /api/orders/:id/picked-up
// Mark an order as picked up (by delivery boy)
// ──────────────────────────────────────────────
export const markAsPickedUp = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const { id } = req.params;

    const { data: updated, error } = await supabase.admin
      .from('orders')
      .update({
        status: 'PICKED_UP',
        picked_up_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq('id', id)
      .eq('delivery_boy_id', userId)
      .in('status', ['OUT_FOR_DELIVERY'])
      .select()
      .single();

    if (error || !updated) {
      res.status(404).json({ error: 'Order not found or cannot be picked up.' });
      return;
    }

    // ── Notify customer: "Your order has been picked up!" ──
    notifyUser(updated.user_id, supabase.admin, {
      title: 'Order Picked Up! 🛵',
      body: 'Your rider has picked up your order and is on the way!',
      data: { type: 'order_update', order_id: id, status: 'PICKED_UP' },
    }).catch((err: any) =>
      console.error('[FCM] Picked-up notification failed:', err?.message),
    );

    res.status(200).json({
      message: 'Order picked up successfully.',
      order: updated,
    });
  } catch (error) {
    console.error('Mark as picked up error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// PATCH /api/orders/:id/assign
// Assign a delivery boy to an order
// ──────────────────────────────────────────────
export const assignDeliveryBoy = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
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
      .in('status', ['OUT_FOR_DELIVERY', 'PREPARING'])
      .select()
      .single();

    if (error || !updated) {
      res.status(404).json({ error: 'Order not found or cannot be assigned.' });
      return;
    }

    // ── Notify customer: "A rider has been assigned!" ──
    (async () => {
      try {
        const { data: riderData } = await supabase.admin
          .from('users')
          .select('username')
          .eq('id', delivery_boy_id)
          .maybeSingle();

        const riderName = riderData?.username || 'A rider';

        if (updated?.user_id) {
          notifyUser(updated.user_id, supabase.admin, {
            title: 'Rider Assigned! 🛵',
            body: `${riderName} has been assigned to your order and is on the way!`,
            data: { type: 'order_update', order_id: id, status: 'OUT_FOR_DELIVERY' },
          });
        }
      } catch (notifError) {
        console.error('[FCM] Assign delivery notification failed:', notifError);
      }
    })();

    res.status(200).json({
      message: 'Delivery boy assigned successfully.',
      order: updated,
    });
  } catch (error) {
    console.error('Assign delivery boy error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// GET /api/orders/history
// Get completed/cancelled order history for the authenticated customer
// ──────────────────────────────────────────────
export const getOrderHistory = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const limit = Math.min(Math.max(parseInt(req.query.limit as string) || 20, 1), 50);
    const offset = Math.max(parseInt(req.query.offset as string) || 0, 0);

    // Terminal statuses — exclude active ones (PENDING, ACCEPTED, PREPARING, READY, PICKED_UP)
    // Note: REJECTED maps to CANCELLED in the DB enum — rejection_reason stores the detail
    const terminalStatuses = ['DELIVERED', 'CANCELLED'];

    const { data: orders, error, count } = await supabase.admin
      .from('orders')
      .select('*', { count: 'exact' })
      .eq('user_id', userId)
      .in('status', terminalStatuses)
      .order('created_at', { ascending: false })
      .range(offset, offset + limit - 1);

    if (error) {
      console.error('Fetch order history error:', error);
      res.status(500).json({ error: 'Failed to fetch order history.' });
      return;
    }

    res.status(200).json({ orders, total: count ?? orders?.length ?? 0 });
  } catch (error) {
    console.error('Get order history error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// PATCH /api/orders/:id/deliver
// Mark an order as delivered (by delivery boy)
// Captures GPS snapshot + optional delivery photo as proof.
// Releases rider's is_on_delivery flag so they can accept new jobs.
// ──────────────────────────────────────────────
export const markAsDelivered = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const { id } = req.params;
    const { delivery_photo_url, delivery_lat, delivery_lng } = req.body;

    // Build update payload
    const updatePayload: Record<string, any> = {
      status: 'DELIVERED',
      delivered_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    };
    if (delivery_photo_url) updatePayload.delivery_photo_url = delivery_photo_url;
    if (delivery_lat != null) updatePayload.delivery_lat = delivery_lat;
    if (delivery_lng != null) updatePayload.delivery_lng = delivery_lng;

    // Update order to DELIVERED
    const { data: updated, error } = await supabase.admin
      .from('orders')
      .update(updatePayload)
      .eq('id', id)
      .eq('delivery_boy_id', userId)
      .in('status', ['PICKED_UP', 'OUT_FOR_DELIVERY'])
      .select()
      .single();

    if (error || !updated) {
      res.status(404).json({ error: 'Order not found or cannot be marked as delivered.' });
      return;
    }

    // Release rider — set is_on_delivery = false so they can accept new jobs
    const { error: releaseError } = await supabase.admin
      .from('rider_locations')
      .update({
        is_on_delivery: false,
        updated_at: new Date().toISOString(),
      })
      .eq('user_id', userId)
      .eq('is_on_delivery', true);

    if (releaseError) {
      console.error('[Deliver] Release rider error:', releaseError.message);
      // Non-fatal — order is still delivered
    }

    // ── Notify customer: "Your order has been delivered!" ──
    notifyUser(updated.user_id, supabase.admin, {
      title: 'Order Delivered! 🎉',
      body: 'Your order has been delivered. Enjoy your meal!',
      data: { type: 'order_update', order_id: id, status: 'DELIVERED' },
    }).catch((err: any) =>
      console.error('[FCM] Delivered notification failed:', err?.message),
    );

    res.status(200).json({
      message: 'Order delivered successfully!',
      order: updated,
    });
  } catch (error) {
    console.error('Mark as delivered error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// GET /api/orders/delivery/stats
// Get delivery earnings summary for the authenticated rider.
// Returns: total deliveries today, total distance, estimated earnings.
// ──────────────────────────────────────────────
export const getRiderStats = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    // Today's date range
    const todayStart = new Date();
    todayStart.setHours(0, 0, 0, 0);
    const todayEnd = new Date();
    todayEnd.setHours(23, 59, 59, 999);

    // Fetch today's delivered orders
    const { data: todayDeliveries, error } = await supabase.admin
      .from('orders')
      .select('total, delivery_fee, delivery_boy_id')
      .eq('delivery_boy_id', userId)
      .eq('status', 'DELIVERED')
      .gte('delivered_at', todayStart.toISOString())
      .lte('delivered_at', todayEnd.toISOString());

    if (error) {
      console.error('Fetch rider stats error:', error.message);
      res.status(500).json({ error: 'Failed to fetch rider stats.' });
      return;
    }

    const totalDeliveries = todayDeliveries?.length ?? 0;
    const totalEarnings = (todayDeliveries ?? []).reduce(
      (sum, o) => sum + ((o.delivery_fee as number) || 0),
      0,
    );

    // Total distance — estimate 3km per delivery on average (no per-order tracking yet)
    const estimatedDistance = totalDeliveries * 3.0;

    res.status(200).json({
      stats: {
        total_deliveries: totalDeliveries,
        total_earnings: totalEarnings,
        estimated_distance_km: estimatedDistance,
      },
    });
  } catch (error) {
    console.error('Get rider stats error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// PATCH /api/orders/:id/decline
// Rider declines an assigned order.
// Resets is_on_delivery, clears assignment, logs to dispatch_log,
// and sends a push notification to the restaurant owner.
// ──────────────────────────────────────────────
export const declineOrder = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const { id } = req.params;

    // Verify the rider is assigned to this order
    const { data: order, error: orderError } = await supabase.admin
      .from('orders')
      .select('id, delivery_boy_id, restaurant_id, order_number, assigned_by')
      .eq('id', id)
      .eq('delivery_boy_id', userId)
      .in('status', ['OUT_FOR_DELIVERY'])
      .maybeSingle();

    if (orderError || !order) {
      res.status(404).json({ error: 'Order not found or you are not assigned to it.' });
      return;
    }

    // Reset the order — clear delivery boy assignment
    const { error: updateError } = await supabase.admin
      .from('orders')
      .update({
        delivery_boy_id: null,
        assigned_at: null,
        assigned_by: null,
        updated_at: new Date().toISOString(),
      })
      .eq('id', id);

    if (updateError) {
      console.error('[Decline] Update order error:', updateError.message);
      res.status(500).json({ error: 'Failed to decline order.' });
      return;
    }

    // Reset rider's is_on_delivery flag
    const { error: releaseError } = await supabase.admin
      .from('rider_locations')
      .update({
        is_on_delivery: false,
        updated_at: new Date().toISOString(),
      })
      .eq('user_id', userId)
      .eq('is_on_delivery', true);

    if (releaseError) {
      console.error('[Decline] Release rider error:', releaseError.message);
      // Non-fatal
    }

    // Log the decline in dispatch_log (fire-and-forget)
    (async () => {
      const { error: logError } = await supabase.admin
        .from('dispatch_log')
        .insert({
          order_id: id,
          rider_id: userId,
          assigned_by: order.assigned_by || 'OWNER',
          status: 'DECLINED',
        });
      if (logError) {
        console.error('[Decline] Log error:', logError.message);
      }
    })();

    // Send push notification to the restaurant owner
    const { data: restaurant } = await supabase.admin
      .from('restaurant_applications')
      .select('user_id, restaurant_name')
      .eq('id', order.restaurant_id)
      .maybeSingle();

    if (restaurant?.user_id) {
      // Fetch rider name for the notification
      const { data: riderData } = await supabase.admin
        .from('users')
        .select('username')
        .eq('id', userId)
        .maybeSingle();

      const riderName = riderData?.username || 'A rider';

      notifyUser(restaurant.user_id, supabase.admin, {
        title: 'Rider Declined Delivery 🚫',
        body: `${riderName} declined order ${order.order_number || ''}. Please reassign manually.`,
        data: {
          type: 'rider_declined',
          order_id: id,
          rider_id: userId,
          restaurant_id: order.restaurant_id,
        },
      }).catch((err: any) =>
        console.error('[Decline] Owner notification failed:', err?.message),
      );
    }

    res.status(200).json({
      message: 'Order declined. Assignment has been cleared.',
    });
  } catch (error) {
    console.error('[Decline] Error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// PATCH /api/orders/:id/cancel
// Customer cancels their own order.
// If a rider is assigned, releases the rider and sends them a push
// notification. Also notifies the restaurant owner.
// ──────────────────────────────────────────────
export const cancelOrder = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const { id } = req.params;

    // Verify the order belongs to this customer and is cancellable
    // Only allow cancellation before the rider has picked up the order
    const { data: order, error: orderError } = await supabase.admin
      .from('orders')
      .select('id, order_number, user_id, delivery_boy_id, restaurant_id, status, assigned_by')
      .eq('id', id)
      .eq('user_id', userId)
      .in('status', ['CREATED', 'ACCEPTED', 'PREPARING', 'OUT_FOR_DELIVERY'])
      .maybeSingle();

    if (orderError || !order) {
      res.status(404).json({ error: 'Order not found or already completed.' });
      return;
    }

    // Set order to CANCELLED
    const { error: updateError } = await supabase.admin
      .from('orders')
      .update({
        status: 'CANCELLED',
        cancelled_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq('id', id);

    if (updateError) {
      console.error('[CancelOrder] Update error:', updateError.message);
      res.status(500).json({ error: 'Failed to cancel order.' });
      return;
    }

    // ── If a rider was assigned, release them ──
    const riderId = order.delivery_boy_id;
    if (riderId) {
      // Release rider's is_on_delivery flag
      const { error: releaseError } = await supabase.admin
        .from('rider_locations')
        .update({
          is_on_delivery: false,
          updated_at: new Date().toISOString(),
        })
        .eq('user_id', riderId)
        .eq('is_on_delivery', true);

      if (releaseError) {
        console.error('[CancelOrder] Release rider error:', releaseError.message);
        // Non-fatal — order is still cancelled
      }

      // Fetch rider name for the notification
      const { data: riderData } = await supabase.admin
        .from('users')
        .select('username')
        .eq('id', riderId)
        .maybeSingle();

      const riderName = riderData?.username || 'Rider';

      // Send push notification to the rider
      notifyUser(riderId, supabase.admin, {
        title: 'Order Cancelled ❌',
        body: `Order ${order.order_number || ''} was cancelled by the customer. This delivery has been removed.`,
        data: {
          type: 'order_cancelled',
          order_id: id,
          rider_id: riderId,
        },
      }).catch((err: any) =>
        console.error('[CancelOrder] Rider notification failed:', err?.message),
      );

      // Log to dispatch_log for audit trail
      (async () => {
        const { error: logError } = await supabase.admin
          .from('dispatch_log')
          .insert({
            order_id: id,
            rider_id: riderId,
            assigned_by: order.assigned_by || 'SYSTEM',
            status: 'CANCELLED',
          });
        if (logError) {
          console.error('[CancelOrder] Log error:', logError.message);
        }
      })();

      console.log(
        `[CancelOrder] Released rider ${riderId.slice(0, 8)} from cancelled order ${id.slice(0, 8)}`,
      );
    }

    // ── Notify the restaurant owner ──
    const { data: restaurant } = await supabase.admin
      .from('restaurant_applications')
      .select('user_id, restaurant_name')
      .eq('id', order.restaurant_id)
      .maybeSingle();

    if (restaurant?.user_id) {
      notifyUser(restaurant.user_id, supabase.admin, {
        title: 'Order Cancelled by Customer ❌',
        body: `Order ${order.order_number || ''} was cancelled by the customer.`,
        data: {
          type: 'order_cancelled',
          order_id: id,
          customer_id: userId,
        },
      }).catch((err: any) =>
        console.error('[CancelOrder] Owner notification failed:', err?.message),
      );
    }

    res.status(200).json({
      message: 'Order cancelled successfully.',
    });
  } catch (error) {
    console.error('[CancelOrder] Error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// GET /api/orders/admin/all
// Get all orders (admin only). Returns delivered orders with
// restaurant names, rider info, and delivery photo status.
// Used for dispute resolution in the admin panel.
// ──────────────────────────────────────────────
export const getAllOrders = async (req: Request, res: Response): Promise<void> => {
  try {
    const role = getUserRole(req);
    if (role !== 'ADMIN') {
      res.status(403).json({ error: 'Admin access required.' });
      return;
    }

    const limit = Math.min(Math.max(parseInt(req.query.limit as string) || 50, 1), 200);
    const offset = Math.max(parseInt(req.query.offset as string) || 0, 0);

    // Fetch all delivered orders
    const { data: orders, error } = await supabase.admin
      .from('orders')
      .select('*')
      .eq('status', 'DELIVERED')
      .order('delivered_at', { ascending: false })
      .range(offset, offset + limit - 1);

    if (error) {
      console.error('Fetch all orders error:', error);
      res.status(500).json({ error: 'Failed to fetch orders.' });
      return;
    }

    if (!orders || orders.length === 0) {
      res.status(200).json({ orders: [] });
      return;
    }

    // Fetch order_items
    const orderIds = orders.map((o: any) => o.id);
    const { data: allItems, error: itemsError } = await supabase.admin
      .from('order_items')
      .select('*')
      .in('order_id', orderIds);

    if (itemsError) {
      console.error('Fetch order items error:', itemsError);
    }

    // Fetch restaurant names
    const restaurantIds = orders.map((o: any) => o.restaurant_id);
    const restaurantNames = await getRestaurantNames(restaurantIds);

    // Fetch rider info
    const riderIds = orders
      .map((o: any) => o.delivery_boy_id)
      .filter(Boolean) as string[];
    const riderInfo = await getRiderInfo(riderIds);

    // Attach details
    const ordersWithDetails = orders.map((order: any) => {
      const info = riderInfo.get(order.delivery_boy_id);
      return {
        ...order,
        items: (allItems || []).filter(
          (item: any) => item.order_id === order.id,
        ),
        restaurant_name: restaurantNames.get(order.restaurant_id) || '',
        delivery_boy_name: info?.username || null,
        delivery_boy_avatar_url: info?.avatar_url || null,
      };
    });

    res.status(200).json({ orders: ordersWithDetails });
  } catch (error) {
    console.error('Get all orders error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// PATCH /api/orders/:id/rider-note
// Add a rider note to an order (delivery boy -> customer)
// ──────────────────────────────────────────────
export const addRiderNote = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const { id } = req.params;
    const { rider_note } = req.body;

    if (!rider_note || rider_note.toString().trim().length === 0) {
      res.status(400).json({ error: 'rider_note is required.' });
      return;
    }

    // Verify the delivery boy is assigned to this order
    const { data: order } = await supabase.admin
      .from('orders')
      .select('id, delivery_boy_id, user_id')
      .eq('id', id)
      .eq('delivery_boy_id', userId)
      .maybeSingle();

    if (!order) {
      res.status(403).json({ error: 'You are not assigned to this order.' });
      return;
    }

    const { data: updated, error } = await supabase.admin
      .from('orders')
      .update({
        rider_note: rider_note.toString().trim(),
        updated_at: new Date().toISOString(),
      })
      .eq('id', id)
      .select('id, rider_note')
      .single();

    if (error) {
      console.error('Add rider note error:', error);
      res.status(500).json({ error: 'Failed to add rider note.' });
      return;
    }

    // ── Notify customer: "Rider added a note!" ──
    if (order?.user_id) {
      notifyUser(order.user_id, supabase.admin, {
        title: 'Message from Your Rider 💬',
        body: rider_note.toString().trim(),
        data: { type: 'order_update', order_id: id, status: 'NOTE' },
      }).catch((err: any) =>
        console.error('[FCM] Rider note notification failed:', err?.message),
      );
    }

    res.status(200).json({
      message: 'Rider note added.',
      rider_note: updated.rider_note,
    });
  } catch (error) {
    console.error('Add rider note error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

