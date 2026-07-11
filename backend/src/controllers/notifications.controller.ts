import { Request, Response } from 'express';
import { getUserId } from '../utils/auth';
import { supabase } from '../db/supabase';

// ──────────────────────────────────────────────
// GET /api/notifications
// Fetch notifications for the authenticated user.
// Supports pagination via limit/offset and read/unread filter.
// Optionally filter by `role` so users with multiple roles only see
// notifications relevant to their currently active role.
// ──────────────────────────────────────────────
export const getNotifications = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const limit = Math.min(Math.max(parseInt(req.query.limit as string) || 50, 1), 100);
    const offset = Math.max(parseInt(req.query.offset as string) || 0, 0);
    const unreadOnly = req.query.unread === 'true';
    const roleFilter = req.query.role as string | undefined;

    let query = supabase.admin
      .from('notifications')
      .select('*', { count: 'exact' })
      .eq('user_id', userId)
      .order('created_at', { ascending: false })
      .range(offset, offset + limit - 1);

    if (unreadOnly) {
      query = query.eq('is_read', false);
    }

    // Filter by role if specified
    if (roleFilter) {
      query = query.eq('role', roleFilter);
    }

    const { data: notifications, error, count } = await query;

    if (error) {
      console.error('[Notifications] Fetch error:', error.message);
      res.status(500).json({ error: 'Failed to fetch notifications.' });
      return;
    }

    // Count unread (also respect role filter)
    let unreadQuery = supabase.admin
      .from('notifications')
      .select('*', { count: 'exact', head: true })
      .eq('user_id', userId)
      .eq('is_read', false);

    if (roleFilter) {
      unreadQuery = unreadQuery.eq('role', roleFilter);
    }

    const { count: unreadCount } = await unreadQuery;

    res.status(200).json({
      notifications: notifications || [],
      unread_count: unreadCount ?? 0,
      total: count ?? notifications?.length ?? 0,
    });
  } catch (error) {
    console.error('[Notifications] Error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// PATCH /api/notifications/:id/read
// Mark a single notification as read.
// ──────────────────────────────────────────────
export const markAsRead = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const { id } = req.params;

    const { error } = await supabase.admin
      .from('notifications')
      .update({ is_read: true })
      .eq('id', id)
      .eq('user_id', userId);

    if (error) {
      console.error('[Notifications] Mark read error:', error.message);
      res.status(500).json({ error: 'Failed to mark as read.' });
      return;
    }

    res.status(200).json({ message: 'Marked as read.' });
  } catch (error) {
    console.error('[Notifications] Error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// POST /api/notifications/read-all
// Mark all notifications as read for the authenticated user.
// ──────────────────────────────────────────────
export const markAllAsRead = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const { error } = await supabase.admin
      .from('notifications')
      .update({ is_read: true })
      .eq('user_id', userId)
      .eq('is_read', false);

    if (error) {
      console.error('[Notifications] Mark all read error:', error.message);
      res.status(500).json({ error: 'Failed to mark all as read.' });
      return;
    }

    res.status(200).json({ message: 'All notifications marked as read.' });
  } catch (error) {
    console.error('[Notifications] Error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};
