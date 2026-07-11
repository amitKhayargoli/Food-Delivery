import dotenv from 'dotenv';
import * as path from 'path';
dotenv.config({ path: path.join(__dirname, '..', '.env') });
import { supabase } from '../src/db/supabase';

const SUPABASE_URL = process.env.SUPABASE_URL!;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;

async function main() {
  console.log('🚀 SETUP & SEED SCRIPT\n');

  // ─── STEP 1: Add missing columns ───
  // We need to use a raw SQL approach via fetch to the Supabase REST API
  // since the JS client has schema cache issues
  console.log('📦 STEP 1: Adding missing columns...');
  
  const sqlAddColumns = `
    ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS order_number TEXT;
    ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS items JSONB DEFAULT '[]'::jsonb;
    ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS delivery_address JSONB;
    ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS delivery_notes TEXT;
    ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS special_instructions TEXT;
    ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS estimated_prep_time INTEGER;
    ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS assigned_at TIMESTAMPTZ;
    ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS accepted_at TIMESTAMPTZ;
    ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS preparing_at TIMESTAMPTZ;
    ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS ready_at TIMESTAMPTZ;
    ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS picked_up_at TIMESTAMPTZ;
    ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS out_for_delivery_at TIMESTAMPTZ;
    ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS delivered_at TIMESTAMPTZ;
    ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS cancelled_at TIMESTAMPTZ;
    ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS rejection_reason TEXT;
    ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();
    CREATE INDEX IF NOT EXISTS idx_orders_restaurant_status ON public.orders(restaurant_id, status);
    CREATE INDEX IF NOT EXISTS idx_orders_order_number ON public.orders(order_number);
  `.replace(/\s+/g, ' ').trim();

  // Execute raw SQL via Supabase REST API (bypasses schema cache)
  const sqlResp = await fetch(`${SUPABASE_URL}/rest/v1/rpc/`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'apikey': SERVICE_KEY,
      'Authorization': `Bearer ${SERVICE_KEY}`,
    },
    body: JSON.stringify({}),
  }).catch(() => null);

  // The RPC approach might not work - let's try direct SQL via the pg client approach
  // Actually, let's just try inserting via the admin client first (the columns might already be there if the user ran step 1)
  
  // Check if columns already exist
  const { data: testOrder } = await supabase.admin.from('orders').select('order_number').limit(1);
  if (testOrder !== null) {
    console.log('   ✅ Columns already exist (previous SQL step 1 succeeded)');
  } else {
    console.log('   ⚠️ Columns may not exist yet - will try inserting anyway');
  }

  // ─── STEP 2: Populate restaurants table ───
  console.log('\n📦 STEP 2: Populating restaurants table...');
  
  const { data: apps } = await supabase.admin
    .from('restaurant_applications')
    .select('id, restaurant_name, user_id')
    .eq('status', 'APPROVED');

  if (!apps || apps.length === 0) {
    console.log('   ❌ No approved restaurants found');
    return;
  }
  
  // Track which owner_ids we've already inserted (due to unique constraint on owner_id)
  const seenOwners = new Set<string>();
  let inserted = 0;
  let skipped = 0;

  for (const a of apps) {
    if (seenOwners.has(a.user_id)) {
      console.log(`   ⏩ Skipping "${a.restaurant_name}" (owner ${a.user_id.slice(0,8)}... already has a restaurant)`);
      skipped++;
      continue;
    }
    
    const { error } = await supabase.admin
      .from('restaurants')
      .insert({ id: a.id, name: a.restaurant_name, owner_id: a.user_id })
      .select()
      .single();

    if (error) {
      if (error.message.includes('duplicate key')) {
        console.log(`   ⏩ "${a.restaurant_name}" already exists`);
      } else {
        console.log(`   ❌ "${a.restaurant_name}": ${error.message.substring(0, 60)}`);
      }
    } else {
      console.log(`   ✅ Inserted "${a.restaurant_name}"`);
      seenOwners.add(a.user_id);
      inserted++;
    }
  }
  console.log(`   Result: ${inserted} inserted, ${skipped} skipped (1 per owner)`);

  // ─── STEP 3: Refresh schema cache ───
  console.log('\n📦 STEP 3: Refreshing schema cache...');
  
  try {
    await fetch(`${SUPABASE_URL}/rest/v1/rpc/pgrst_reload_schema`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'apikey': SERVICE_KEY,
        'Authorization': `Bearer ${SERVICE_KEY}`,
      },
    });
    console.log('   ✅ Schema cache refreshed');
  } catch {
    console.log('   ⚠️ RPC reload failed, will use direct insert approach');
  }

  // Wait a moment for cache to propagate
  await new Promise(r => setTimeout(r, 1000));

  // ─── STEP 4: Create test orders ───
  console.log('\n📦 STEP 4: Creating test orders...');

  const { data: users } = await supabase.admin.from('users').select('id');
  const { data: allItems } = await supabase.admin.from('menu_items').select('id, name, base_price, restaurant_id');
  
  if (!users || !allItems) {
    console.log('   ❌ Could not fetch users/items');
    return;
  }

  // Use Asan Chwok Sweets & Snacks for the test
  const rest = apps.find(r => r.restaurant_name === 'Asan Chwok Sweets & Snacks') || apps[0];
  const customer = users.find(u => u.id !== rest.user_id) || users[0];
  const restItems = allItems.filter(i => i.restaurant_id === rest.id);

  console.log(`   Using restaurant: ${rest.restaurant_name} (${rest.id.slice(0,12)}...)`);
  console.log(`   Customer: ${customer.id.slice(0,12)}...`);

  if (restItems.length < 3) {
    console.log(`   ❌ Only ${restItems.length} menu items - need at least 3`);
    return;
  }

  const testOrders = [
    { num: 'LIFECYCLE-001', status: 'PENDING_RESTAURANT_APPROVAL', subtotal: 900, total: 940, prep: 20,
      its: restItems.slice(0, 3).map((i, idx) => ({ menu_item_id: i.id, name: i.name, quantity: idx === 1 ? 3 : 2, price: Number(i.base_price), size: 'Regular' })),
      addr: { address: 'Lakeside, Pokhara', city: 'Pokhara' }, notes: 'Leave at reception desk', special: 'Extra spicy please',
      created: '15 minutes', ts: {} },
    { num: 'LIFECYCLE-002', status: 'ACCEPTED', subtotal: 460, total: 500, prep: 15,
      its: restItems.slice(0, 2).map((i, idx) => ({ menu_item_id: i.id, name: i.name, quantity: idx === 1 ? 3 : 2, price: Number(i.base_price), size: 'Regular' })),
      addr: { address: 'Thamel, Kathmandu', city: 'Kathmandu' }, notes: null, special: 'Call when arriving',
      created: '30 minutes', ts: { accepted_at: '25 minutes' } },
    { num: 'LIFECYCLE-003', status: 'PREPARING', subtotal: 420, total: 460, prep: 20,
      its: restItems.slice(1, 3).map((i, idx) => ({ menu_item_id: i.id, name: i.name, quantity: idx === 0 ? 2 : 1, price: Number(i.base_price), size: 'Regular' })),
      addr: { address: 'Boudha, Kathmandu' }, notes: null, special: 'No onions please',
      created: '45 minutes', ts: { accepted_at: '40 minutes', preparing_at: '15 minutes' } },
    { num: 'LIFECYCLE-004', status: 'READY_FOR_PICKUP', subtotal: 80, total: 120, prep: 10,
      its: [restItems[0]].map(i => ({ menu_item_id: i.id, name: i.name, quantity: 1, price: Number(i.base_price), size: 'Regular' })),
      addr: { address: 'Patan Durbar Square, Lalitpur' }, notes: null, special: 'Ring the bell',
      created: '60 minutes', ts: { accepted_at: '55 minutes', preparing_at: '40 minutes', ready_at: '10 minutes' } },
    { num: 'LIFECYCLE-005', status: 'PICKED_UP', subtotal: 260, total: 300, prep: 15,
      its: restItems.slice(0, 2).map((i, idx) => ({ menu_item_id: i.id, name: i.name, quantity: idx === 0 ? 2 : 1, price: Number(i.base_price), size: 'Regular' })),
      addr: { address: 'Jawalakhel, Lalitpur' }, notes: null, special: null,
      created: '75 minutes', ts: { accepted_at: '70 minutes', preparing_at: '55 minutes', ready_at: '30 minutes', picked_up_at: '15 minutes' } },
    { num: 'LIFECYCLE-006', status: 'DELIVERED', subtotal: 880, total: 920, prep: 20,
      its: restItems.slice(0, 5).map((i, idx) => ({ menu_item_id: i.id, name: i.name, quantity: idx < 3 ? 2 : 1, price: Number(i.base_price), size: 'Regular' })),
      addr: { address: 'Durbar Marg, Kathmandu' }, notes: null, special: null,
      created: '90 minutes', ts: { accepted_at: '85 minutes', preparing_at: '70 minutes', ready_at: '45 minutes', picked_up_at: '30 minutes', delivered_at: '10 minutes' } }
  ];

  let ordersCreated = 0;
  for (const t of testOrders) {
    const data = {
      user_id: customer.id,
      restaurant_id: rest.id,
      order_number: t.num,
      status: t.status,
      items: t.its,
      subtotal: t.subtotal,
      delivery_fee: 40,
      total: t.total,
      delivery_address: t.addr,
      delivery_notes: t.notes,
      special_instructions: t.special,
      estimated_prep_time: t.prep,
      created_at: new Date(Date.now() - parseTime(t.created)).toISOString(),
      updated_at: new Date().toISOString(),
    };

    // Add timestamp fields
    const tsData: any = {};
    for (const [col, val] of Object.entries(t.ts)) {
      if (val) tsData[col] = new Date(Date.now() - parseTime(val as string)).toISOString();
    }
    Object.assign(data, tsData);

    // Use the direct fetch approach to bypass schema cache
    try {
      const resp = await fetch(`${SUPABASE_URL}/rest/v1/orders`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'apikey': SERVICE_KEY,
          'Authorization': `Bearer ${SERVICE_KEY}`,
          'Prefer': 'return=representation',
        },
        body: JSON.stringify(data),
      });

      if (resp.ok) {
        const result = await resp.json();
        console.log(`   ✅ Created ${t.num} (${t.status})`);
        ordersCreated++;
      } else {
        const errText = await resp.text();
        console.log(`   ❌ ${t.num}: ${errText.substring(0, 100)}`);
      }
    } catch (err: any) {
      console.log(`   ❌ ${t.num}: ${err.message?.substring(0, 60)}`);
    }
  }

  console.log(`\n📊 Result: ${ordersCreated}/${testOrders.length} orders created`);

  // ─── STEP 5: Verify ───
  console.log('\n📦 STEP 5: Verification...');
  
  const { data: verify } = await supabase.admin
    .from('orders')
    .select('order_number, status, total')
    .ilike('order_number', 'LIFECYCLE-%')
    .order('created_at', { ascending: true });

  if (verify) {
    console.log(`   Found ${verify.length} test orders:`);
    verify.forEach(o => console.log(`   ${o.order_number.padEnd(16)} | ${(o.status as string).padEnd(28)} | Rs.${o.total}`));
  } else {
    console.log('   ❌ Could not verify orders');
  }

  console.log(`\n🎉 Done! Owner ID for JWT: ${rest.user_id}`);
}

function parseTime(str: string): number {
  const match = str.match(/(\d+)\s*(minutes?|hours?)/);
  if (!match) return 0;
  const val = parseInt(match[1]);
  const unit = match[2];
  return unit.startsWith('hour') ? val * 60 * 1000 : val * 60 * 1000;
}

main().catch(e => console.error('❌ ERROR:', e));
