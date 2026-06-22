import { Client } from 'pg';
import dotenv from 'dotenv';
import * as path from 'path';
dotenv.config({ path: path.join(__dirname, '..', '.env') });

const projectRef = process.env.SUPABASE_URL!.replace('https://', '').replace('.supabase.co', '');
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY!;

const connections = [
  { name: 'direct (port 5432)', connString: `postgresql://postgres:${encodeURIComponent(serviceRoleKey)}@db.${projectRef}.supabase.co:5432/postgres` },
  { name: 'direct (port 6543)', connString: `postgresql://postgres:${encodeURIComponent(serviceRoleKey)}@db.${projectRef}.supabase.co:6543/postgres` },
  { name: 'pooler ap-southeast-1', connString: `postgresql://postgres.${projectRef}:${encodeURIComponent(serviceRoleKey)}@ap-southeast-1.pooler.supabase.com:6543/postgres` },
  { name: 'pooler ap-southeast-2', connString: `postgresql://postgres.${projectRef}:${encodeURIComponent(serviceRoleKey)}@ap-southeast-2.pooler.supabase.com:6543/postgres` },
  { name: 'pooler ap-south-1', connString: `postgresql://postgres.${projectRef}:${encodeURIComponent(serviceRoleKey)}@ap-south-1.pooler.supabase.com:6543/postgres` },
  { name: 'pooler us-east-1', connString: `postgresql://postgres.${projectRef}:${encodeURIComponent(serviceRoleKey)}@us-east-1.pooler.supabase.com:6543/postgres` },
  { name: 'pooler anon ap-southeast-1', connString: `postgresql://postgres.${projectRef}:${encodeURIComponent(serviceRoleKey)}@ap-southeast-1.pooler.supabase.com:5432/postgres` },
  { name: 'pooler ap-southeast-1 no SSL', connString: `postgresql://postgres.${projectRef}:${encodeURIComponent(serviceRoleKey)}@ap-southeast-1.pooler.supabase.com:6543/postgres` },
  { name: 'pooler ap-southeast-1 port 5432 anon', connString: `postgresql://postgres.${projectRef}:${encodeURIComponent(serviceRoleKey)}@ap-southeast-1.pooler.supabase.com:5432/postgres` },
  { name: 'transaction pooler', connString: `postgresql://postgres.${projectRef}:${encodeURIComponent(serviceRoleKey)}@aws-0-ap-southeast-1.pooler.supabase.com:6543/postgres` },
];

async function tryConnect(conn: { name: string; connString: string }): Promise<boolean> {
  const client = new Client({ connectionString: conn.connString, connectionTimeoutMillis: 8000 });
  try {
    await client.connect();
    console.log(`✅ Connected: ${conn.name}`);

    // ─── STEP 1: Add columns ───
    console.log('\n📦 STEP 1: Adding columns...');
    const alterSQL = `
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
    `;
    await client.query(alterSQL);
    console.log('   ✅ All columns added');

    // ─── STEP 2: Populate restaurants ───
    console.log('\n📦 STEP 2: Populating restaurants table...');
    
    const { rows: apps } = await client.query(
      `SELECT id, restaurant_name, user_id FROM public.restaurant_applications WHERE status = 'APPROVED'`
    );

    // Insert one per owner due to unique constraint on owner_id
    const seenOwners = new Set<string>();
    for (const a of apps) {
      if (seenOwners.has(a.user_id)) {
        console.log(`   ⏩ Skipping "${a.restaurant_name}" (owner already has a restaurant)`);
        continue;
      }
      await client.query(
        `INSERT INTO public.restaurants (id, name, owner_id) VALUES ($1, $2, $3) ON CONFLICT (id) DO NOTHING`,
        [a.id, a.restaurant_name, a.user_id]
      );
      console.log(`   ✅ "${a.restaurant_name}"`);
      seenOwners.add(a.user_id);
    }

    // ─── STEP 3: Get data for test orders ───
    console.log('\n📦 STEP 3: Preparing test orders...');

    const { rows: users } = await client.query(`SELECT id FROM public.users LIMIT 10`);
    const rest = apps[0]; // Asan Chwok Sweets & Snacks
    const customer = users.find((u: any) => u.id !== rest.user_id) || users[0];

    const { rows: allItems } = await client.query(
      `SELECT id, name, base_price FROM public.menu_items WHERE restaurant_id = $1`,
      [rest.id]
    );

    console.log(`   Restaurant: ${rest.restaurant_name} (${rest.id})`);
    console.log(`   Customer: ${customer.id}`);
    console.log(`   Menu items: ${allItems.length}`);

    // ─── STEP 4: Insert orders ───
    console.log('\n📦 STEP 4: Creating 6 test orders...');

    const testOrders = [
      { num: 'LIFECYCLE-001', status: 'PENDING_RESTAURANT_APPROVAL', subtotal: 900, total: 940, prep: 20,
        its: (() => {
          const items = allItems.slice(0, 3);
          return items.map((i: any, idx: number) => ({ menu_item_id: i.id, name: i.name, quantity: idx === 1 ? 3 : 2, price: Number(i.base_price), size: 'Regular' }));
        })(),
        addr: JSON.stringify({ address: 'Lakeside, Pokhara', city: 'Pokhara' }), notes: 'Leave at reception desk', special: 'Extra spicy please',
        created: '15 minutes', ts: {} },
      { num: 'LIFECYCLE-002', status: 'ACCEPTED', subtotal: 460, total: 500, prep: 15,
        its: (() => {
          const items = allItems.slice(0, 2);
          return items.map((i: any, idx: number) => ({ menu_item_id: i.id, name: i.name, quantity: idx === 1 ? 3 : 2, price: Number(i.base_price), size: 'Regular' }));
        })(),
        addr: JSON.stringify({ address: 'Thamel, Kathmandu', city: 'Kathmandu' }), notes: null, special: 'Call when arriving',
        created: '30 minutes', ts: { accepted_at: '25 minutes' } },
      { num: 'LIFECYCLE-003', status: 'PREPARING', subtotal: 420, total: 460, prep: 20,
        its: (() => {
          const items = allItems.slice(1, 3);
          return items.map((i: any, idx: number) => ({ menu_item_id: i.id, name: i.name, quantity: idx === 0 ? 2 : 1, price: Number(i.base_price), size: 'Regular' }));
        })(),
        addr: JSON.stringify({ address: 'Boudha, Kathmandu', city: 'Kathmandu' }), notes: null, special: 'No onions please',
        created: '45 minutes', ts: { accepted_at: '40 minutes', preparing_at: '15 minutes' } },
      { num: 'LIFECYCLE-004', status: 'READY_FOR_PICKUP', subtotal: 80, total: 120, prep: 10,
        its: [(() => { const i = allItems[0]; return { menu_item_id: i.id, name: i.name, quantity: 1, price: Number(i.base_price), size: 'Regular' }; })()],
        addr: JSON.stringify({ address: 'Patan Durbar Square, Lalitpur', city: 'Lalitpur' }), notes: null, special: 'Ring the bell',
        created: '60 minutes', ts: { accepted_at: '55 minutes', preparing_at: '40 minutes', ready_at: '10 minutes' } },
      { num: 'LIFECYCLE-005', status: 'PICKED_UP', subtotal: 260, total: 300, prep: 15,
        its: (() => {
          const items = allItems.slice(0, 2);
          return items.map((i: any, idx: number) => ({ menu_item_id: i.id, name: i.name, quantity: idx === 0 ? 2 : 1, price: Number(i.base_price), size: 'Regular' }));
        })(),
        addr: JSON.stringify({ address: 'Jawalakhel, Lalitpur', city: 'Lalitpur' }), notes: null, special: null,
        created: '75 minutes', ts: { accepted_at: '70 minutes', preparing_at: '55 minutes', ready_at: '30 minutes', picked_up_at: '15 minutes' } },
      { num: 'LIFECYCLE-006', status: 'DELIVERED', subtotal: 880, total: 920, prep: 20,
        its: (() => {
          const items = allItems.slice(0, 5);
          return items.map((i: any, idx: number) => ({ menu_item_id: i.id, name: i.name, quantity: idx < 3 ? 2 : 1, price: Number(i.base_price), size: 'Regular' }));
        })(),
        addr: JSON.stringify({ address: 'Durbar Marg, Kathmandu', city: 'Kathmandu' }), notes: null, special: null,
        created: '90 minutes', ts: { accepted_at: '85 minutes', preparing_at: '70 minutes', ready_at: '45 minutes', picked_up_at: '30 minutes', delivered_at: '10 minutes' } }
    ];

    const parseTime = (str: string): number => {
      const m = str.match(/(\d+)\s*(minutes?|hours?)/);
      if (!m) return 0;
      return parseInt(m[1]) * 60 * 1000;
    };

    for (const t of testOrders) {
      const now = Date.now();
      const created = new Date(now - parseTime(t.created)).toISOString();
      const updated = new Date().toISOString();

      // Build timestamp columns
      const tsCols: string[] = [];
      const tsVals: any[] = [];
      for (const [col, val] of Object.entries(t.ts)) {
        if (val) {
          tsCols.push(col);
          tsVals.push(new Date(now - parseTime(val as string)).toISOString());
        }
      }

      const itemsJson = JSON.stringify(t.its);
      const tsColStr = tsCols.length > 0 ? ', ' + tsCols.map((_, i) => `$${9 + i}`).join(', ') : '';
      const tsColNames = tsCols.length > 0 ? ', ' + tsCols.join(', ') : '';

      const sql = `INSERT INTO public.orders (user_id, restaurant_id, order_number, status, items, subtotal, delivery_fee, total, delivery_address, delivery_notes, special_instructions, estimated_prep_time, created_at, updated_at${tsColNames})
        VALUES ($1, $2, $3, $4, $5::jsonb, $6, $7, $8, $9::jsonb, $10, $11, $12, $13, $14${tsColStr.length > 0 ? ', ' + tsVals.map((_, i) => `$${15 + i}`).join(', ') : ''})`;

      const params = [
        customer.id, rest.id, t.num, t.status, itemsJson,
        t.subtotal, 40, t.total, t.addr, t.notes, t.special,
        t.prep, created, updated, ...tsVals
      ];

      try {
        await client.query(sql, params);
        console.log(`   ✅ ${t.num} (${t.status}) - Rs.${t.total}`);
      } catch (err: any) {
        console.log(`   ❌ ${t.num}: ${err.message.substring(0, 100)}`);
      }
    }

    // ─── STEP 5: Verify ───
    console.log('\n📦 STEP 5: Verification...');
    const { rows: verify } = await client.query(
      `SELECT order_number, status, total, created_at FROM public.orders WHERE order_number LIKE 'LIFECYCLE-%' ORDER BY order_number`
    );

    if (verify.length > 0) {
      console.log(`   ✅ ${verify.length} test orders:`);
      verify.forEach((o: any) => console.log(`      ${o.order_number.padEnd(16)} | ${o.status.padEnd(28)} | Rs.${o.total}`));
    } else {
      console.log('   ❌ No test orders found');
    }

    // ─── STEP 6: Refresh schema cache ───
    console.log('\n📦 STEP 6: Refreshing PostgREST schema cache...');
    await client.query(`NOTIFY pgrst, 'reload schema'`);
    console.log('   ✅ Schema cache notified');

    await client.end();
    console.log(`\n🎉 DONE!`);
    console.log(`   Owner ID for JWT: ${rest.user_id}`);
    console.log(`   Restaurant ID: ${rest.id}`);
    return true;
  } catch (err: any) {
    console.log(`❌ ${conn.name}: ${err.message?.substring(0, 120)}`);
    await client.end().catch(() => {});
    return false;
  }
}

async function main() {
  for (const conn of connections) {
    const ok = await tryConnect(conn);
    if (ok) process.exit(0);
  }
  console.log('\n❌ All connections failed. The Supabase project might have connection pooling restrictions.');
  process.exit(1);
}

main();
