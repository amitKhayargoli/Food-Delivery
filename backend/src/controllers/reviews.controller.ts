import { Request, Response } from 'express';
import { supabase } from '../db/supabase';
import { getUserId } from '../utils/auth';

// ──────────────────────────────────────────────
// Helper: Recalculate & update restaurant stats
// ──────────────────────────────────────────────
async function refreshRestaurantStats(restaurantId: string): Promise<void> {
  const { data: stats } = await supabase.admin
    .from('restaurant_reviews')
    .select('rating')
    .eq('restaurant_id', restaurantId);

  const ratings = (stats ?? []).map((r: any) => r.rating as number);
  const totalReviews = ratings.length;
  const averageRating = totalReviews > 0
    ? Math.round((ratings.reduce((a, b) => a + b, 0) / totalReviews) * 100) / 100
    : 0;

  await supabase.admin
    .from('restaurant_applications')
    .update({
      total_reviews: totalReviews,
      average_rating: averageRating,
    })
    .eq('id', restaurantId);
}

// ──────────────────────────────────────────────
// POST /api/reviews
// Create a review for a restaurant
// ──────────────────────────────────────────────
export const createReview = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const { restaurant_id, rating, comment, images } = req.body;

    if (!restaurant_id || !rating) {
      res.status(400).json({ error: 'restaurant_id and rating are required.' });
      return;
    }

    if (rating < 1 || rating > 5) {
      res.status(400).json({ error: 'Rating must be between 1 and 5.' });
      return;
    }

    // Verify the restaurant exists and is approved
    const { data: restaurant } = await supabase.admin
      .from('restaurant_applications')
      .select('id')
      .eq('id', restaurant_id)
      .eq('status', 'APPROVED')
      .maybeSingle();

    if (!restaurant) {
      res.status(404).json({ error: 'Restaurant not found.' });
      return;
    }

    // Check if user already reviewed this restaurant
    const { data: existing } = await supabase.admin
      .from('restaurant_reviews')
      .select('id')
      .eq('restaurant_id', restaurant_id)
      .eq('user_id', userId)
      .maybeSingle();

    if (existing) {
      res.status(409).json({ error: 'You have already reviewed this restaurant.' });
      return;
    }

    const { data: review, error: insertError } = await supabase.admin
      .from('restaurant_reviews')
      .insert({
        restaurant_id,
        user_id: userId,
        rating,
        comment: comment || null,
        images: images && Array.isArray(images) && images.length > 0 ? images : [],
      })
      .select('*, users!user_id(username, avatar_url)')
      .single();

    if (insertError) {
      console.error('[Reviews] Create error:', insertError.message);
      res.status(500).json({ error: 'Failed to create review.' });
      return;
    }

    // Recalculate restaurant stats
    await refreshRestaurantStats(restaurant_id);

    res.status(201).json({ review });
  } catch (error) {
    console.error('[Reviews] Create error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// GET /api/reviews/restaurant/:restaurantId
// Get all reviews for a restaurant
// ──────────────────────────────────────────────
export const getRestaurantReviews = async (req: Request, res: Response): Promise<void> => {
  try {
    const { restaurantId } = req.params;

    const { data: reviews, error } = await supabase.admin
      .from('restaurant_reviews')
      .select('*, users!user_id(id, username, avatar_url)')
      .eq('restaurant_id', restaurantId)
      .order('created_at', { ascending: false });

    if (error) {
      console.error('[Reviews] Fetch error:', error.message);
      res.status(500).json({ error: 'Failed to fetch reviews.' });
      return;
    }

    res.status(200).json({ reviews: reviews ?? [] });
  } catch (error) {
    console.error('[Reviews] Fetch error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// GET /api/reviews/my
// Get all reviews submitted by the authenticated user
// ──────────────────────────────────────────────
export const getMyReviews = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const { data: reviews, error } = await supabase.admin
      .from('restaurant_reviews')
      .select('*, restaurant_applications!restaurant_id(restaurant_name, logo_url)')
      .eq('user_id', userId)
      .order('created_at', { ascending: false });

    if (error) {
      console.error('[Reviews] Fetch my error:', error.message);
      res.status(500).json({ error: 'Failed to fetch reviews.' });
      return;
    }

    res.status(200).json({ reviews: reviews ?? [] });
  } catch (error) {
    console.error('[Reviews] Fetch my error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// GET /api/reviews/owner
// Get all reviews for the authenticated owner's restaurant
// ──────────────────────────────────────────────
export const getOwnerReviews = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    // Find the owner's restaurant
    const { data: application } = await supabase.admin
      .from('restaurant_applications')
      .select('id, restaurant_name')
      .eq('user_id', userId)
      .eq('status', 'APPROVED')
      .maybeSingle();

    if (!application) {
      res.status(404).json({ error: 'No approved restaurant found.' });
      return;
    }

    const { data: reviews, error } = await supabase.admin
      .from('restaurant_reviews')
      .select('*, users!user_id(id, username, avatar_url)')
      .eq('restaurant_id', application.id)
      .order('created_at', { ascending: false });

    if (error) {
      console.error('[Reviews] Owner fetch error:', error.message);
      res.status(500).json({ error: 'Failed to fetch reviews.' });
      return;
    }

    res.status(200).json({
      restaurant_name: application.restaurant_name,
      restaurant_id: application.id,
      reviews: reviews ?? [],
    });
  } catch (error) {
    console.error('[Reviews] Owner fetch error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// PUT /api/reviews/:reviewId
// Update a review (only the author can update)
// ──────────────────────────────────────────────
export const updateReview = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const { reviewId } = req.params;
    const { rating, comment, images } = req.body;

    // Fetch existing review to verify ownership
    const { data: existing } = await supabase.admin
      .from('restaurant_reviews')
      .select('id, user_id, restaurant_id')
      .eq('id', reviewId)
      .maybeSingle();

    if (!existing) {
      res.status(404).json({ error: 'Review not found.' });
      return;
    }

    if (existing.user_id !== userId) {
      res.status(403).json({ error: 'Unauthorized to update this review.' });
      return;
    }

    if (rating !== undefined && (rating < 1 || rating > 5)) {
      res.status(400).json({ error: 'Rating must be between 1 and 5.' });
      return;
    }

    const updateData: Record<string, any> = {};
    if (rating !== undefined) updateData.rating = rating;
    if (comment !== undefined) updateData.comment = comment;
    if (images !== undefined) updateData.images = images;

    const { data: review, error: updateError } = await supabase.admin
      .from('restaurant_reviews')
      .update(updateData)
      .eq('id', reviewId)
      .select('*, users!user_id(username, avatar_url)')
      .single();

    if (updateError) {
      console.error('[Reviews] Update error:', updateError.message);
      res.status(500).json({ error: 'Failed to update review.' });
      return;
    }

    await refreshRestaurantStats(existing.restaurant_id);

    res.status(200).json({ review });
  } catch (error) {
    console.error('[Reviews] Update error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// DELETE /api/reviews/:reviewId
// Delete a review (author only)
// ──────────────────────────────────────────────
export const deleteReview = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const { reviewId } = req.params;

    const { data: existing } = await supabase.admin
      .from('restaurant_reviews')
      .select('id, user_id, restaurant_id')
      .eq('id', reviewId)
      .maybeSingle();

    if (!existing) {
      res.status(404).json({ error: 'Review not found.' });
      return;
    }

    if (existing.user_id !== userId) {
      res.status(403).json({ error: 'Unauthorized to delete this review.' });
      return;
    }

    const { error: deleteError } = await supabase.admin
      .from('restaurant_reviews')
      .delete()
      .eq('id', reviewId);

    if (deleteError) {
      console.error('[Reviews] Delete error:', deleteError.message);
      res.status(500).json({ error: 'Failed to delete review.' });
      return;
    }

    await refreshRestaurantStats(existing.restaurant_id);

    res.status(200).json({ message: 'Review deleted successfully.' });
  } catch (error) {
    console.error('[Reviews] Delete error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// DELETE /api/reviews/admin/:reviewId
// Admin-only: delete any review
// ──────────────────────────────────────────────
export const adminDeleteReview = async (req: Request, res: Response): Promise<void> => {
  try {
    const { reviewId } = req.params;

    const { data: existing } = await supabase.admin
      .from('restaurant_reviews')
      .select('id, restaurant_id')
      .eq('id', reviewId)
      .maybeSingle();

    if (!existing) {
      res.status(404).json({ error: 'Review not found.' });
      return;
    }

    const { error: deleteError } = await supabase.admin
      .from('restaurant_reviews')
      .delete()
      .eq('id', reviewId);

    if (deleteError) {
      console.error('[Reviews] Admin delete error:', deleteError.message);
      res.status(500).json({ error: 'Failed to delete review.' });
      return;
    }

    await refreshRestaurantStats(existing.restaurant_id);

    res.status(200).json({ message: 'Review deleted successfully.' });
  } catch (error) {
    console.error('[Reviews] Admin delete error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};
