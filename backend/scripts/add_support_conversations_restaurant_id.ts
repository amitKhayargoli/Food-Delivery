/**
 * Migration: Add restaurant_id to support_conversations
 *
 * This allows linking support conversations to specific restaurants,
 * so that only the restaurant owner of the relevant order can reply.
 *
 * Usage: npx ts-node scripts/add_support_conversations_restaurant_id.ts
 */
import { createClient } from '@supabase/supabase-js';
import * as dotenv from 'dotenv';
import * as path from 'path';
// eslint-disable-next-line @typescript-eslint/no-var-requires
const WebSocket = require('ws');

dotenv.config({ path: path.resolve(__dirname, '../.env') });

const SUPABASE_URL = process.env.SUPABASE_URL || '';
const SERVICE_ROLE = process.env.SUPABASE_SERVICE_ROLE_KEY || '';

if (!SUPABASE_URL || !SERVICE_ROLE) {
  console.error('❌ Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in .env');
  process.exit(1);
}

const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
  auth: { autoRefreshToken: false, persistSession: false },
  realtime: { transport: WebSocket as any },
});

async function migrate() {
  console.log('▶ Adding restaurant_id column to support_conversations...\n');

  // 1. Add the column (nullable to start)
  const { error: alterError } = await admin.rpc('exec_sql', {
    sql: `ALTER TABLE support_conversations ADD COLUMN IF NOT EXISTS restaurant_id UUID REFERENCES restaurant_applications(id);`,
  });

  if (alterError) {
    // Try direct SQL via query instead
    console.log('   RPC not available, trying direct approach...');
    const { error: directError } = await admin
      .from('support_conversations')
      .select('id, order_id')
      .limit(1);

    if (directError) {
      console.error('❌ Cannot access support_conversations table:', directError.message);
      console.log('\n   Please run this SQL manually in Supabase SQL Editor:\n');
      console.log('   ALTER TABLE support_conversations ADD COLUMN IF NOT EXISTS restaurant_id UUID REFERENCES restaurant_applications(id);');
      console.log('   CREATE INDEX IF NOT EXISTS idx_support_conversations_restaurant_id ON support_conversations(restaurant_id);\n');
      process.exit(1);
    }
  }

  console.log('✅ Column added or already exists.');

  // 2. Backfill restaurant_id for existing conversations with order_id
  const { data: conversations } = await admin
    .from('support_conversations')
    .select('id, order_id')
    .not('order_id', 'is', null);

  if (conversations && conversations.length > 0) {
    console.log(`\n▶ Backfilling restaurant_id for ${conversations.length} conversations...`);

    for (const conv of conversations) {
      // Look up order to get restaurant_id
      const { data: order } = await admin
        .from('orders')
        .select('restaurant_id')
        .eq('id', conv.order_id)
        .maybeSingle();

      if (order?.restaurant_id) {
        await admin
          .from('support_conversations')
          .update({ restaurant_id: order.restaurant_id })
          .eq('id', conv.id);
      }
    }

    console.log('✅ Backfill complete.');
  } else {
    console.log('\n   No conversations with order_id to backfill.');
  }

  // 3. Create index
  try {
    await admin.rpc('exec_sql', {
      sql: 'CREATE INDEX IF NOT EXISTS idx_support_conversations_restaurant_id ON support_conversations(restaurant_id);',
    });
  } catch (_) {
    console.log('   Index creation skipped (run manually if needed).');
  }

  console.log('\n✅ Migration complete!');
  console.log('   Please run this SQL in Supabase SQL Editor if the automated migration failed:\n');
  console.log('   ALTER TABLE support_conversations ADD COLUMN IF NOT EXISTS restaurant_id UUID REFERENCES restaurant_applications(id);');
  console.log('   CREATE INDEX IF NOT EXISTS idx_support_conversations_restaurant_id ON support_conversations(restaurant_id);');
}

migrate().catch(console.error);
