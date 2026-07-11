/**
 * Orders Table Migration
 *
 * Run this via the Supabase SQL editor or execute locally:
 *   npx ts-node backend/scripts/create_orders_table.ts
 *
 * This creates the `orders` table that stores customer orders,
 * tracking their lifecycle from PENDING → DELIVERED.
 */
import { Client } from 'pg';
import dotenv from 'dotenv';
import * as path from 'path';
dotenv.config({ path: path.join(__dirname, '..', '.env') });

const projectRef = process.env.SUPABASE_URL!.replace('https://', '').replace('.supabase.co', '');
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY!;

const createSQL = `
CREATE TABLE IF NOT EXISTS public.orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  restaurant_id UUID NOT NULL REFERENCES public.restaurant_applications(id) ON DELETE CASCADE,
  order_number TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN (
    'PENDING', 'ACCEPTED', 'PREPARING', 'READY',
    'PICKED_UP', 'DELIVERED', 'CANCELLED', 'REJECTED'
  )),
  items JSONB NOT NULL DEFAULT '[]'::jsonb,
  subtotal DECIMAL(10, 2) NOT NULL DEFAULT 0,
  delivery_fee DECIMAL(10, 2) NOT NULL DEFAULT 0,
  total DECIMAL(10, 2) NOT NULL DEFAULT 0,
  delivery_address JSONB,
  delivery_notes TEXT,
  special_instructions TEXT,
  estimated_prep_time INTEGER,
  delivery_boy_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  assigned_at TIMESTAMPTZ,
  accepted_at TIMESTAMPTZ,
  preparing_at TIMESTAMPTZ,
  ready_at TIMESTAMPTZ,
  picked_up_at TIMESTAMPTZ,
  delivered_at TIMESTAMPTZ,
  cancelled_at TIMESTAMPTZ,
  rejection_reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_orders_restaurant_id ON public.orders(restaurant_id);
CREATE INDEX IF NOT EXISTS idx_orders_user_id ON public.orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_status ON public.orders(status);
CREATE INDEX IF NOT EXISTS idx_orders_restaurant_status ON public.orders(restaurant_id, status);
DROP INDEX IF EXISTS idx_orders_delivery_boy;
CREATE INDEX idx_orders_delivery_boy ON public.orders(delivery_boy_id);

-- Enable Row Level Security
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;

-- (DROP + CREATE used instead of CREATE IF NOT EXISTS — supported on PG 9.6+)

DROP POLICY IF EXISTS "Restaurant owners can view their orders" ON public.orders;
CREATE POLICY "Restaurant owners can view their orders"
  ON public.orders FOR SELECT
  USING (
    restaurant_id IN (
      SELECT id FROM public.restaurant_applications
      WHERE user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Delivery boys can view assigned orders" ON public.orders;
CREATE POLICY "Delivery boys can view assigned orders"
  ON public.orders FOR SELECT
  USING (delivery_boy_id = auth.uid());

DROP POLICY IF EXISTS "Customers can view their own orders" ON public.orders;
CREATE POLICY "Customers can view their own orders"
  ON public.orders FOR SELECT
  USING (user_id = auth.uid());
`;

const connections: { name: string; connString: string }[] = [
  { name: 'direct (port 5432)', connString: `postgresql://postgres:${encodeURIComponent(serviceRoleKey)}@db.${projectRef}.supabase.co:5432/postgres` },
  { name: 'direct (port 6543)', connString: `postgresql://postgres:${encodeURIComponent(serviceRoleKey)}@db.${projectRef}.supabase.co:6543/postgres` },
  { name: 'pooler ap-southeast-1', connString: `postgresql://postgres.${projectRef}:${encodeURIComponent(serviceRoleKey)}@ap-southeast-1.pooler.supabase.com:6543/postgres` },
  { name: 'pooler ap-southeast-2', connString: `postgresql://postgres.${projectRef}:${encodeURIComponent(serviceRoleKey)}@ap-southeast-2.pooler.supabase.com:6543/postgres` },
  { name: 'pooler ap-south-1', connString: `postgresql://postgres.${projectRef}:${encodeURIComponent(serviceRoleKey)}@ap-south-1.pooler.supabase.com:6543/postgres` },
  { name: 'pooler us-east-1', connString: `postgresql://postgres.${projectRef}:${encodeURIComponent(serviceRoleKey)}@us-east-1.pooler.supabase.com:6543/postgres` },
  { name: 'pooler (anon) ap-southeast-1', connString: `postgresql://postgres.${projectRef}:${encodeURIComponent(serviceRoleKey)}@ap-southeast-1.pooler.supabase.com:5432/postgres` },
];

async function tryConnect(conn: { name: string; connString: string }): Promise<boolean> {
  const client = new Client({ connectionString: conn.connString, connectionTimeoutMillis: 6000 });
  try {
    await client.connect();
    console.log(`✅ Connected: ${conn.name}`);

    await client.query(createSQL);
    console.log('   ✅ Orders table created!');

    const { rows } = await client.query(
      `SELECT column_name, data_type, is_nullable 
       FROM information_schema.columns 
       WHERE table_schema = 'public' AND table_name = 'orders'
       ORDER BY ordinal_position`
    );
    console.log('   Columns:');
    rows.forEach((r: any) => console.log(`     - ${r.column_name} (${r.data_type})`));

    await client.end();
    return true;
  } catch (err: any) {
    const msg = err.message || String(err);
    console.log(`❌ ${conn.name}: ${msg.substring(0, 100)}`);
    await client.end().catch(() => {});
    return false;
  }
}

async function main() {
  for (const conn of connections) {
    const ok = await tryConnect(conn);
    if (ok) process.exit(0);
  }
  console.log('\nAll connections failed. Please create the table manually via Supabase SQL editor with:');
  console.log(createSQL);
  process.exit(1);
}

main();
