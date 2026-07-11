/**
 * Migration script to create the `notifications` table.
 *
 * This table stores in-app notifications for each user. When a push
 * notification is sent via FCM, a copy is also inserted here so the
 * user can view their notification history in the app.
 *
 * Run: npx ts-node scripts/create_notifications_table.ts
 */
import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
import path from 'path';

dotenv.config({ path: path.resolve(__dirname, '../.env') });

const supabaseUrl = process.env.SUPABASE_URL;
const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!supabaseUrl || !supabaseKey) {
  console.error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in .env');
  process.exit(1);
}

const admin = createClient(supabaseUrl, supabaseKey, {
  auth: { autoRefreshToken: false, persistSession: false },
});

async function main() {
  console.log('[migrate] Creating notifications table...');

  const { error } = await admin.rpc('create_notifications_table' as any, {}).maybeSingle();

  if (error && !error.message.includes('already exists')) {
    // Try raw SQL via the Supabase REST API
    const { error: sqlError } = await admin.from('_migrations').insert({
      name: 'create_notifications_table',
      sql: `
        CREATE TABLE IF NOT EXISTS notifications (
          id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
          user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
          title TEXT NOT NULL,
          body TEXT NOT NULL,
          type TEXT DEFAULT 'general',
          data JSONB DEFAULT '{}'::jsonb,
          is_read BOOLEAN DEFAULT false,
          created_at TIMESTAMPTZ DEFAULT now()
        );

        CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON notifications(user_id);
        CREATE INDEX IF NOT EXISTS idx_notifications_created_at ON notifications(created_at DESC);
        CREATE INDEX IF NOT EXISTS idx_notifications_unread ON notifications(user_id, is_read) WHERE is_read = false;
      `,
    } as any).maybeSingle();

    if (sqlError) {
      console.error('[migrate] Failed:', sqlError.message);
      process.exit(1);
    }
  }

  console.log('[migrate] Notifications table ready.');
  process.exit(0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
