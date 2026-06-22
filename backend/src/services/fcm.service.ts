/**
 * FCM Push Notification Service
 *
 * Sends push notifications to Android/iOS devices via the Firebase Cloud
 * Messaging HTTP v1 API using OAuth 2.0 authentication.
 *
 * Setup:
 *   1. Go to Firebase Console → Project Settings → Service Accounts
 *   2. Click "Generate new private key" → download the JSON file
 *   3. Place it at backend/fcm-service-account.json (gitignored)
 *   4. Set FCM_SERVICE_ACCOUNT_PATH in backend/.env
 *
 * The device tokens are stored in the `device_tokens` Supabase table.
 */

import { GoogleAuth } from 'google-auth-library';
import path from 'path';

const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';
const FCM_PROJECT_ID = 'android-dcb82';

// ──────────────────────────────────────────────
//  OAuth2 Access Token Management
// ──────────────────────────────────────────────

/**
 * Lazy singleton GoogleAuth instance. The underlying OAuth2Client handles
 * token refresh internally — each call to getAccessToken() returns a fresh
 * token when the cached one expires, so we don't need our own cache.
 */
let _auth: GoogleAuth | null = null;

function getAuth(): GoogleAuth | null {
  const serviceAccountPath = process.env.FCM_SERVICE_ACCOUNT_PATH;
  if (!serviceAccountPath) {
    console.warn(
      '[FCM] FCM_SERVICE_ACCOUNT_PATH not configured — push not sent.',
    );
    return null;
  }

  if (!_auth) {
    _auth = new GoogleAuth({
      keyFile: path.resolve(serviceAccountPath),
      scopes: FCM_SCOPE,
    });
  }
  return _auth;
}

/**
 * Get a valid OAuth2 access token for FCM.
 * Uses the service account JSON file specified via
 * FCM_SERVICE_ACCOUNT_PATH env var.
 * Token refresh is handled internally by google-auth-library.
 */
async function getAccessToken(): Promise<string | null> {
  const auth = getAuth();
  if (!auth) return null;

  try {
    const client = await auth.getClient();
    const accessToken = await client.getAccessToken();
    return accessToken?.token ?? null;
  } catch (error) {
    console.error('[FCM] Auth error:', error);
    return null;
  }
}

// ──────────────────────────────────────────────
//  Send Push Notification (FCM HTTP v1 API)
// ──────────────────────────────────────────────

/**
 * Send a push notification to a specific device token via the
 * FCM HTTP v1 API.
 */
export async function sendPushNotification(
  token: string,
  payload: {
    title: string;
    body: string;
    data?: Record<string, string>;
  },
): Promise<boolean> {
  const accessToken = await getAccessToken();
  if (!accessToken) return false;

  const url = `https://fcm.googleapis.com/v1/projects/${FCM_PROJECT_ID}/messages:send`;

  const message: Record<string, any> = {
    token,
    notification: {
      title: payload.title,
      body: payload.body,
    },
    data: payload.data ?? {},
    android: {
      priority: 'HIGH',
      notification: {
        priority: 'HIGH',
        sound: 'default',
      },
    },
  };

  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${accessToken}`,
      },
      body: JSON.stringify({ message }),
    });

    if (!response.ok) {
      const body = await response.text();
      console.error('[FCM] Send failed:', response.status, body);

      // google-auth-library handles token refresh internally on next call
      return false;
    }

    return true;
  } catch (error) {
    console.error('[FCM] Send error:', error);
    return false;
  }
}

/**
 * Send a push notification to all device tokens associated with a user.
 * Tokens are stored in the `device_tokens` table keyed by user_id.
 */
export async function notifyUser(
  userId: string,
  supabaseAdmin: any,
  payload: { title: string; body: string; data?: Record<string, string> },
): Promise<void> {
  try {
    // Fetch all active device tokens for this user
    const { data: tokens, error } = await supabaseAdmin
      .from('device_tokens')
      .select('token')
      .eq('user_id', userId);

    if (error) {
      console.error('[FCM] Failed to fetch device tokens:', error.message);
      return;
    }

    if (!tokens || tokens.length === 0) {
      debugLog('[FCM] No device tokens found for user', userId);
      return;
    }

    const results = await Promise.allSettled(
      tokens.map((row: { token: string }) =>
        sendPushNotification(row.token, payload),
      ),
    );

    const succeeded = results.filter(
      (r) => r.status === 'fulfilled' && r.value,
    ).length;
    debugLog(
      `[FCM] Notified user ${userId}: ${succeeded}/${tokens.length} tokens delivered`,
    );
  } catch (error) {
    console.error('[FCM] notifyUser error:', error);
  }
}

function debugLog(...args: any[]) {
  if (process.env.NODE_ENV !== 'production') {
    console.log(...args);
  }
}
