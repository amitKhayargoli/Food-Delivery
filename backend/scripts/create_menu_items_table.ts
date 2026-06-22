/**
 * Menu Items Table Migration
 *
 * Run this via the Supabase SQL editor or execute locally:
 *   npx ts-node backend/scripts/create_menu_items_table.ts
 *
 * This creates the `menu_items` table that stores food items for each restaurant,
 * supporting multi-image, size variants, nutrition info, and ingredients.
 */
import { Client } from 'pg';
import dotenv from 'dotenv';
import * as path from 'path';
dotenv.config({ path: path.join(__dirname, '..', '.env') });

const projectRef = process.env.SUPABASE_URL!.replace('https://', '').replace('.supabase.co', '');
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY!;

const createSQL = `
CREATE TABLE IF NOT EXISTS public.menu_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id UUID NOT NULL REFERENCES public.restaurant_applications(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  base_price DECIMAL(10, 2) NOT NULL DEFAULT 0,
  category TEXT,
  is_available BOOLEAN NOT NULL DEFAULT TRUE,
  
  -- Multi-image support (US-15: minimum 3 photos per item)
  images TEXT[] NOT NULL DEFAULT '{}',
  
  -- Nutrition info (US-16)
  calories INTEGER,
  portion_weight TEXT,
  allergens TEXT[] DEFAULT '{}',
  
  -- Ingredients
  ingredients TEXT[] DEFAULT '{}',
  
  -- Size variants (JSONB array)
  sizes JSONB DEFAULT '[]'::jsonb,
  
  -- Preparation time in minutes
  prep_time INTEGER,
  
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_menu_items_restaurant_id ON public.menu_items(restaurant_id);
CREATE INDEX IF NOT EXISTS idx_menu_items_category ON public.menu_items(category);
CREATE INDEX IF NOT EXISTS idx_menu_items_available ON public.menu_items(is_available);

-- Enable Row Level Security
ALTER TABLE public.menu_items ENABLE ROW LEVEL SECURITY;

-- Restaurant owners can manage their own menu items
DROP POLICY IF EXISTS "Restaurant owners can manage their menu" ON public.menu_items;
CREATE POLICY "Restaurant owners can manage their menu"
  ON public.menu_items FOR ALL
  USING (
    restaurant_id IN (
      SELECT id FROM public.restaurant_applications
      WHERE user_id = auth.uid()
    )
  );

-- Everyone can read available menu items
DROP POLICY IF EXISTS "Anyone can view available menu items" ON public.menu_items;
CREATE POLICY "Anyone can view available menu items"
  ON public.menu_items FOR SELECT
  USING (is_available = TRUE OR restaurant_id IN (
    SELECT id FROM public.restaurant_applications
    WHERE user_id = auth.uid()
  ));
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
    console.log('   ✅ Menu items table created!');

    const { rows } = await client.query(
      `SELECT column_name, data_type, is_nullable 
       FROM information_schema.columns 
       WHERE table_schema = 'public' AND table_name = 'menu_items'
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
