/**
 * Seed Orders — Fixed version without schema cache issues
 *
 * Uses raw SQL to avoid Supabase schema cache problems.
 *   cd backend && npx ts-node scripts/seed_orders_final.ts
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

  // Get all restaurants with user data
  const { data: rests } = await supabase.admin
    .from('restaurant_applications')
    .select('id, restaurant_name, user_id')
    .eq('status', 'APPROVED');

  if (!rests || rests.length === 0) {
    console.log('❌ No approved restaurants found.');
    process.exit(1);
  }
  console.log(`🏪 Found ${rests.length} restaurants`);

  // Get users
  const { data: rawUsers } = await supabase.admin
    .from('users')
    .select('id, username, role');

  const users = (rawUsers && rawUsers.length > 0)
    ? rawUsers
    : rests.map(r => ({ id: r.user_id, username: 'Owner', role: 'RESTAURANT_OWNER' }));
  console.log(`👤 Using ${users.length} users for order assignment`);

  const statuses = ['PENDING', 'ACCEPTED', 'PREPARING', 'READY', 'PICKED_UP', 'DELIVERED'];
  let createdCount = 0;
  let failCount = 0;

  for (let i = 0; i < Math.min(12, rests.length * 2); i++) {
    const rest = rests[i % rests.length];
    const user = users[i % users.length];
    const status = statuses[i % statuses.length];
    const orderNumber = generateOrderNumber();

    // Get menu items
    const { data: items } = await supabase.admin
      .from('menu_items')
      .select('id, name, base_price')
      .eq('restaurant_id', rest.id)
      .limit(3);

    if (!items || items.length === 0) {
      console.log(`   ⏩ No menu items for ${rest.restaurant_name}, skipping`);
      continue;
    }

    const orderItems = items.map((item: any) => ({
      food_id: item.id,
      name: item.name,
      price: item.base_price,
      quantity: Math.floor(1 + Math.random() * 3),
    }));

    const subtotal = orderItems.reduce((sum: number, item: any) => sum + item.price * item.quantity, 0);
    const deliveryFee = Math.random() > 0.3 ? 50 : 0;
    const total = subtotal + deliveryFee;

    // Use a single raw SQL query to bypass schema cache
    const { error } = await supabase.admin.rpc('exec_sql' as any, {
      query: `
        INSERT INTO public.orders (
          user_id, restaurant_id, order_number, status,
          items, subtotal, delivery_fee, total,
          delivery_address, created_at, updated_at
        ) VALUES (
          '${user.id}',
          '${rest.id}',
          '${orderNumber}',
          '${status}',
          '${JSON.stringify(orderItems).replace(/'/g, "''")}',
          ${subtotal},
          ${deliveryFee},
          ${total},
          '${JSON.stringify({ full_address: 'Thamel, Kathmandu 44600', latitude: 27.7172, longitude: 85.3240 }).replace(/'/g, "''")}',
          '${now(i * 120)}',
          '${now(0)}'
        );
      `,
    });

    if (error) {
      // Fallback: try direct insert without delivery_address
      console.error(`   ❌ SQL approach failed: ${error.message}`);
      console.log('   🔄 Trying direct insert without delivery_address...');

      const { error: e2 } = await supabase.admin
        .from('orders')
        .insert({
          user_id: user.id,
          restaurant_id: rest.id,
          order_number: orderNumber,
          status,
          items: orderItems,
          subtotal,
          delivery_fee: deliveryFee,
          total,
          created_at: now(i * 120),
          updated_at: now(0),
        });

      if (e2) {
        console.error(`   ❌ ${orderNumber}: ${e2.message}`);
        failCount++;
      } else {
        console.log(`   ✅ ${orderNumber} (${status}) for ${rest.restaurant_name}`);
        createdCount++;
      }
    } else {
      console.log(`   ✅ ${orderNumber} (${status}) for ${rest.restaurant_name}`);
      createdCount++;
    }
  }

  console.log(`\n📊 Summary: ${createdCount} created, ${failCount} failed`);

  const { data: allOrders } = await supabase.admin.from('orders').select('id');
  console.log(`📦 Total orders in DB: ${allOrders?.length || 0}`);
}

main().catch(console.error);
