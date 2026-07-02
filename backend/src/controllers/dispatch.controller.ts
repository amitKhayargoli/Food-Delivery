import { Request, Response } from 'express';
import { supabase } from '../db/supabase';
import { getUserId } from '../utils/auth';

// ──────────────────────────────────────────────
// POST /api/dispatch/log
// Log a dispatch event (internal use by dispatch service + manual assign)
// ──────────────────────────────────────────────
export const logDispatchEvent = async (req: Request, res: Response): Promise<void> => {
  try {
    const { order_id, rider_id, assigned_by, distance_km, rider_score, response_time_seconds, status } = req.body;

    if (!order_id || !rider_id || !assigned_by || !status) {
      res.status(400).json({ error: 'order_id, rider_id, assigned_by, and status are required.' });
      return;
    }

    const { data, error } = await supabase.admin
      .from('dispatch_log')
      .insert({
        order_id,
        rider_id,
        assigned_by,
        distance_km: distance_km ?? null,
        rider_score: rider_score ?? null,
        response_time_seconds: response_time_seconds ?? null,
        status,
      })
      .select()
      .single();

    if (error) {
      console.error('[DispatchLog] Insert error:', error.message);
      res.status(500).json({ error: 'Failed to log dispatch event.' });
      return;
    }

    res.status(201).json({ log: data });
  } catch (error) {
    console.error('[DispatchLog] Error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// GET /api/dispatch/log/:orderId
// Get dispatch log entries for a specific order
// ──────────────────────────────────────────────
export const getDispatchLogForOrder = async (req: Request, res: Response): Promise<void> => {
  try {
    const { orderId } = req.params;

    const { data, error } = await supabase.admin
      .from('dispatch_log')
      .select('*, users!rider_id(username, phone)')
      .eq('order_id', orderId)
      .order('created_at', { ascending: false });

    if (error) {
      console.error('[DispatchLog] Fetch error:', error.message);
      res.status(500).json({ error: 'Failed to fetch dispatch log.' });
      return;
    }

    res.status(200).json({ logs: data ?? [] });
  } catch (error) {
    console.error('[DispatchLog] Error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// GET /api/dispatch/analytics
// Get dispatch analytics for the authenticated owner's restaurant.
// Returns: avg_dispatch_time_s, avg_arrival_time_s, rider_ratings_summary
// ──────────────────────────────────────────────
export const getDispatchAnalytics = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    // Get the owner's restaurant
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

    const restaurantId = application.id;

    // ── Average dispatch time (READY → assigned_at) ──
    const { data: dispatchedOrders } = await supabase.admin
      .from('orders')
      .select('ready_at, assigned_at')
      .eq('restaurant_id', restaurantId)
      .not('assigned_at', 'is', null)
      .not('ready_at', 'is', null);

    let avgDispatchTimeS = 0;
    if (dispatchedOrders && dispatchedOrders.length > 0) {
      const totalSeconds = dispatchedOrders.reduce((sum, o) => {
        const ready = new Date(o.ready_at).getTime();
        const assigned = new Date(o.assigned_at).getTime();
        return sum + Math.max(0, (assigned - ready) / 1000);
      }, 0);
      avgDispatchTimeS = Math.round(totalSeconds / dispatchedOrders.length);
    }

    // ── Average arrival time (assigned_at → picked_up_at) ──
    const { data: pickedOrders } = await supabase.admin
      .from('orders')
      .select('assigned_at, picked_up_at')
      .eq('restaurant_id', restaurantId)
      .not('assigned_at', 'is', null)
      .not('picked_up_at', 'is', null);

    let avgArrivalTimeS = 0;
    if (pickedOrders && pickedOrders.length > 0) {
      const totalSeconds = pickedOrders.reduce((sum, o) => {
        const assigned = new Date(o.assigned_at).getTime();
        const pickedUp = new Date(o.picked_up_at).getTime();
        return sum + Math.max(0, (pickedUp - assigned) / 1000);
      }, 0);
      avgArrivalTimeS = Math.round(totalSeconds / pickedOrders.length);
    }

    // ── Rider ratings for this restaurant's orders ──
    // Get all order IDs for this restaurant
    const { data: restaurantOrders } = await supabase.admin
      .from('orders')
      .select('id')
      .eq('restaurant_id', restaurantId);

    const orderIds = (restaurantOrders ?? []).map((o: any) => o.id);

    let avgRiderRating = 0;
    let totalRiderRatings = 0;
    if (orderIds.length > 0) {
      const { data: ratings } = await supabase.admin
        .from('rider_ratings')
        .select('rating')
        .in('order_id', orderIds);

      if (ratings && ratings.length > 0) {
        totalRiderRatings = ratings.length;
        avgRiderRating = ratings.reduce((sum, r) => sum + r.rating, 0) / ratings.length;
      }
    }

    res.status(200).json({
      analytics: {
        avg_dispatch_time_s: avgDispatchTimeS,
        avg_arrival_time_s: avgArrivalTimeS,
        avg_rider_rating: Math.round(avgRiderRating * 10) / 10,
        total_rider_ratings: totalRiderRatings,
        total_dispatched: dispatchedOrders?.length ?? 0,
        total_delivered: pickedOrders?.length ?? 0,
      },
    });
  } catch (error) {
    console.error('[DispatchAnalytics] Error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// GET /api/dispatch/admin/riders
// Admin-only: Get all delivery boys with performance stats.
// Returns: list of riders with total deliveries, avg rating, online status
// ──────────────────────────────────────────────
export const getAllRidersWithStats = async (_req: Request, res: Response): Promise<void> => {
  try {
    // Get all DELIVERY_BOY users
    const { data: riders, error: ridersError } = await supabase.admin
      .from('users')
      .select('id, username, email, phone, status, created_at')
      .contains('roles', ['DELIVERY_BOY'])
      .order('created_at', { ascending: false });

    if (ridersError) {
      console.error('[Admin] Fetch riders error:', ridersError.message);
      res.status(500).json({ error: 'Failed to fetch riders.' });
      return;
    }

    if (!riders || riders.length === 0) {
      res.status(200).json({ riders: [] });
      return;
    }

    // Get rider locations (online status)
    const riderIds = riders.map((r: any) => r.id);
    const { data: locations } = await supabase.admin
      .from('rider_locations')
      .select('user_id, is_online, is_on_delivery, last_active_at, latitude, longitude')
      .in('user_id', riderIds);

    const locationMap = new Map<string, any>();
    if (locations) {
      for (const loc of locations) {
        locationMap.set(loc.user_id, loc);
      }
    }

    // Get delivery counts and ratings for each rider
    const { data: orderCounts } = await supabase.admin
      .from('orders')
      .select('delivery_boy_id, id')
      .in('delivery_boy_id', riderIds)
      .eq('status', 'DELIVERED');

    const deliveryCountMap = new Map<string, number>();
    if (orderCounts) {
      for (const o of orderCounts) {
        const id = o.delivery_boy_id;
        deliveryCountMap.set(id, (deliveryCountMap.get(id) ?? 0) + 1);
      }
    }

    // Get ratings for each rider
    const { data: ratings } = await supabase.admin
      .from('rider_ratings')
      .select('rider_id, rating')
      .in('rider_id', riderIds);

    const ratingMap = new Map<string, { sum: number; count: number }>();
    if (ratings) {
      for (const r of ratings) {
        const entry = ratingMap.get(r.rider_id) ?? { sum: 0, count: 0 };
        entry.sum += r.rating;
        entry.count += 1;
        ratingMap.set(r.rider_id, entry);
      }
    }

    // Enrich riders with stats
    const enrichedRiders = riders.map((rider: any) => {
      const loc = locationMap.get(rider.id);
      const deliveryCount = deliveryCountMap.get(rider.id) ?? 0;
      const ratingEntry = ratingMap.get(rider.id);
      const avgRating = ratingEntry ? Math.round((ratingEntry.sum / ratingEntry.count) * 10) / 10 : 0;

      return {
        id: rider.id,
        username: rider.username,
        email: rider.email,
        phone: rider.phone,
        status: rider.status,
        created_at: rider.created_at,
        is_online: loc?.is_online ?? false,
        is_on_delivery: loc?.is_on_delivery ?? false,
        last_active_at: loc?.last_active_at ?? null,
        latitude: loc?.latitude ?? null,
        longitude: loc?.longitude ?? null,
        total_deliveries: deliveryCount,
        average_rating: avgRating,
        total_ratings: ratingEntry?.count ?? 0,
      };
    });

    // Sort: online first, then by total_deliveries desc
    enrichedRiders.sort((a: any, b: any) => {
      if (a.is_online !== b.is_online) return a.is_online ? -1 : 1;
      return b.total_deliveries - a.total_deliveries;
    });

    res.status(200).json({ riders: enrichedRiders });
  } catch (error) {
    console.error('[Admin] Get riders error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// POST /api/dispatch/admin/riders
// Admin-only: Create a new delivery boy account.
// ──────────────────────────────────────────────
export const createRider = async (req: Request, res: Response): Promise<void> => {
  try {
    const { username, email, phone, password } = req.body;

    if (!username || !phone || !password) {
      res.status(400).json({ error: 'username, phone, and password are required.' });
      return;
    }

    // Check if user already exists
    const { data: existing } = await supabase.admin
      .from('users')
      .select('id')
      .or(`username.eq.${username},phone.eq.${phone}`)
      .maybeSingle();

    if (existing) {
      res.status(409).json({ error: 'User with this username or phone already exists.' });
      return;
    }

    // Create the user via Supabase Auth first (to get a hashed password)
    const { data: authUser, error: authError } = await supabase.admin.auth.admin.createUser({
      email: email || `${username}@delivery.dailo.app`,
      password,
      email_confirm: true,
      user_metadata: { username, role: 'DELIVERY_BOY' },
    });

    if (authError || !authUser?.user) {
      console.error('[Admin] Create auth user error:', authError?.message);
      res.status(500).json({ error: 'Failed to create rider account.' });
      return;
    }

    // Insert into public.users table with multi-role support
    const { data: user, error: userError } = await supabase.admin
      .from('users')
      .insert({
        id: authUser.user.id,
        username,
        email: email || null,
        phone,
        role: 'DELIVERY_BOY',
        roles: ['CUSTOMER', 'DELIVERY_BOY'],
        status: 'ACTIVE',
      })
      .select()
      .single();

    if (userError) {
      console.error('[Admin] Insert user error:', userError.message);
      // Rollback the auth user
      await supabase.admin.auth.admin.deleteUser(authUser.user.id);
      res.status(500).json({ error: 'Failed to create rider profile.' });
      return;
    }

    res.status(201).json({
      message: 'Rider created successfully.',
      rider: user,
    });
  } catch (error) {
    console.error('[Admin] Create rider error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// GET /api/dispatch/admin/performance
// Admin-only: Get rider leaderboard by deliveries completed.
// Includes on-time delivery percentage (defined as delivered within 30
// minutes of assignment).
// ──────────────────────────────────────────────
export const getRiderPerformance = async (_req: Request, res: Response): Promise<void> => {
  try {
    // Get all riders with their delivery stats
    const { data: riders } = await supabase.admin
      .from('users')
      .select('id, username, phone')
      .contains('roles', ['DELIVERY_BOY']);

    if (!riders || riders.length === 0) {
      res.status(200).json({ leaderboard: [] });
      return;
    }

    const riderIds = riders.map((r: any) => r.id);

    // Get delivery counts grouped by rider (last 30 days)
    const thirtyDaysAgo = new Date();
    thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);

    const { data: recentOrders } = await supabase.admin
      .from('orders')
      .select('delivery_boy_id, delivered_at, assigned_at')
      .in('delivery_boy_id', riderIds)
      .eq('status', 'DELIVERED')
      .gte('delivered_at', thirtyDaysAgo.toISOString());

    const deliveryCountMap = new Map<string, number>();
    const onTimeCountMap = new Map<string, number>();

    // On-time threshold: 30 minutes in seconds
    const ON_TIME_THRESHOLD_S = 1800;

    if (recentOrders) {
      for (const o of recentOrders) {
        const id = o.delivery_boy_id;

        // Total deliveries count
        deliveryCountMap.set(id, (deliveryCountMap.get(id) ?? 0) + 1);

        // On-time check: assigned_at -> delivered_at <= 30 min
        if (o.assigned_at && o.delivered_at) {
          const assigned = new Date(o.assigned_at).getTime();
          const delivered = new Date(o.delivered_at).getTime();
          const elapsedSeconds = (delivered - assigned) / 1000;
          if (elapsedSeconds >= 0 && elapsedSeconds <= ON_TIME_THRESHOLD_S) {
            onTimeCountMap.set(id, (onTimeCountMap.get(id) ?? 0) + 1);
          }
        }
      }
    }

    // Get average ratings
    const { data: ratings } = await supabase.admin
      .from('rider_ratings')
      .select('rider_id, rating, created_at')
      .in('rider_id', riderIds)
      .gte('created_at', thirtyDaysAgo.toISOString());

    const ratingMap = new Map<string, { sum: number; count: number }>();
    if (ratings) {
      for (const r of ratings) {
        const entry = ratingMap.get(r.rider_id) ?? { sum: 0, count: 0 };
        entry.sum += r.rating;
        entry.count += 1;
        ratingMap.set(r.rider_id, entry);
      }
    }

    // Build leaderboard
    const leaderboard = riders.map((rider: any) => {
      const total = deliveryCountMap.get(rider.id) ?? 0;
      const onTime = onTimeCountMap.get(rider.id) ?? 0;
      const percentage = total > 0 ? Math.round((onTime / total) * 100) : 0;

      return {
        id: rider.id,
        username: rider.username,
        phone: rider.phone,
        total_deliveries: total,
        on_time_deliveries: onTime,
        on_time_percentage: percentage,
        average_rating: ratingMap.has(rider.id)
          ? Math.round((ratingMap.get(rider.id)!.sum / ratingMap.get(rider.id)!.count) * 10) / 10
          : 0,
        total_ratings: ratingMap.get(rider.id)?.count ?? 0,
      };
    });

    // Sort by delivery count descending
    leaderboard.sort((a: any, b: any) => b.total_deliveries - a.total_deliveries);

    res.status(200).json({ leaderboard });
  } catch (error) {
    console.error('[Admin] Performance error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};
