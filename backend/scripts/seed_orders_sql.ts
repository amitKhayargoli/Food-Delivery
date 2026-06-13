/**
 * Generate SQL for creating sample orders.
 * Run this to print the SQL, then paste the output into Supabase SQL Editor.
 *
 *   cd backend && npx ts-node scripts/seed_orders_sql.ts > output_orders.sql
 */

import dotenv from 'dotenv';
import * as path from 'path';
dotenv.config({ path: path.join(__dirname, '..', '.env') });

import { supabase } from '../src/db/supabase';

function now(offsetMinutes = 0): string {
  return new Date(Date.now() - offsetMinutes * 60 * 1000).toISOString();
}

function esc(val: string): string {
  return val.replace(/'/g, "''");
}

async function main() {
  // Get restaurants
  const { data: rests } = await supabase.admin
    .from('restaurant_applications')
    .select('id, restaurant_name, user_id')
    .eq('status', 'APPROVED');
  if (!rests || rests.length === 0) { console.log('-- No restaurants found'); return; }

  // Get users
  const { data: rawUsers } = await supabase.admin.from('users').select('id, username, role');
  const users = (rawUsers && rawUsers.length > 0)
    ? rawUsers
    : rests.map(r => ({ id: r.user_id, username: 'Owner', role: 'RESTAURANT_OWNER' }));

  // Get menu items per restaurant
  const menuMap = new Map<string, any[]>();
  for (const r of rests) {
    const { data: items } = await supabase.admin
      .from('menu_items')
      .select('id, name, base_price')
      .eq('restaurant_id', r.id)
      .limit(3);
    if (items && items.length > 0) menuMap.set(r.id, items);
  }

  const statuses = ['PENDING', 'ACCEPTED', 'PREPARING', 'READY', 'PICKED_UP', 'DELIVERED'];

  console.log('-- Generated order seed SQL');
  console.log(`-- ${new Date().toISOString()}`);
  console.log();

  for (let i = 0; i < Math.min(12, rests.length * 2); i++) {
    const rest = rests[i % rests.length];
    const user = users[i % users.length];
    const status = statuses[i % statuses.length];

    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    let code = '';
    for (let j = 0; j < 5; j++) code += chars[Math.floor(Math.random() * chars.length)];
    const orderNumber = `DAILO-${code}`;

    const items = menuMap.get(rest.id);
    if (!items || items.length === 0) continue;

    const orderItems = items.map((item: any) => ({
      food_id: item.id,
      name: item.name,
      price: item.base_price,
      quantity: Math.floor(1 + Math.random() * 3),
    }));
    const subtotal = orderItems.reduce((s: number, it: any) => s + it.price * it.quantity, 0);
    const deliveryFee = Math.random() > 0.3 ? 50 : 0;
    const total = subtotal + deliveryFee;

    const itemsJson = JSON.stringify(orderItems);
    const addrJson = JSON.stringify({
      full_address: 'Thamel, Kathmandu 44600',
      latitude: 27.7172,
      longitude: 85.3240,
    });

    const created = now(i * 120);
    const updated = now(0);

    console.log(`INSERT INTO public.orders (user_id, restaurant_id, order_number, status, items, subtotal, delivery_fee, total, delivery_address, created_at, updated_at)`);
    console.log(`VALUES (`);
    console.log(`  '${esc(user.id)}',`);
    console.log(`  '${esc(rest.id)}',`);
    console.log(`  '${esc(orderNumber)}',`);
    console.log(`  '${esc(status)}',`);
    console.log(`  '${esc(itemsJson)}'::jsonb,`);
    console.log(`  ${subtotal},`);
    console.log(`  ${deliveryFee},`);
    console.log(`  ${total},`);
    console.log(`  '${esc(addrJson)}'::jsonb,`);
    console.log(`  '${created}',`);
    console.log(`  '${updated}'`);
    console.log(`);`);
    console.log();
  }

  console.log('-- Verification:');
  console.log("SELECT COUNT(*) AS total_orders FROM public.orders;");
}

main().catch(console.error);
