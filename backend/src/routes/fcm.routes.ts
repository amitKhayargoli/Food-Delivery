import { Router, Request, Response } from 'express';
import { supabase } from '../db/supabase';
import { getUserId } from '../utils/auth';

const router = Router();

// ──────────────────────────────────────────────
// POST /api/fcm/register-token
// Register (or update) the user's FCM device token
// ──────────────────────────────────────────────
router.post('/register-token', async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const { token } = req.body;
    if (!token) {
      res.status(400).json({ error: 'Token is required' });
      return;
    }

    // Upsert the device token — if the same token already exists for this
    // user, update its last_seen timestamp; otherwise insert a new row.
    const { error: upsertError } = await supabase.admin
      .from('device_tokens')
      .upsert(
        {
          user_id: userId,
          token,
          last_seen: new Date().toISOString(),
        },
        { onConflict: 'token' },
      );

    if (upsertError) {
      console.error('[FCM] Token upsert error:', upsertError.message);
      res.status(500).json({ error: 'Failed to register token' });
      return;
    }

    res.status(200).json({ message: 'Token registered' });
  } catch (error) {
    console.error('[FCM] Register token error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ──────────────────────────────────────────────
// POST /api/fcm/notify-call
// Send an incoming call push notification to the callee.
// Called by the Flutter app immediately after inserting a call record.
// ──────────────────────────────────────────────
router.post('/notify-call', async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const { calleeId, callerName, callId, channelName } = req.body;
    if (!calleeId || !callerName || !callId || !channelName) {
      res.status(400).json({ error: 'Missing required fields: calleeId, callerName, callId, channelName' });
      return;
    }

    // Import notifyIncomingCall dynamically to avoid circular imports
    const { notifyIncomingCall } = await import('../services/fcm.service');

    await notifyIncomingCall(calleeId, supabase.admin, {
      callerId: userId,
      callerName,
      callId,
      channelName,
    });

    res.status(200).json({ message: 'Call notification sent' });
  } catch (error) {
    console.error('[FCM] Notify call error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

export default router;
