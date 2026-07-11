import dotenv from 'dotenv';
import * as path from 'path';
dotenv.config({ path: path.join(__dirname, '..', '.env') });
import { supabase } from '../src/db/supabase';

function esc(s: string) { return s.replace(/'/g, "''"); }

async function main() {
  const { data: apps } = await supabase.admin.from('restaurant_applications').select('id, restaurant_name, user_id').eq('status', 'APPROVED');
  const { data: users } = await supabase.admin.from('users').select('id, username, role');
  const { data: items } = await supabase.admin.from('menu_items').select('id, name, base_price, restaurant_id');
  if (!apps || !users || !items) return;

  const rest = apps.find(r => r.restaurant_name === 'Asan Chwok Sweets & Snacks') || apps[0];
  const customer = users.find((u: any) => u.id !== rest.user_id) || users[0];
  const restItems = items.filter(i => i.restaurant_id === rest.id);
  const owner = users.find(u => u.id === rest.user_id);

  console.log(`-- https://hsiaguzxkytfsstvatep.supabase.co`);
  console.log(`-- Run this in Supabase SQL Editor`);
  console.log(`-- Restaurant: ${rest.restaurant_name}`);
  console.log(`-- Owner: ${owner?.username} (${rest.user_id})`);
  console.log(`-- Customer: ${customer.id.slice(0,12)}...\n`);

  // Only add columns that might be missing (IF NOT EXISTS)
  console.log('-- STEP 1: Add missing columns (safe to re-run)');
  console.log('ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS order_number TEXT;');
  console.log("ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS items JSONB DEFAULT '[]'::jsonb;");
  console.log('ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS delivery_address JSONB;');
  console.log('ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS delivery_notes TEXT;');
  console.log('ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS special_instructions TEXT;');
  console.log('ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS estimated_prep_time INTEGER;');
  console.log('ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS assigned_at TIMESTAMPTZ;');
  console.log('ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS accepted_at TIMESTAMPTZ;');
  console.log('ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS preparing_at TIMESTAMPTZ;');
  console.log('ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS ready_at TIMESTAMPTZ;');
  console.log('ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS picked_up_at TIMESTAMPTZ;');
  console.log('ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS out_for_delivery_at TIMESTAMPTZ;');
  console.log('ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS delivered_at TIMESTAMPTZ;');
  console.log('ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMPTZ;');
  console.log('ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS rejection_reason TEXT;');
  console.log('ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();');
  console.log('CREATE INDEX IF NOT EXISTS idx_orders_restaurant_status ON public.orders(restaurant_id, status);');
  console.log('CREATE INDEX IF NOT EXISTS idx_orders_order_number ON public.orders(order_number);');
  console.log('');

  // Insert just ONE restaurant (Asan Chwok Sweets) since the FK requires it
  console.log('-- STEP 2: Add the test restaurant (FK requirement)');
  console.log(`INSERT INTO public.restaurants (id, name, owner_id) VALUES ('${rest.id}', '${esc(rest.restaurant_name)}', '${rest.user_id}') ON CONFLICT (owner_id) DO NOTHING;`);
  console.log('');

  // 6 test orders
  console.log('-- STEP 3: Insert 6 test orders');
  
  const orders = [
    { num: 'LIFECYCLE-001', status: 'PENDING_RESTAURANT_APPROVAL', sub: 900, total: 940, prep: 20,
      items: restItems.slice(0, 3).map((i: any, idx: number) => ({ menu_item_id: i.id, name: i.name, quantity: idx === 1 ? 3 : 2, price: Number(i.base_price), size: 'Regular' })),
      addr: '{"address":"Lakeside, Pokhara","city":"Pokhara"}', notes: 'Leave at reception desk', special: 'Extra spicy please',
      created: '15', ts: '' },
    { num: 'LIFECYCLE-002', status: 'ACCEPTED', sub: 460, total: 500, prep: 15,
      items: restItems.slice(0, 2).map((i: any, idx: number) => ({ menu_item_id: i.id, name: i.name, quantity: idx === 1 ? 3 : 2, price: Number(i.base_price), size: 'Regular' })),
      addr: '{"address":"Thamel, Kathmandu"}', notes: null, special: 'Call when arriving',
      created: '30', ts: 'accepted_at = NOW() - INTERVAL \'25 minutes\'' },
    { num: 'LIFECYCLE-003', status: 'PREPARING', sub: 420, total: 460, prep: 20,
      items: restItems.slice(1, 3).map((i: any, idx: number) => ({ menu_item_id: i.id, name: i.name, quantity: idx === 0 ? 2 : 1, price: Number(i.base_price), size: 'Regular' })),
      addr: '{"address":"Boudha, Kathmandu"}', notes: null, special: 'No onions please',
      created: '45', ts: 'accepted_at = NOW() - INTERVAL \'40 minutes\', preparing_at = NOW() - INTERVAL \'15 minutes\'' },
    { num: 'LIFECYCLE-004', status: 'READY_FOR_PICKUP', sub: 80, total: 120, prep: 10,
      items: [{ menu_item_id: restItems[0].id, name: restItems[0].name, quantity: 1, price: Number(restItems[0].base_price), size: 'Regular' }],
      addr: '{"address":"Patan Durbar Square, Lalitpur"}', notes: null, special: 'Ring the bell',
      created: '60', ts: 'accepted_at = NOW() - INTERVAL \'55 minutes\', preparing_at = NOW() - INTERVAL \'40 minutes\', ready_at = NOW() - INTERVAL \'10 minutes\'' },
    { num: 'LIFECYCLE-005', status: 'PICKED_UP', sub: 260, total: 300, prep: 15,
      items: restItems.slice(0, 2).map((i: any, idx: number) => ({ menu_item_id: i.id, name: i.name, quantity: idx === 0 ? 2 : 1, price: Number(i.base_price), size: 'Regular' })),
      addr: '{"address":"Jawalakhel, Lalitpur"}', notes: null, special: null,
      created: '75', ts: 'accepted_at = NOW() - INTERVAL \'70 minutes\', preparing_at = NOW() - INTERVAL \'55 minutes\', ready_at = NOW() - INTERVAL \'30 minutes\', picked_up_at = NOW() - INTERVAL \'15 minutes\'' },
    { num: 'LIFECYCLE-006', status: 'DELIVERED', sub: 880, total: 920, prep: 20,
      items: restItems.slice(0, 5).map((i: any, idx: number) => ({ menu_item_id: i.id, name: i.name, quantity: idx < 3 ? 2 : 1, price: Number(i.base_price), size: 'Regular' })),
      addr: '{"address":"Durbar Marg, Kathmandu"}', notes: null, special: null,
      created: '90', ts: 'accepted_at = NOW() - INTERVAL \'85 minutes\', preparing_at = NOW() - INTERVAL \'70 minutes\', ready_at = NOW() - INTERVAL \'45 minutes\', picked_up_at = NOW() - INTERVAL \'30 minutes\', delivered_at = NOW() - INTERVAL \'10 minutes\'' },
  ];

  const dn = (v: string | null) => v ? `'${v}'` : 'NULL';
  const si2 = (v: string | null) => v ? `'${v}'` : 'NULL';

  for (const o of orders) {
    const itemsJson = esc(JSON.stringify(o.items));
    const tsUpdate = o.ts ? `UPDATE public.orders SET ${o.ts}, updated_at = NOW() WHERE order_number = '${o.num}';` : '';
    
    console.log(`INSERT INTO public.orders (user_id, restaurant_id, order_number, status, items, subtotal, delivery_fee, total, delivery_address, delivery_notes, special_instructions, estimated_prep_time, created_at, updated_at) VALUES ('${customer.id}', '${rest.id}', '${o.num}', '${o.status}', '${itemsJson}'::jsonb, ${o.sub}, 40, ${o.total}, '${o.addr}'::jsonb, ${dn(o.notes)}, ${si2(o.special)}, ${o.prep}, NOW() - INTERVAL '${o.created} minutes', NOW());`);
    if (tsUpdate) console.log(tsUpdate);
  }

  // Create a PENDING_RESTAURANT_APPROVAL order (the one we'll progress through the lifecycle)
  const activeItems = restItems.slice(0, 2).map((i: any, idx: number) => ({ menu_item_id: i.id, name: i.name, quantity: idx + 1, price: Number(i.base_price), size: 'Regular' }));
  console.log(`\n-- Extra order for active lifecycle test`);
  console.log(`INSERT INTO public.orders (user_id, restaurant_id, order_number, status, items, subtotal, delivery_fee, total, delivery_address, delivery_notes, special_instructions, estimated_prep_time, created_at, updated_at) VALUES ('${customer.id}', '${rest.id}', 'ACTIVE-LIFECYCLE', 'PENDING_RESTAURANT_APPROVAL', '${esc(JSON.stringify(activeItems))}'::jsonb, 260, 40, 300, '{"address":"Test Location","city":"Kathmandu"}'::jsonb, 'Test order', 'For lifecycle test', 15, NOW(), NOW());`);
  console.log('');

  console.log('-- STEP 4: Verify');
  console.log("SELECT order_number, status, total FROM public.orders WHERE order_number LIKE 'LIFECYCLE-%' OR order_number = 'ACTIVE-LIFECYCLE' ORDER BY order_number;");
  console.log('');
  console.log('-- STEP 5: Refresh schema cache');
  console.log("NOTIFY pgrst, 'reload schema';");
}

main().catch(console.error);
