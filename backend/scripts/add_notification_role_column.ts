/**
 * Migration script to add the `role` column to the `notifications` table.
 *
 * This column tags each notification with the intended target role so that
 * users with multiple roles (e.g. USER + RESTAURANT_OWNER) only see
 * notifications relevant to their currently active role.
 *
 * All existing rows get role = 'customer' as the default.
 *
 * Run: npx ts-node scripts/add_notification_role_column.ts
 */
import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
import path from 'path';

dotenv.config({ path: path.resolve(__dirname, '../.env') });

async function main() {
  const supabaseUrl = process.env.SUPABASE_URL;
  const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!supabaseUrl || !supabaseKey) {
    console.error('Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in .env');
    process.exit(1);
  }

  const admin = createClient(supabaseUrl, supabaseKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  console.log('[migrate] Adding role column to notifications table...');

  // Use raw SQL via the Supabase REST API
  const { error } = await admin.rpc('exec_sql', {
    sql: `
      ALTER TABLE IF EXISTS notifications
      ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT 'customer';

      CREATE INDEX IF NOT EXISTS idx_notifications_role ON notifications(role);
      CREATE INDEX IF NOT EXISTS idx_notifications_user_role
        ON notifications(user_id, role);
    `,
  } as any).maybeSingle();

  if (error) {
    console.log('[migrate] exec_sql RPC not available, trying direct ALTER TABLE...');

    // Fallback: try to create the function first
    const createFnResult = await fetch(
      `${supabaseUrl}/rest/v1/rpc/`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'apikey': supabaseKey,
          'Authorization': `Bearer ${supabaseKey}`,
          'Prefer': 'params=single-object',
        },
        body: JSON.stringify({
          sql: `
            CREATE OR REPLACE FUNCTION add_notification_role_column()
            RETURNS void
            LANGUAGE plpgsql
            AS $$
            BEGIN
              ALTER TABLE IF EXISTS notifications
              ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT 'customer';
              CREATE INDEX IF NOT EXISTS idx_notifications_role ON notifications(role);
              CREATE INDEX IF NOT EXISTS idx_notifications_user_role
                ON notifications(user_id, role);
            END;
            $$;
          `,
        }),
      },
    );

    if (!createFnResult.ok) {
      const text = await createFnResult.text();
      console.log('[migrate] Function creation response:', createFnResult.status, text);
    }

    // Now run the function
    const runResult = await fetch(
      `${supabaseUrl}/rest/v1/rpc/add_notification_role_column`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'apikey': supabaseKey,
          'Authorization': `Bearer ${supabaseKey}`,
        },
      },
    );

    if (runResult.ok) {
      console.log('[migrate] ✅ Role column added successfully.');
    } else {
      const text = await runResult.text();
      console.log('[migrate] Migration result:', runResult.status, text);
      console.log('[migrate] ⚠️ You may need to run the SQL manually in Supabase SQL Editor:');
      console.log(`
        ALTER TABLE IF EXISTS notifications
        ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT 'customer';

        CREATE INDEX IF NOT EXISTS idx_notifications_role ON notifications(role);
        CREATE INDEX IF NOT EXISTS idx_notifications_user_role
          ON notifications(user_id, role);
      `);
    }
  } else {
    console.log('[migrate] ✅ Role column added successfully.');
  }

  process.exit(0);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
