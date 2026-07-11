import { Router, Request, Response } from 'express';
import jwt from 'jsonwebtoken';
import { supabase } from '../db/supabase';

const router = Router();
const JWT_SECRET = process.env.JWT_SECRET || 'supersecretkey';

interface JwtPayload {
  id: string;
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

// ──────────────────────────────────────────────
// POST /api/fcm/register-token
// Register (or update) the user's FCM device token
// ──────────────────────────────────────────────
router.post('/register-token', async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = getUserId(req);
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

export default router;
