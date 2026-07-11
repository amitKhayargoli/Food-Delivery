/**
 * Seed Orders — using Supabase REST API directly
 * Bypasses the JS client schema cache issues.
 *
 *   cd backend && npx ts-node scripts/seed_orders_rest.ts
 */

import dotenv from 'dotenv';
import * as path from 'path';
dotenv.config({ path: path.join(__dirname, '..', '.env') });

const SUPABASE_URL = process.env.SUPABASE_URL || '';
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || '';

function now(offsetMinutes = 0): string {
  return new Date(Date.now() - offsetMinutes * 60 * 1000).toISOString();
}

function generateOrderNumber(): string {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  let code = '';
  for (let i = 0; i < 5; i++) code += chars[Math.floor(Math.random() * chars.length)];
  return `DAILO-${code}`;
}

async function restQuery(method: string, table: string, body?: any) {
  const url = `${SUPABASE_URL}/rest/v1/${table}`;
  const headers: Record<string, string> = {
    'apikey': SERVICE_KEY,
    'Authorization': `Bearer ${SERVICE_KEY}`,
    'Content-Type': 'application/json',
    'Prefer': 'return=minimal',
  };

  const res = await fetch(url, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`${res.status} ${res.statusText}: ${text.substring(0, 200)}`);
  }
  return res;
}

async function main() {
  console.log('📦 Seeding sample orders via REST API...\n');

  if (!SUPABASE_URL || !SERVICE_KEY) {
    console.error('❌ SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set');
    process.exit(1);
  }

  // Get restaurants
  const restUrl = `${SUPABASE_URL}/rest/v1/restaurant_applications?select=id,restaurant_name,user_id&status=eq.APPROVED`;
  const restRes = await fetch(restUrl, {
    headers: {
      'apikey': SERVICE_KEY,
      'Authorization': `Bearer ${SERVICE_KEY}`,
    },
  });
  const rests = (await restRes.json()) as any[];

  if (!rests || rests.length === 0) {
    console.log('❌ No approved restaurants found');
    process.exit(1);
  }
  console.log(`🏪 Found ${rests.length} restaurants`);

  // Get users
  const userUrl = `${SUPABASE_URL}/rest/v1/users?select=id,username,role`;
  const userRes = await fetch(userUrl, {
    headers: {
      'apikey': SERVICE_KEY,
      'Authorization': `Bearer ${SERVICE_KEY}`,
    },
  });
  const rawUsers = (await userRes.json()) as any[];

  const users = (rawUsers && rawUsers.length > 0)
    ? rawUsers
    : rests.map((r: any) => ({ id: r.user_id, username: 'Owner', role: 'RESTAURANT_OWNER' }));
  console.log(`👤 Using ${users.length} users`);

  // Get menu items per restaurant
  const menuMap = new Map<string, any[]>();
  for (const rest of rests) {
    const menuUrl = `${SUPABASE_URL}/rest/v1/menu_items?select=id,name,base_price&restaurant_id=eq.${rest.id}&limit=3`;
    const menuRes = await fetch(menuUrl, {
      headers: {
        'apikey': SERVICE_KEY,
        'Authorization': `Bearer ${SERVICE_KEY}`,
      },
    });
    const items = (await menuRes.json()) as any[];
    if (items.length > 0) menuMap.set(rest.id, items);
  }

  const statuses = ['PENDING', 'ACCEPTED', 'PREPARING', 'READY', 'PICKED_UP', 'DELIVERED'];
  let createdCount = 0;

  for (let i = 0; i < Math.min(12, rests.length * 2); i++) {
    const rest = rests[i % rests.length];
    const user = users[i % users.length];
    const status = statuses[i % statuses.length];
    const orderNumber = generateOrderNumber();
    const items = menuMap.get(rest.id);

    if (!items || items.length === 0) continue;

    const orderItems = items.map((item: any) => ({
      food_id: item.id,
      name: item.name,
      price: item.base_price,
      quantity: Math.floor(1 + Math.random() * 3),
    }));

    const subtotal = orderItems.reduce((sum: number, item: any) => sum + item.price * item.quantity, 0);
    const deliveryFee = Math.random() > 0.3 ? 50 : 0;
    const total = subtotal + deliveryFee;

    try {
      await restQuery('POST', 'orders', {
        user_id: user.id,
        restaurant_id: rest.id,
        order_number: orderNumber,
        status,
        items: orderItems,
        subtotal,
        delivery_fee: deliveryFee,
        total,
        delivery_address: {
          full_address: 'Thamel, Kathmandu 44600',
          latitude: 27.7172,
          longitude: 85.3240,
        },
        created_at: now(i * 120),
        updated_at: now(0),
      });
      console.log(`   ✅ ${orderNumber} (${status}) for ${rest.restaurant_name}`);
      createdCount++;
    } catch (err: any) {
      console.error(`   ❌ ${orderNumber}: ${err.message.substring(0, 150)}`);
    }
  }

  console.log(`\n📊 ${createdCount} orders created`);

  // Verify
  const verifyRes = await fetch(`${SUPABASE_URL}/rest/v1/orders?select=id`, {
    headers: {
      'apikey': SERVICE_KEY,
      'Authorization': `Bearer ${SERVICE_KEY}`,
    },
  });
  const allOrders = (await verifyRes.json()) as any[];
  console.log(`📦 Total orders in DB: ${allOrders?.length || 0}`);
}

main().catch(console.error);
