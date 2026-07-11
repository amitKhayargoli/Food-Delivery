/**
 * Seed Sample Orders
 *
 * Creates sample orders in various statuses for existing restaurants.
 * Run after seed_data.ts (which creates restaurants & menus).
 *
 *   cd backend && npx ts-node scripts/seed_orders.ts
 */

import dotenv from 'dotenv';
import * as path from 'path';
dotenv.config({ path: path.join(__dirname, '..', '.env') });

import { supabase } from '../src/db/supabase';

function now(offsetMinutes = 0): string {
  return new Date(Date.now() - offsetMinutes * 60 * 1000).toISOString();
}

function generateOrderNumber(): string {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  let code = '';
  for (let i = 0; i < 5; i++) code += chars[Math.floor(Math.random() * chars.length)];
  return `DAILO-${code}`;
}

async function main() {
  console.log('📦 Seeding sample orders...\n');

  // Get all restaurants
  const { data: rests } = await supabase.admin
    .from('restaurant_applications')
    .select('id, restaurant_name, user_id')
    .eq('status', 'APPROVED');

  if (!rests || rests.length === 0) {
    console.log('❌ No approved restaurants found. Run seed_data.ts first.');
    process.exit(1);
  }
  console.log(`🏪 Found ${rests.length} restaurants`);

  // Get all users to assign as order customers (any role works for testing)
  const { data: rawUsers } = await supabase.admin
    .from('users')
    .select('id, username, role');

  // Use actual users if available, otherwise fall back to restaurant owner user_ids
  const users = (rawUsers && rawUsers.length > 0)
    ? rawUsers
    : rests.map(r => ({ id: r.user_id, username: 'Restaurant Owner', role: 'RESTAURANT_OWNER' }));

  console.log(`👤 Found ${users.length} users (${rawUsers?.length || 0} from public.users, ${rests.length} fallback from restaurants)`);

  const statuses = ['PENDING', 'ACCEPTED', 'PREPARING', 'READY', 'PICKED_UP', 'DELIVERED'] as const;
  let createdCount = 0;
  let failCount = 0;

  for (let i = 0; i < Math.min(12, rests.length * 2); i++) {
    const rest = rests[i % rests.length];
    const user = users[i % users.length];

    // Get menu items for this restaurant
    const { data: items } = await supabase.admin
      .from('menu_items')
      .select('id, name, base_price')
      .eq('restaurant_id', rest.id)
      .limit(3);

    if (!items || items.length === 0) continue;

    const status = statuses[i % statuses.length];
    const orderNumber = generateOrderNumber();

    const orderItems = items.map((item: any) => ({
      food_id: item.id,
      name: item.name,
      price: item.base_price,
      quantity: Math.floor(1 + Math.random() * 3),
      image_url: null,
    }));

    const subtotal = orderItems.reduce((sum: number, item: any) => sum + item.price * item.quantity, 0);
    const deliveryFee = Math.random() > 0.3 ? 50 : 0;
    const total = subtotal + deliveryFee;

    const { error } = await supabase.admin.from('orders').insert({
      user_id: user.id,
      restaurant_id: rest.id,
      order_number: orderNumber,
      status,
      items: JSON.stringify(orderItems),
      subtotal,
      delivery_fee: deliveryFee,
      total,
      delivery_address: JSON.stringify({
        full_address: 'Thamel, Kathmandu 44600',
        latitude: 27.7172,
        longitude: 85.3240,
      }),
      created_at: now(i * 120),
      updated_at: now(0),
    });

    if (error) {
      console.error(`   ❌ ${orderNumber}: ${error.message}`);
      failCount++;
    } else {
      console.log(`   ✅ ${orderNumber} (${status}) for ${rest.restaurant_name}`);
      createdCount++;
    }
  }

  console.log(`\n📊 Summary: ${createdCount} created, ${failCount} failed`);

  // Final count
  const { data: allOrders } = await supabase.admin.from('orders').select('id');
  console.log(`📦 Total orders in DB: ${allOrders?.length || 0}`);
}

main().catch(console.error);
