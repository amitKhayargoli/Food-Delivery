/**
 * Quick script to list delivery boys and set a rider as online.
 *
 * Usage:
 *   npx ts-node scripts/go_online.ts list              # List delivery boys
 *   npx ts-node scripts/go_online.ts online <user_id>   # Set a rider as online
 */
import { createClient } from '@supabase/supabase-js';
import * as dotenv from 'dotenv';
import * as path from 'path';
// eslint-disable-next-line @typescript-eslint/no-var-requires
const WebSocket = require('ws');

dotenv.config({ path: path.resolve(__dirname, '../.env') });

const admin = createClient(
  process.env.SUPABASE_URL || '',
  process.env.SUPABASE_SERVICE_ROLE_KEY || '',
  { auth: { autoRefreshToken: false, persistSession: false }, realtime: { transport: WebSocket as any } },
);

async function listRiders() {
  // Try both single role column and roles array
  const { data: riders1 } = await admin
    .from('users')
    .select('id, username, phone, role')
    .eq('role', 'DELIVERY_BOY');

  const { data: riders2 } = await admin
    .from('users')
    .select('id, username, phone, roles')
    .contains('roles', ['DELIVERY_BOY']);

  const allRiders = [...(riders1 || []), ...(riders2 || [])];
  const seen = new Set();
  const unique = allRiders.filter(r => {
    if (seen.has(r.id)) return false;
    seen.add(r.id);
    return true;
  });

  if (unique.length === 0) {
    console.log('No delivery boys found.');
    return;
  }

  console.log('\n📋 Delivery Boys:\n');
  for (const r of unique) {
    // Check if they have a rider_locations entry
    const { data: loc } = await admin
      .from('rider_locations')
      .select('is_online, is_on_delivery')
      .eq('user_id', r.id)
      .maybeSingle();

    const status = loc ? (loc.is_online ? '🟢 Online' : '🔴 Offline') : '⚫ No location';
    const onDelivery = loc?.is_on_delivery ? ' (on delivery)' : '';
    console.log(`  ${r.id}  ${r.username || 'No name'}  ${r.phone || ''}  ${status}${onDelivery}`);
  }
  console.log('\nTo set a rider online:');
  console.log('  npx ts-node scripts/go_online.ts online <full_user_id>\n');
}

async function goOnline(userId: string) {
  // Check if user exists
  const { data: user } = await admin
    .from('users')
    .select('id, username')
    .eq('id', userId)
    .maybeSingle();

  if (!user) {
    console.error(`❌ User not found with ID: ${userId}`);
    process.exit(1);
  }

  const now = new Date().toISOString();

  // Upsert into rider_locations with is_online = true
  const { error } = await admin
    .from('rider_locations')
    .upsert({
      user_id: userId,
      latitude: 27.7172,
      longitude: 85.3240,
      is_online: true,
      is_on_delivery: false,
      last_active_at: now,
      updated_at: now,
    }, { onConflict: 'user_id' });

  if (error) {
    console.error('❌ Failed to set online:', error.message);
    process.exit(1);
  }

  console.log(`\n✅ ${user.username || 'Rider'} is now ONLINE 🟢\n`);
}

const cmd = process.argv[2];

if (cmd === 'list') {
  listRiders();
} else if (cmd === 'online') {
  const userId = process.argv[3];
  if (!userId) {
    console.error('❌ Please provide a user ID.\n   Usage: npx ts-node scripts/go_online.ts online <USER_ID>\n');
    process.exit(1);
  }
  goOnline(userId);
} else {
  console.log(`
  Usage:
    npx ts-node scripts/go_online.ts list              # List delivery boys
    npx ts-node scripts/go_online.ts online <user_id>   # Set a rider as online
  `);
}
