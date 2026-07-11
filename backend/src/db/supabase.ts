import { createClient, SupabaseClient } from '@supabase/supabase-js';
// eslint-disable-next-line @typescript-eslint/no-var-requires
const WebSocket = require('ws');

let _adminClient: SupabaseClient | null = null;
let _anonClient: SupabaseClient | null = null;

function getSupabaseUrl(): string {
  return process.env.SUPABASE_URL || '';
}

function getServiceRoleKey(): string {
  return process.env.SUPABASE_SERVICE_ROLE_KEY || '';
}

function getAnonKey(): string {
  return process.env.SUPABASE_ANON_KEY || '';
}

const clientOptions = {
  auth: {
    autoRefreshToken: false,
    persistSession: false,
  },
  realtime: {
    transport: WebSocket as any,
  },
};

/**
 * Admin client with service_role key — bypasses all RLS.
 * Use for backend-only database operations (OTP, user management, etc.)
 */
export function getAdminClient(): SupabaseClient {
  if (!_adminClient) {
    const url = getSupabaseUrl();
    const key = getServiceRoleKey();
    if (!url || !key) {
      throw new Error(
        'SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set in environment',
      );
    }
    _adminClient = createClient(url, key, clientOptions);
  }
  return _adminClient;
}

/**
 * Anon client with anon key — respects RLS.
 * Use for auth operations (signIn, signUp, etc.)
 */
export function getAnonClient(): SupabaseClient {
  if (!_anonClient) {
    const url = getSupabaseUrl();
    const key = getAnonKey();
    if (!url || !key) {
      throw new Error(
        'SUPABASE_URL and SUPABASE_ANON_KEY must be set in environment',
      );
    }
    _anonClient = createClient(url, key, clientOptions);
  }
  return _anonClient;
}

export const supabase = {
  get admin(): SupabaseClient {
    return getAdminClient();
  },
  get auth(): SupabaseClient {
    return getAnonClient();
  },
};
