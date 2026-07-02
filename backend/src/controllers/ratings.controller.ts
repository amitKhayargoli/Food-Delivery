import { Request, Response } from 'express';
import { supabase } from '../db/supabase';
import { getUserId } from '../utils/auth';

// ──────────────────────────────────────────────
// POST /api/ratings
// Submit a rating for a rider after delivery.
// ──────────────────────────────────────────────
export const submitRating = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const { order_id, rider_id, rating, comment } = req.body;

    if (!order_id || !rider_id || !rating) {
      res.status(400).json({ error: 'order_id, rider_id, and rating are required.' });
      return;
    }

    if (rating < 1 || rating > 5) {
      res.status(400).json({ error: 'Rating must be between 1 and 5.' });
      return;
    }

    // Verify the order belongs to this user and is delivered
    const { data: order, error: orderError } = await supabase.admin
      .from('orders')
      .select('id, status, delivery_boy_id')
      .eq('id', order_id)
      .eq('user_id', userId)
      .eq('status', 'DELIVERED')
      .single();

    if (orderError || !order) {
      res.status(404).json({ error: 'Order not found or not yet delivered.' });
      return;
    }

    // Verify the rider_id matches the assigned delivery boy
    if (order.delivery_boy_id !== rider_id) {
      res.status(400).json({ error: 'Rider ID does not match the assigned delivery boy.' });
      return;
    }

    // Insert the rating (unique constraint on order_id prevents duplicates)
    const { data: ratingData, error: insertError } = await supabase.admin
      .from('rider_ratings')
      .insert({
        order_id,
        rider_id,
        user_id: userId,
        rating,
        comment: comment || null,
      })
      .select()
      .single();

    if (insertError) {
      // Handle duplicate rating
      if (insertError.code === '23505') {
        res.status(409).json({ error: 'You have already rated this delivery.' });
        return;
      }
      console.error('Submit rating error:', insertError);
      res.status(500).json({ error: 'Failed to submit rating.' });
      return;
    }

    res.status(201).json({
      message: 'Rating submitted successfully.',
      rating: ratingData,
    });
  } catch (error) {
    console.error('Submit rating error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// GET /api/ratings/rider/:riderId
// Get average rating for a specific rider.
// ──────────────────────────────────────────────
export const getRiderRating = async (req: Request, res: Response): Promise<void> => {
  try {
    const { riderId } = req.params;

    const { data, error } = await supabase.admin
      .from('rider_ratings')
      .select('rating')
      .eq('rider_id', riderId);

    if (error) {
      console.error('Fetch rider ratings error:', error);
      res.status(500).json({ error: 'Failed to fetch ratings.' });
      return;
    }

    const ratings = (data ?? []).map((r: any) => r.rating as number);
    const average = ratings.length > 0
      ? ratings.reduce((a, b) => a + b, 0) / ratings.length
      : 0;

    res.status(200).json({
      rider_id: riderId,
      average_rating: Math.round(average * 10) / 10,
      total_ratings: ratings.length,
    });
  } catch (error) {
    console.error('Get rider rating error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// GET /api/ratings/my
// Get all ratings submitted by the authenticated user.
// ──────────────────────────────────────────────
export const getMyRatings = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const { data, error } = await supabase.admin
      .from('rider_ratings')
      .select('*')
      .eq('user_id', userId)
      .order('created_at', { ascending: false });

    if (error) {
      console.error('Fetch my ratings error:', error);
      res.status(500).json({ error: 'Failed to fetch ratings.' });
      return;
    }

    res.status(200).json({ ratings: data ?? [] });
  } catch (error) {
    console.error('Get my ratings error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};
