import dotenv from 'dotenv';
import * as path from 'path';
dotenv.config({ path: path.join(__dirname, '..', '.env') });

import { supabase } from '../src/db/supabase';

function esc(s: string) { return s.replace(/'/g, "''"); }

async function main() {
  const { data: users } = await supabase.admin.from('users').select('id, username, role');
  const { data: rests } = await supabase.admin.from('restaurant_applications').select('id, restaurant_name, user_id').eq('status', 'APPROVED');
  const { data: items } = await supabase.admin.from('menu_items').select('id, name, base_price, restaurant_id');

  if (!users || !rests || !items) { console.log('ERROR: missing data'); return; }

  const rest = rests.find(r => r.restaurant_name === 'Asan Chwok Sweets & Snacks') || rests[0];
  const customer = users.find(u => u.id !== rest.user_id) || users[0];
  const restItems = items.filter(i => i.restaurant_id === rest.id);

  const testOrders = [
    { num: 'LIFECYCLE-001', status: 'PENDING_RESTAURANT_APPROVAL', subtotal: 900, total: 940, prep: 20,
      its: restItems.slice(0, 3).map((i, idx) => ({ menu_item_id: i.id, name: i.name, quantity: idx === 1 ? 3 : 2, price: Number(i.base_price), size: 'Regular' })),
      addr: { address: 'Lakeside, Pokhara', city: 'Pokhara' }, notes: 'Leave at reception desk', special: 'Extra spicy please',
      created: '15', ts: {} },
    { num: 'LIFECYCLE-002', status: 'ACCEPTED', subtotal: 460, total: 500, prep: 15,
      its: restItems.slice(0, 2).map((i, idx) => ({ menu_item_id: i.id, name: i.name, quantity: idx === 1 ? 3 : 2, price: Number(i.base_price), size: 'Regular' })),
      addr: { address: 'Thamel, Kathmandu', city: 'Kathmandu' }, notes: null, special: 'Call when arriving',
      created: '30', ts: { accepted_at: '25' } },
    { num: 'LIFECYCLE-003', status: 'PREPARING', subtotal: 420, total: 460, prep: 20,
      its: restItems.slice(1, 3).map((i, idx) => ({ menu_item_id: i.id, name: i.name, quantity: idx === 0 ? 2 : 1, price: Number(i.base_price), size: 'Regular' })),
      addr: { address: 'Boudha, Kathmandu', city: 'Kathmandu' }, notes: null, special: 'No onions please',
      created: '45', ts: { accepted_at: '40', preparing_at: '15' } },
    { num: 'LIFECYCLE-004', status: 'READY_FOR_PICKUP', subtotal: 80, total: 120, prep: 10,
      its: [restItems[0]].map(i => ({ menu_item_id: i.id, name: i.name, quantity: 1, price: Number(i.base_price), size: 'Regular' })),
      addr: { address: 'Patan Durbar Square, Lalitpur', city: 'Lalitpur' }, notes: null, special: 'Ring the bell',
      created: '60', ts: { accepted_at: '55', preparing_at: '40', ready_at: '10' } },
    { num: 'LIFECYCLE-005', status: 'PICKED_UP', subtotal: 260, total: 300, prep: 15,
      its: restItems.slice(0, 2).map((i, idx) => ({ menu_item_id: i.id, name: i.name, quantity: idx === 0 ? 2 : 1, price: Number(i.base_price), size: 'Regular' })),
      addr: { address: 'Jawalakhel, Lalitpur', city: 'Lalitpur' }, notes: null, special: null,
      created: '75', ts: { accepted_at: '70', preparing_at: '55', ready_at: '30', picked_up_at: '15' } },
    { num: 'LIFECYCLE-006', status: 'DELIVERED', subtotal: 880, total: 920, prep: 20,
      its: restItems.slice(0, 5).map((i, idx) => ({ menu_item_id: i.id, name: i.name, quantity: idx < 3 ? 2 : 1, price: Number(i.base_price), size: 'Regular' })),
      addr: { address: 'Durbar Marg, Kathmandu', city: 'Kathmandu' }, notes: null, special: null,
      created: '90', ts: { accepted_at: '85', preparing_at: '70', ready_at: '45', picked_up_at: '30', delivered_at: '10' } }
  ];

  console.log('-- STEP 1: Add missing columns');
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

  console.log('-- STEP 2: Insert test orders');
  for (const t of testOrders) {
    const its = esc(JSON.stringify(t.its));
    const addr = esc(JSON.stringify(t.addr));
    const notes = t.notes ? `'${t.notes}'` : 'NULL';
    const special = t.special ? `'${t.special}'` : 'NULL';
    console.log(`INSERT INTO public.orders (user_id, restaurant_id, order_number, status, items, subtotal, delivery_fee, total, delivery_address, delivery_notes, special_instructions, estimated_prep_time, created_at, updated_at) VALUES ('${customer.id}', '${rest.id}', '${t.num}', '${t.status}', '${its}'::jsonb, ${t.subtotal}, 40, ${t.total}, '${addr}'::jsonb, ${notes}, ${special}, ${t.prep}, NOW() - INTERVAL '${t.created} minutes', NOW());`);
  }
  console.log('');

  console.log('-- STEP 3: Set timestamps');
  for (const t of testOrders) {
    const updates = Object.entries(t.ts)
      .filter(([_, v]) => v !== undefined)
      .map(([col, val]) => `${col} = NOW() - INTERVAL '${val} minutes'`)
      .join(', ');
    if (updates) console.log(`UPDATE public.orders SET ${updates} WHERE order_number = '${t.num}';`);
  }
  console.log('');

  console.log('-- STEP 4: Refresh schema cache');
  console.log("NOTIFY pgrst, 'reload schema';");
  console.log('');

  console.log('-- STEP 5: Verify');
  console.log("SELECT order_number, status, total FROM public.orders WHERE order_number LIKE 'LIFECYCLE-%' ORDER BY order_number;");

  console.log(`\n-- Owner ID (for JWT): ${rest.user_id}`);
  console.log(`-- Restaurant ID: ${rest.id}`);
  console.log(`-- Owner username: ${users.find(u => u.id === rest.user_id)?.username}`);
}

main().catch(e => console.error('ERROR:', e));
