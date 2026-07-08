import { Request, Response } from 'express';
import jwt from 'jsonwebtoken';
import { supabase } from '../db/supabase';
import { getUserId } from '../utils/auth';
import { notifyUser } from '../services/fcm.service';

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
// POST /api/problems
// Submit a problem report for an order (customer)
// ──────────────────────────────────────────────
export const submitProblem = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const { order_id, issue_type, description } = req.body;

    if (!order_id || !issue_type) {
      res.status(400).json({ error: 'order_id and issue_type are required.' });
      return;
    }

    const validTypes = ['wrong_item', 'missing_item', 'quality', 'other'];
    if (!validTypes.includes(issue_type)) {
      res.status(400).json({ error: `Invalid issue_type. Must be one of: ${validTypes.join(', ')}` });
      return;
    }

    // Verify the order belongs to this user
    const { data: order, error: orderError } = await supabase.admin
      .from('orders')
      .select('id, restaurant_id, order_number, status')
      .eq('id', order_id)
      .eq('user_id', userId)
      .eq('status', 'DELIVERED')
      .maybeSingle();

    if (orderError || !order) {
      res.status(404).json({ error: 'Order not found or not yet delivered.' });
      return;
    }

    // Check if a problem already exists for this order
    const { data: existing } = await supabase.admin
      .from('order_problems')
      .select('id, status')
      .eq('order_id', order_id)
      .maybeSingle();

    if (existing) {
      res.status(409).json({ error: 'A problem report already exists for this order.', existing });
      return;
    }

    const { data: problem, error } = await supabase.admin
      .from('order_problems')
      .insert({
        order_id,
        user_id: userId,
        issue_type,
        description: description?.trim() || null,
        status: 'PENDING',
        created_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .select()
      .single();

    if (error) {
      console.error('[Problems] Submit error:', error);
      res.status(500).json({ error: 'Failed to submit problem report.' });
      return;
    }

    // Notify the restaurant owner
    const { data: restaurant } = await supabase.admin
      .from('restaurant_applications')
      .select('user_id, restaurant_name')
      .eq('id', order.restaurant_id)
      .maybeSingle();

    if (restaurant?.user_id) {
      const typeLabels: Record<string, string> = {
        wrong_item: 'Wrong Item',
        missing_item: 'Missing Item',
        quality: 'Food Quality',
        other: 'Other Issue',
      };
      notifyUser(restaurant.user_id, supabase.admin, {
        title: 'Problem Reported ⚠️',
        body: `Issue: ${typeLabels[issue_type] || issue_type} — Order #${order.order_number || ''}`,
        data: { type: 'problem_reported', problem_id: problem.id, order_id },
      }).catch(() => {});
    }

    res.status(201).json({
      message: 'Problem reported successfully.',
      problem,
    });
  } catch (error) {
    console.error('[Problems] Submit error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// GET /api/problems/my
// Get problem reports for the authenticated user
// ──────────────────────────────────────────────
export const getMyProblems = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const { data: problems, error } = await supabase.admin
      .from('order_problems')
      .select('*')
      .eq('user_id', userId)
      .order('created_at', { ascending: false });

    if (error) {
      console.error('[Problems] Fetch my problems error:', error);
      res.status(500).json({ error: 'Failed to fetch problems.' });
      return;
    }

    res.status(200).json({ problems: problems || [] });
  } catch (error) {
    console.error('[Problems] Get my problems error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// GET /api/problems/order/:orderId
// Get problem report for a specific order
// ──────────────────────────────────────────────
export const getProblemByOrder = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const { orderId } = req.params;
    const role = getUserRole(req);

    let query = supabase.admin
      .from('order_problems')
      .select('*')
      .eq('order_id', orderId);

    // Non-admin users can only see their own problems
    if (role !== 'ADMIN') {
      query = query.eq('user_id', userId);
    }

    const { data: problem, error } = await query.maybeSingle();

    if (error) {
      console.error('[Problems] Fetch by order error:', error);
      res.status(500).json({ error: 'Failed to fetch problem.' });
      return;
    }

    res.status(200).json({ problem: problem || null });
  } catch (error) {
    console.error('[Problems] Get by order error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// GET /api/problems/restaurant
// Get problems for the authenticated owner's restaurant
// ──────────────────────────────────────────────
export const getRestaurantProblems = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    // Get the owner's restaurant
    const { data: application } = await supabase.admin
      .from('restaurant_applications')
      .select('id, restaurant_name')
      .eq('user_id', userId)
      .eq('status', 'APPROVED')
      .maybeSingle();

    if (!application) {
      res.status(200).json({ problems: [] });
      return;
    }

    // Fetch orders for this restaurant, then get their problem reports
    const { data: orders } = await supabase.admin
      .from('orders')
      .select('id, order_number')
      .eq('restaurant_id', application.id);

    const orderIds = (orders || []).map((o: any) => o.id);
    if (orderIds.length === 0) {
      res.status(200).json({ problems: [] });
      return;
    }

    const { data: problems, error } = await supabase.admin
      .from('order_problems')
      .select('*')
      .in('order_id', orderIds)
      .order('created_at', { ascending: false });

    if (error) {
      console.error('[Problems] Fetch restaurant problems error:', error);
      res.status(500).json({ error: 'Failed to fetch problems.' });
      return;
    }

    // Attach order numbers and customer info
    const orderMap = new Map<string, any>();
    for (const o of orders || []) {
      orderMap.set(o.id, o);
    }

    const userIds = [...new Set((problems || []).map((p: any) => p.user_id))];
    const { data: users } = await supabase.admin
      .from('users')
      .select('id, username')
      .in('id', userIds);

    const userMap = new Map<string, any>();
    for (const u of users || []) {
      userMap.set(u.id, u);
    }

    const problemsWithDetails = (problems || []).map((p: any) => {
      const orderInfo = orderMap.get(p.order_id);
      const userInfo = userMap.get(p.user_id);
      return {
        ...p,
        order_number: orderInfo?.order_number || '',
        customer_name: userInfo?.username || 'Unknown',
        restaurant_name: application.restaurant_name,
      };
    });

    res.status(200).json({ problems: problemsWithDetails });
  } catch (error) {
    console.error('[Problems] Get restaurant problems error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// GET /api/problems/all
// Get all problems (admin only)
// ──────────────────────────────────────────────
export const getAllProblems = async (req: Request, res: Response): Promise<void> => {
  try {
    const role = getUserRole(req);
    if (role !== 'ADMIN') {
      res.status(403).json({ error: 'Admin access required.' });
      return;
    }

    const status = req.query.status as string | undefined;

    let query = supabase.admin
      .from('order_problems')
      .select('*')
      .order('created_at', { ascending: false });

    if (status && ['PENDING', 'APPROVED', 'REJECTED'].includes(status)) {
      query = query.eq('status', status);
    }

    const { data: problems, error } = await query;

    if (error) {
      console.error('[Problems] Fetch all error:', error);
      res.status(500).json({ error: 'Failed to fetch problems.' });
      return;
    }

    if (!problems || problems.length === 0) {
      res.status(200).json({ problems: [] });
      return;
    }

    // Enrich with order and user details
    const orderIds = [...new Set(problems.map((p: any) => p.order_id))];
    const { data: orders } = await supabase.admin
      .from('orders')
      .select('id, order_number, restaurant_id')
      .in('id', orderIds);

    const orderMap = new Map<string, any>();
    for (const o of orders || []) {
      orderMap.set(o.id, o);
    }

    const userIds = [...new Set((problems || []).map((p: any) => p.user_id))];
    const { data: users } = await supabase.admin
      .from('users')
      .select('id, username')
      .in('id', userIds);

    const userMap = new Map<string, any>();
    for (const u of users || []) {
      userMap.set(u.id, u);
    }

    const restaurantIds = [...new Set((orders || []).map((o: any) => o.restaurant_id))];
    const { data: restaurants } = await supabase.admin
      .from('restaurant_applications')
      .select('id, restaurant_name')
      .in('id', restaurantIds);

    const restaurantMap = new Map<string, any>();
    for (const r of restaurants || []) {
      restaurantMap.set(r.id, r);
    }

    const enriched = (problems || []).map((p: any) => {
      const orderInfo = orderMap.get(p.order_id);
      const userInfo = userMap.get(p.user_id);
      const restInfo = orderInfo ? restaurantMap.get(orderInfo.restaurant_id) : null;
      return {
        ...p,
        order_number: orderInfo?.order_number || '',
        customer_name: userInfo?.username || 'Unknown',
        restaurant_name: restInfo?.restaurant_name || '',
      };
    });

    res.status(200).json({ problems: enriched });
  } catch (error) {
    console.error('[Problems] Get all error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// PATCH /api/problems/:id/status
// Update problem status (APPROVED / REJECTED) — owner or admin
// ──────────────────────────────────────────────
export const updateProblemStatus = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const { id } = req.params;
    const { status, admin_note, refund_amount } = req.body;

    if (!status || !['APPROVED', 'REJECTED'].includes(status)) {
      res.status(400).json({ error: 'Status must be APPROVED or REJECTED.' });
      return;
    }

    // Verify the user owns the restaurant related to this problem
    const { data: problem, error: fetchError } = await supabase.admin
      .from('order_problems')
      .select('id, order_id, user_id, issue_type, status')
      .eq('id', id)
      .maybeSingle();

    if (fetchError || !problem) {
      res.status(404).json({ error: 'Problem not found.' });
      return;
    }

    if (problem.status !== 'PENDING') {
      res.status(400).json({ error: `This problem has already been ${problem.status.toLowerCase()}.` });
      return;
    }

    const role = getUserRole(req);

    // Owner verification: check if they own the restaurant for this order
    if (role !== 'ADMIN') {
      const { data: order } = await supabase.admin
        .from('orders')
        .select('restaurant_id')
        .eq('id', problem.order_id)
        .maybeSingle();

      if (!order) {
        res.status(404).json({ error: 'Order not found.' });
        return;
      }

      const { data: application } = await supabase.admin
        .from('restaurant_applications')
        .select('id')
        .eq('id', order.restaurant_id)
        .eq('user_id', userId)
        .maybeSingle();

      if (!application) {
        res.status(403).json({ error: 'You do not own this restaurant.' });
        return;
      }
    }

    const updateData: Record<string, any> = {
      status,
      admin_note: admin_note?.trim() || null,
      refund_amount: refund_amount || null,
      updated_at: new Date().toISOString(),
    };

    const { data: updated, error } = await supabase.admin
      .from('order_problems')
      .update(updateData)
      .eq('id', id)
      .select()
      .single();

    if (error) {
      console.error('[Problems] Update status error:', error);
      res.status(500).json({ error: 'Failed to update problem status.' });
      return;
    }

    // Notify the customer
    const statusEmoji = status === 'APPROVED' ? '✅' : '❌';
    const statusText = status === 'APPROVED' ? 'approved' : 'rejected';
    notifyUser(problem.user_id, supabase.admin, {
      title: `Refund Request ${statusEmoji}`,
      body: `Your refund request has been ${statusText}.${admin_note ? ` Note: ${admin_note}` : ''}`,
      data: {
        type: 'problem_status_update',
        problem_id: id,
        order_id: problem.order_id,
        status,
      },
    }).catch(() => {});

    res.status(200).json({
      message: `Problem ${statusText}.`,
      problem: updated,
    });
  } catch (error) {
    console.error('[Problems] Update status error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};
