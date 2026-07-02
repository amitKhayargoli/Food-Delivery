import { Request } from 'express';
import jwt from 'jsonwebtoken';
import { supabase } from '../db/supabase';

const JWT_SECRET = process.env.JWT_SECRET || 'supersecretkey';

interface JwtPayload {
  id: string;
  role: string;
}

/**
 * Extract the authenticated user ID from the request.
 *
 * Accepts two types of Bearer tokens:
 *   1. A custom backend JWT signed with JWT_SECRET (issued by the backend's
 *      auth controllers — OTP, login, Google sign-in, complete-profile)
 *   2. A Supabase access token (issued by Supabase Auth when users sign in
 *      via `client.auth.signInWithPassword()` or similar flows)
 *
 * Returns `null` when the token is missing, expired, or invalid.
 */
export async function getUserId(req: Request): Promise<string | null> {
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) return null;

  const token = authHeader.slice(7);

  // 1. Try custom backend JWT
  try {
    const payload = jwt.verify(token, JWT_SECRET) as JwtPayload;
    if (payload.id) return payload.id;
  } catch {
    // Not a custom JWT — fall through to Supabase check
  }

  // 2. Try Supabase access token
  try {
    const { data, error } = await supabase.admin.auth.getUser(token);
    if (error || !data?.user) return null;
    return data.user.id;
  } catch {
    return null;
  }
}
