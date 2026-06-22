import dotenv from 'dotenv';
import * as path from 'path';
dotenv.config({ path: path.join(__dirname, '..', '.env') });

import { supabase } from '../src/db/supabase';

async function main() {
  console.log('=== GENERATING MIGRATION SQL ===\n');
  
  const missingColumns = [
    { name: 'order_number', type: 'TEXT', nullable: true },
    { name: 'items', type: 'JSONB', nullable: true, default: "'[]'::jsonb" },
    { name: 'delivery_address', type: 'JSONB', nullable: true },
    { name: 'delivery_notes', type: 'TEXT', nullable: true },
    { name: 'special_instructions', type: 'TEXT', nullable: true },
    { name: 'estimated_prep_time', type: 'INTEGER', nullable: true },
    { name: 'assigned_at', type: 'TIMESTAMPTZ', nullable: true },
    { name: 'accepted_at', type: 'TIMESTAMPTZ', nullable: true },
    { name: 'preparing_at', type: 'TIMESTAMPTZ', nullable: true },
    { name: 'ready_at', type: 'TIMESTAMPTZ', nullable: true },
    { name: 'picked_up_at', type: 'TIMESTAMPTZ', nullable: true },
    { name: 'delivered_at', type: 'TIMESTAMPTZ', nullable: true },
    { name: 'cancelled_at', type: 'TIMESTAMPTZ', nullable: true },
    { name: 'rejection_reason', type: 'TEXT', nullable: true },
    { name: 'updated_at', type: 'TIMESTAMPTZ', nullable: true, default: 'NOW()' },
  ];

  // Generate ALTER TABLE statements
  console.log('-- ============================================');
  console.log('-- ADD MISSING COLUMNS TO ORDERS TABLE');
  console.log('-- ============================================\n');

  for (const col of missingColumns) {
    const nullable = col.nullable ? '' : ' NOT NULL';
    const defaultVal = col.default ? ` DEFAULT ${col.default}` : '';
    console.log(`ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS ${col.name} ${col.type}${nullable}${defaultVal};`);
  }

  console.log('\n-- Add status constraint if not already present');
  console.log(`ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_status_check;`);
  console.log(`ALTER TABLE public.orders ADD CONSTRAINT orders_status_check CHECK (status IN (
    'PENDING', 'ACCEPTED', 'PREPARING', 'READY',
    'PICKED_UP', 'DELIVERED', 'CANCELLED', 'REJECTED'
  ));`);

  console.log('\n-- Create indexes for performance');
  console.log('CREATE INDEX IF NOT EXISTS idx_orders_restaurant_status ON public.orders(restaurant_id, status);');
  console.log('CREATE INDEX IF NOT EXISTS idx_orders_order_number ON public.orders(order_number);');
  console.log('CREATE INDEX IF NOT EXISTS idx_orders_delivery_boy ON public.orders(delivery_boy_id);\n');

  console.log('-- ============================================');
  console.log('-- THEN INSERT TEST ORDERS');
  console.log('-- ============================================\n');

  // Get data for test orders
  const { data: users } = await supabase.admin.from('users').select('id, username, role');
  const { data: rests } = await supabase.admin.from('restaurant_applications').select('id, restaurant_name, user_id').eq('status', 'APPROVED');
  const { data: items } = await supabase.admin.from('menu_items').select('id, name, base_price, restaurant_id');

  if (!users || !rests || !items) {
    console.log('-- ERROR: Could not fetch data for test orders');
    return;
  }

  // Find Asan Chwok Sweets & Snacks or first restaurant
  const rest = rests.find(r => r.restaurant_name === 'Asan Chwok Sweets & Snacks') || rests[0];
  const owner = users.find(u => u.id === rest.user_id);
  const customer = users.find(u => u.id !== rest.user_id && u.role !== 'RESTAURANT_OWNER') || users.find(u => u.id !== rest.user_id) || users[0];
  const restItems = items.filter(i => i.restaurant_id === rest.id);

  if (restItems.length < 3) {
    console.log('-- Not enough menu items for this restaurant, need at least 3');
    return;
  }

  const testOrders = [
    {
      order_number: 'LIFECYCLE-001', status: 'PENDING',
      items: restItems.slice(0, 3).map((i, idx) => ({
        menu_item_id: i.id, name: i.name,
        quantity: idx === 1 ? 3 : 2,
        price: Number(i.base_price), size: 'Regular'
      })),
      subtotal: 900, delivery_fee: 40, total: 940,
      delivery_address: { address: 'Lakeside, Pokhara', city: 'Pokhara', lat: 28.2096, lng: 83.9856 },
      delivery_notes: 'Leave at the reception desk',
      special_instructions: 'Extra spicy please',
      estimated_prep_time: 20,
      timestamps: {}
    },
    {
      order_number: 'LIFECYCLE-002', status: 'ACCEPTED',
      items: restItems.slice(0, 2).map((i, idx) => ({
        menu_item_id: i.id, name: i.name,
        quantity: idx === 1 ? 3 : 2,
        price: Number(i.base_price), size: 'Regular'
      })),
      subtotal: 460, delivery_fee: 40, total: 500,
      delivery_address: { address: 'Thamel, Kathmandu', city: 'Kathmandu' },
      special_instructions: 'Call when arriving',
      estimated_prep_time: 15,
      timestamps: { accepted_at: '-25 minutes' }
    },
    {
      order_number: 'LIFECYCLE-003', status: 'PREPARING',
      items: restItems.slice(1, 3).map((i, idx) => ({
        menu_item_id: i.id, name: i.name,
        quantity: idx === 0 ? 2 : 1,
        price: Number(i.base_price), size: 'Regular'
      })),
      subtotal: 420, delivery_fee: 40, total: 460,
      delivery_address: { address: 'Boudha, Kathmandu', city: 'Kathmandu' },
      special_instructions: 'No onions please',
      estimated_prep_time: 20,
      timestamps: { accepted_at: '-40 minutes', preparing_at: '-15 minutes' }
    },
    {
      order_number: 'LIFECYCLE-004', status: 'READY',
      items: [restItems[0]].map(i => ({
        menu_item_id: i.id, name: i.name,
        quantity: 1, price: Number(i.base_price), size: 'Regular'
      })),
      subtotal: 80, delivery_fee: 40, total: 120,
      delivery_address: { address: 'Patan Durbar Square, Lalitpur' },
      special_instructions: 'Ring the bell',
      estimated_prep_time: 10,
      timestamps: { accepted_at: '-55 minutes', preparing_at: '-40 minutes', ready_at: '-10 minutes' }
    },
    {
      order_number: 'LIFECYCLE-005', status: 'PICKED_UP',
      items: restItems.slice(0, 2).map((i, idx) => ({
        menu_item_id: i.id, name: i.name,
        quantity: idx === 0 ? 2 : 1,
        price: Number(i.base_price), size: 'Regular'
      })),
      subtotal: 260, delivery_fee: 40, total: 300,
      delivery_address: { address: 'Jawalakhel, Lalitpur' },
      estimated_prep_time: 15,
      timestamps: { accepted_at: '-70 minutes', preparing_at: '-55 minutes', ready_at: '-30 minutes', picked_up_at: '-15 minutes' }
    },
    {
      order_number: 'LIFECYCLE-006', status: 'DELIVERED',
      items: restItems.slice(0, 5).map((i, idx) => ({
        menu_item_id: i.id, name: i.name,
        quantity: idx < 3 ? 2 : 1,
        price: Number(i.base_price), size: 'Regular'
      })),
      subtotal: 880, delivery_fee: 40, total: 920,
      delivery_address: { address: 'Durbar Marg, Kathmandu' },
      estimated_prep_time: 20,
      timestamps: {
        accepted_at: '-85 minutes', preparing_at: '-70 minutes',
        ready_at: '-45 minutes', picked_up_at: '-30 minutes', delivered_at: '-10 minutes'
      }
    }
  ];

  for (const order of testOrders) {
    const itemsStr = JSON.stringify(order.items).replace(/'/g, "''");
    const addrStr = JSON.stringify(order.delivery_address).replace(/'/g, "''");
    const notes = order.delivery_notes ? `'${order.delivery_notes}'` : 'NULL';
    const special = order.special_instructions ? `'${order.special_instructions}'` : 'NULL';

    console.log(`INSERT INTO public.orders (
  user_id, restaurant_id, order_number, status,
  items, subtotal, delivery_fee, total,
  delivery_address, delivery_notes, special_instructions,
  estimated_prep_time, created_at, updated_at
) VALUES (
  '${customer.id}', '${rest.id}', '${order.order_number}', '${order.status}',
  '${itemsStr}'::jsonb,
  ${order.subtotal}, ${order.delivery_fee}, ${order.total},
  '${addrStr}'::jsonb,
  ${notes}, ${special},
  ${order.estimated_prep_time},
  NOW() - INTERVAL '${parseInt(order.timestamps.accepted_at || '-15 minutes') + 15} minutes',
  NOW()
);`);
  }

  console.log('\n-- Update timestamp columns');
  for (const order of testOrders) {
    const updates = Object.entries(order.timestamps)
      .filter(([_, v]) => v)
      .map(([col, val]) => `${col} = NOW()${val}`)
      .join(', ');
    if (updates) {
      console.log(`UPDATE public.orders SET ${updates} WHERE order_number = '${order.order_number}';`);
    }
  }

  console.log('\n-- Verify');
  console.log("SELECT order_number, status, total FROM public.orders WHERE order_number LIKE 'LIFECYCLE-%' ORDER BY order_number;");

  console.log('\n-- Summary:');
  console.log(`-- Owner user ID (for JWT): ${owner?.id || rest.user_id}`);
  console.log(`-- Restaurant ID: ${rest.id}`);
  console.log(`-- Orders to create: ${testOrders.length}`);
  console.log(`-- Menu items available for "${rest.restaurant_name}": ${restItems.length}`);
}

main().catch(e => console.error('ERROR:', e));
