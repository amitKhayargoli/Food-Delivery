import { Request, Response } from 'express';
import { supabase } from '../db/supabase';
import { getUserId } from '../utils/auth';

// ──────────────────────────────────────────────
// POST /api/coupons/validate
// Validate a coupon code and return discount info
// Body: { code: string, order_total: number, restaurant_id?: string }
// ──────────────────────────────────────────────
export const validateCoupon = async (req: Request, res: Response): Promise<void> => {
  try {
    const { code, order_total, restaurant_id } = req.body;

    if (!code || !order_total) {
      res.status(400).json({ error: 'code and order_total are required.' });
      return;
    }

    const normalizedCode = (code as string).trim().toUpperCase();

    // Fetch the coupon
    const { data: coupon, error } = await supabase.admin
      .from('coupons')
      .select('*')
      .eq('code', normalizedCode)
      .maybeSingle();

    if (error) {
      console.error('[Coupons] Fetch error:', error);
      res.status(500).json({ error: 'Failed to validate coupon.' });
      return;
    }

    if (!coupon) {
      res.status(404).json({ error: 'Invalid coupon code.', valid: false });
      return;
    }

    // ── Validation checks ──

    // Active
    if (!coupon.is_active) {
      res.status(400).json({ error: 'This coupon is no longer active.', valid: false });
      return;
    }

    // Expiry
    if (coupon.expires_at && new Date(coupon.expires_at) < new Date()) {
      res.status(400).json({ error: 'This coupon has expired.', valid: false });
      return;
    }

    // Usage limit
    if (coupon.usage_limit && coupon.used_count >= coupon.usage_limit) {
      res.status(400).json({ error: 'This coupon has reached its usage limit.', valid: false });
      return;
    }

    // Restaurant-specific coupon: must match the order's restaurant
    if (coupon.restaurant_id && restaurant_id && coupon.restaurant_id !== restaurant_id) {
      res.status(400).json({ error: 'This coupon is not valid for this restaurant.', valid: false });
      return;
    }

    // Minimum order amount
    const orderTotal = order_total as number;
    if (coupon.min_order_amount && orderTotal < coupon.min_order_amount) {
      res.status(400).json({
        error: `Minimum order amount of Rs. ${coupon.min_order_amount} required.`,
        valid: false,
        min_order_amount: coupon.min_order_amount,
      });
      return;
    }

    // ── Calculate discount ──
    let discountAmount = 0;
    if (coupon.discount_type === 'PERCENTAGE') {
      discountAmount = (orderTotal * coupon.discount_value) / 100;
      // Apply max discount cap if set
      if (coupon.max_discount_cap && discountAmount > coupon.max_discount_cap) {
        discountAmount = coupon.max_discount_cap;
      }
    } else {
      // FIXED
      discountAmount = coupon.discount_value;
      // Fixed discount can't exceed order total
      if (discountAmount > orderTotal) {
        discountAmount = orderTotal;
      }
    }

    res.status(200).json({
      valid: true,
      coupon: {
        id: coupon.id,
        code: coupon.code,
        discount_type: coupon.discount_type,
        discount_value: coupon.discount_value,
        discount_amount: discountAmount,
        max_discount_cap: coupon.max_discount_cap,
        description: coupon.description,
      },
    });
  } catch (error) {
    console.error('[Coupons] Validate error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// POST /api/coupons
// Create a new coupon (owner for their restaurant, or admin for global)
// ──────────────────────────────────────────────
export const createCoupon = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const {
      code,
      discount_type,
      discount_value,
      min_order_amount,
      max_discount_cap,
      usage_limit,
      expires_at,
      description,
      restaurant_id,
    } = req.body;

    // Validation
    if (!code || !code.trim()) {
      res.status(400).json({ error: 'Coupon code is required.' });
      return;
    }
    if (!discount_type || !['PERCENTAGE', 'FIXED'].includes(discount_type)) {
      res.status(400).json({ error: 'discount_type must be PERCENTAGE or FIXED.' });
      return;
    }
    if (!discount_value || discount_value <= 0) {
      res.status(400).json({ error: 'discount_value must be greater than 0.' });
      return;
    }

    // Check role: restaurant owners can only create coupons for their restaurant
    // Admins can create global coupons (restaurant_id = null) or any restaurant's
    const { data: user } = await supabase.admin
      .from('users')
      .select('role')
      .eq('id', userId)
      .single();

    const isAdmin = user?.role === 'ADMIN';
    const normalizedCode = code.trim().toUpperCase();

    // If not admin, resolve restaurant_id from the owner's application
    let targetRestaurantId = restaurant_id || null;
    if (!isAdmin) {
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
      targetRestaurantId = application.id;
    }

    // Check for duplicate code
    const { data: existing } = await supabase.admin
      .from('coupons')
      .select('id')
      .eq('code', normalizedCode)
      .maybeSingle();

    if (existing) {
      res.status(409).json({ error: 'A coupon with this code already exists.' });
      return;
    }

    const { data: coupon, error } = await supabase.admin
      .from('coupons')
      .insert({
        code: normalizedCode,
        discount_type,
        discount_value,
        min_order_amount: min_order_amount || null,
        max_discount_cap: max_discount_cap || null,
        usage_limit: usage_limit || null,
        expires_at: expires_at || null,
        description: description || null,
        restaurant_id: targetRestaurantId,
        created_by: userId,
      })
      .select()
      .single();

    if (error) {
      console.error('[Coupons] Create error:', error);
      res.status(500).json({ error: 'Failed to create coupon.' });
      return;
    }

    res.status(201).json({
      message: 'Coupon created successfully.',
      coupon,
    });
  } catch (error) {
    console.error('[Coupons] Create error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// GET /api/coupons/my
// Get coupons for the authenticated owner's restaurant
// Admins see all coupons
// ──────────────────────────────────────────────
export const getMyCoupons = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const { data: user } = await supabase.admin
      .from('users')
      .select('role')
      .eq('id', userId)
      .single();

    const isAdmin = user?.role === 'ADMIN';

    let query = supabase.admin
      .from('coupons')
      .select('*')
      .order('created_at', { ascending: false });

    if (isAdmin) {
      // Admins see all coupons
    } else {
      // Owners see their restaurant's coupons + global coupons
      const { data: application } = await supabase.admin
        .from('restaurant_applications')
        .select('id')
        .eq('user_id', userId)
        .eq('status', 'APPROVED')
        .limit(1)
        .maybeSingle();

      if (!application) {
        res.status(200).json({ coupons: [] });
        return;
      }
      query = query.or(`restaurant_id.eq.${application.id},restaurant_id.is.null`);
    }

    const { data: coupons, error } = await query;

    if (error) {
      console.error('[Coupons] Fetch error:', error);
      res.status(500).json({ error: 'Failed to fetch coupons.' });
      return;
    }

    res.status(200).json({ coupons: coupons || [] });
  } catch (error) {
    console.error('[Coupons] Fetch error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// GET /api/coupons/available
// Fetch active coupons for a customer's cart — returns coupons scoped to
// the given restaurant_id + global coupons that are active & non-expired.
// Query: ?restaurant_id=xxx
// ──────────────────────────────────────────────
export const getAvailableCoupons = async (req: Request, res: Response): Promise<void> => {
  try {
    const { restaurant_id } = req.query;

    if (!restaurant_id) {
      res.status(400).json({ error: 'restaurant_id query parameter is required.' });
      return;
    }

    const now = new Date().toISOString();

    let query = supabase.admin
      .from('coupons')
      .select('*')
      .eq('is_active', true)
      .or(`restaurant_id.eq.${restaurant_id},restaurant_id.is.null`)
      .filter('expires_at', 'gte', now)
      .filter('used_count', 'lt', supabase.admin.rpc('coalesce', { x: 'usage_limit', y: 1000000 }));

    // Simpler alternative without RPC: fetch then filter
    const { data: coupons, error } = await supabase.admin
      .from('coupons')
      .select('*')
      .eq('is_active', true)
      .or(`restaurant_id.eq.${restaurant_id},restaurant_id.is.null`)
      .order('created_at', { ascending: false });

    if (error) {
      console.error('[Coupons] Available fetch error:', error);
      res.status(500).json({ error: 'Failed to fetch available coupons.' });
      return;
    }

    const nowDate = new Date();
    const available = (coupons || []).filter((c) => {
      // Not expired
      if (c.expires_at && new Date(c.expires_at) < nowDate) return false;
      // Not at usage limit
      if (c.usage_limit && c.used_count >= c.usage_limit) return false;
      return true;
    });

    // Return simplified fields for display
    const result = available.map((c) => ({
      id: c.id,
      code: c.code,
      discount_type: c.discount_type,
      discount_value: c.discount_value,
      description: c.description,
      min_order_amount: c.min_order_amount,
      max_discount_cap: c.max_discount_cap,
      expires_at: c.expires_at,
    }));

    res.status(200).json({ coupons: result });
  } catch (error) {
    console.error('[Coupons] Available error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// DELETE /api/coupons/:id
// Delete a coupon (owner or admin)
// ──────────────────────────────────────────────
export const deleteCoupon = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const { id } = req.params;

    // Verify ownership or admin
    const { data: user } = await supabase.admin
      .from('users')
      .select('role')
      .eq('id', userId)
      .single();

    const isAdmin = user?.role === 'ADMIN';

    let query = supabase.admin.from('coupons').delete().eq('id', id);

    if (!isAdmin) {
      // Owners can only delete coupons belonging to their restaurant
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
      query = query.eq('restaurant_id', application.id);
    }

    const { error } = await query;

    if (error) {
      console.error('[Coupons] Delete error:', error);
      res.status(500).json({ error: 'Failed to delete coupon.' });
      return;
    }

    res.status(200).json({ message: 'Coupon deleted successfully.' });
  } catch (error) {
    console.error('[Coupons] Delete error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// POST /api/coupons/:id/apply
// Increment the used_count for a coupon
// This is called after a successful order placement
// ──────────────────────────────────────────────
export const applyCoupon = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const { id } = req.params;

    const { data: coupon, error: fetchError } = await supabase.admin
      .from('coupons')
      .select('id, used_count, usage_limit')
      .eq('id', id)
      .single();

    if (fetchError || !coupon) {
      res.status(404).json({ error: 'Coupon not found.' });
      return;
    }

    // Check limit
    if (coupon.usage_limit && coupon.used_count >= coupon.usage_limit) {
      res.status(400).json({ error: 'Coupon usage limit reached.' });
      return;
    }

    const { error: updateError } = await supabase.admin
      .from('coupons')
      .update({
        used_count: (coupon.used_count || 0) + 1,
        updated_at: new Date().toISOString(),
      })
      .eq('id', id);

    if (updateError) {
      console.error('[Coupons] Apply error:', updateError);
      res.status(500).json({ error: 'Failed to apply coupon.' });
      return;
    }

    res.status(200).json({ message: 'Coupon applied successfully.' });
  } catch (error) {
    console.error('[Coupons] Apply error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};
