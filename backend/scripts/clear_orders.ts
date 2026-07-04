/**
 * One-time script to clear all orders from the database.
 * Run with: npx ts-node scripts/clear_orders.ts
 *
 * Deletes in order: calls → order_items → orders
 * to respect foreign key constraints.
 */
import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
import path from 'path';
// eslint-disable-next-line @typescript-eslint/no-var-requires
const WebSocket = require('ws');

dotenv.config({ path: path.resolve(__dirname, '../.env') });

const url = process.env.SUPABASE_URL || '';
const key = process.env.SUPABASE_SERVICE_ROLE_KEY || '';

if (!url || !key) {
  console.error('❌ SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set in .env');
  process.exit(1);
}

const admin = createClient(url, key, {
  auth: { autoRefreshToken: false, persistSession: false },
  realtime: { transport: WebSocket as any },
});

async function clearOrders() {
  console.log('🗑️  Clearing orders...');

  // Delete in order of FK dependencies
  const { error: errCalls } = await admin.from('calls').delete().neq('id', '00000000-0000-0000-0000-000000000000');
  if (errCalls) console.error('  calls:', errCalls.message);
  else console.log('  ✅ calls cleared');

  const { error: errItems } = await admin.from('order_items').delete().neq('id', '00000000-0000-0000-0000-000000000000');
  if (errItems) console.error('  order_items:', errItems.message);
  else console.log('  ✅ order_items cleared');

  const { error: errOrders } = await admin.from('orders').delete().neq('id', '00000000-0000-0000-0000-000000000000');
  if (errOrders) console.error('  orders:', errOrders.message);
  else console.log('  ✅ orders cleared');

  console.log('✅ Done!');
}

clearOrders().catch(console.error);
