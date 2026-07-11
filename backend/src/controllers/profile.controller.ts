import { Request, Response } from 'express';
import jwt from 'jsonwebtoken';
import { supabase } from '../db/supabase';
import { getUserId } from '../utils/auth';

const JWT_SECRET = process.env.JWT_SECRET || 'supersecretkey';

interface JwtPayload {
  id: string;
  role: string;
}

// ──────────────────────────────────────────────
// PATCH  /api/profile/avatar
// Update the user's avatar URL in the users table.
// Expects: { avatar_url: string }
// ──────────────────────────────────────────────

export const updateAvatar = async (
  req: Request,
  res: Response,
): Promise<void> => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader?.startsWith('Bearer ')) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    let userId: string;
    try {
      const payload = jwt.verify(authHeader.slice(7), JWT_SECRET) as JwtPayload;
      userId = payload.id;
    } catch {
      res.status(401).json({ error: 'Invalid or expired token' });
      return;
    }

    const { avatar_url } = req.body;
    if (!avatar_url || typeof avatar_url !== 'string') {
      res.status(400).json({ error: 'avatar_url is required' });
      return;
    }

    const { error } = await supabase.admin
      .from('users')
      .update({ avatar_url, updated_at: new Date().toISOString() })
      .eq('id', userId);

    if (error) {
      console.error('[profile] updateAvatar error:', error);
      res.status(500).json({ error: 'Failed to update avatar' });
      return;
    }

    res.status(200).json({
      message: 'Avatar updated successfully',
      avatar_url,
    });
  } catch (error) {
    console.error('[profile] updateAvatar error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// GET  /api/profile/delivery-location
// ──────────────────────────────────────────────

export const getDeliveryLocation = async (
  req: Request,
  res: Response,
): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }

    const { data, error } = await supabase.admin
      .from('users')
      .select('delivery_location')
      .eq('id', userId)
      .limit(1)
      .maybeSingle();

    if (error) {
      console.error('[profile] getDeliveryLocation error:', error);
      res.status(500).json({ error: 'Failed to fetch delivery location' });
      return;
    }

    res.status(200).json({
      delivery_location: data?.delivery_location ?? null,
    });
  } catch (error) {
    console.error('[profile] getDeliveryLocation error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// PATCH  /api/profile
// Update the user's username, email, and/or phone.
// Expects: { username?: string, email?: string, phone?: string }
// ──────────────────────────────────────────────

export const updateProfile = async (
  req: Request,
  res: Response,
): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const { username, email, phone } = req.body;
    const updates: Record<string, any> = { updated_at: new Date().toISOString() };

    if (username !== undefined) {
      if (typeof username !== 'string' || username.trim().length < 2) {
        res.status(400).json({ error: 'Username must be at least 2 characters.' });
        return;
      }
      updates.username = username.trim();
    }

    if (email !== undefined) {
      if (typeof email !== 'string' || !email.includes('@') || !email.includes('.')) {
        res.status(400).json({ error: 'Please provide a valid email address.' });
        return;
      }
      updates.email = email.trim().toLowerCase();
    }

    if (phone !== undefined) {
      if (typeof phone !== 'string' || phone.trim().length < 7) {
        res.status(400).json({ error: 'Invalid phone number.' });
        return;
      }
      updates.phone = phone.trim();
    }

    if (Object.keys(updates).length <= 1) {
      res.status(400).json({ error: 'No fields to update.' });
      return;
    }

    const { data, error } = await supabase.admin
      .from('users')
      .update(updates)
      .eq('id', userId)
      .select('id, username, email, phone')
      .single();

    if (error) {
      console.error('[profile] updateProfile error:', error);
      res.status(500).json({ error: 'Failed to update profile.' });
      return;
    }

    res.status(200).json({
      message: 'Profile updated successfully',
      user: {
        id: data.id,
        username: data.username,
        email: data.email,
        phone: data.phone,
      },
    });
  } catch (error) {
    console.error('[profile] updateProfile error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// PATCH  /api/profile/delivery-location
// ──────────────────────────────────────────────

export const updateDeliveryLocation = async (
  req: Request,
  res: Response,
): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Unauthorized' });
      return;
    }

    const { address, latitude, longitude } = req.body;

    if (!address || latitude == null || longitude == null) {
      res.status(400).json({ error: 'address, latitude, and longitude are required' });
      return;
    }

    const deliveryLocation = { address, latitude, longitude };

    const { error } = await supabase.admin
      .from('users')
      .update({ delivery_location: JSON.stringify(deliveryLocation) })
      .eq('id', userId);

    if (error) {
      console.error('[profile] updateDeliveryLocation error:', error);
      res.status(500).json({ error: 'Failed to update delivery location' });
      return;
    }

    res.status(200).json({
      message: 'Delivery location updated',
      delivery_location: deliveryLocation,
    });
  } catch (error) {
    console.error('[profile] updateDeliveryLocation error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};
