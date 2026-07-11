/**
 * Coupons & Promotions Table Migration
 *
 * Creates the coupons table for:
 *   - Restaurant owner-specific coupons
 *   - Admin global coupons (restaurant_id = NULL)
 *
 * Run via Supabase SQL editor or:
 *   npx ts-node scripts/create_coupons_table.ts
 */
const createSQL = `
CREATE TABLE IF NOT EXISTS public.coupons (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Coupon code (uppercase, unique across all coupons)
  code TEXT NOT NULL UNIQUE,

  -- Discount type: 'PERCENTAGE' or 'FIXED'
  discount_type TEXT NOT NULL CHECK (discount_type IN ('PERCENTAGE', 'FIXED')),

  -- Discount value: e.g. 20 for 20% or 100 for Rs. 100 off
  discount_value DECIMAL(10, 2) NOT NULL CHECK (discount_value > 0),

  -- Minimum order amount required to use this coupon (nullable)
  min_order_amount DECIMAL(10, 2),

  -- Maximum discount cap for percentage coupons (e.g. max Rs. 200 off)
  max_discount_cap DECIMAL(10, 2),

  -- Usage limit: max times this coupon can be used overall (nullable = unlimited)
  usage_limit INTEGER,

  -- How many times it has been used so far
  used_count INTEGER NOT NULL DEFAULT 0,

  -- NULL = global coupon (admin created, works everywhere)
  -- Non-NULL = restaurant-specific coupon
  restaurant_id UUID REFERENCES public.restaurant_applications(id) ON DELETE CASCADE,

  -- Expiry and status
  expires_at TIMESTAMPTZ,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,

  -- Metadata
  description TEXT,
  created_by UUID REFERENCES public.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_coupons_code ON public.coupons(code);
CREATE INDEX IF NOT EXISTS idx_coupons_restaurant_id ON public.coupons(restaurant_id);
CREATE INDEX IF NOT EXISTS idx_coupons_active ON public.coupons(is_active) WHERE is_active = TRUE;

-- Enable Row Level Security
ALTER TABLE public.coupons ENABLE ROW LEVEL SECURITY;

-- Restaurant owners can manage their own coupons
DROP POLICY IF EXISTS "Owners can manage their restaurant coupons" ON public.coupons;
CREATE POLICY "Owners can manage their restaurant coupons"
  ON public.coupons FOR ALL
  USING (
    restaurant_id IN (
      SELECT id FROM public.restaurant_applications
      WHERE user_id = auth.uid()
    )
  );

-- Admins can manage all coupons
DROP POLICY IF EXISTS "Admins can manage all coupons" ON public.coupons;
CREATE POLICY "Admins can manage all coupons"
  ON public.coupons FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid() AND role = 'ADMIN'
    )
  );

-- Anyone can read active, non-expired global coupons for display
DROP POLICY IF EXISTS "Anyone can view active coupons" ON public.coupons;
CREATE POLICY "Anyone can view active coupons"
  ON public.coupons FOR SELECT
  USING (is_active = TRUE AND (expires_at IS NULL OR expires_at > NOW()));
`;

async function main() {
  console.log('Migration: coupons table\n');
  console.log('Run the following SQL in your Supabase SQL editor:\n');
  console.log(createSQL);
  console.log('\n---\nOr connect directly:\n');
  console.log('  npx ts-node scripts/create_coupons_table.ts\n');

  // Attempt direct connection if env vars are available
  const dotenv = await import('dotenv');
  const path = await import('path');
  dotenv.default.config({ path: path.default.join(__dirname, '..', '.env') });

  const projectRef = process.env.SUPABASE_URL?.replace('https://', '').replace('.supabase.co', '');
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!projectRef || !serviceRoleKey) {
    console.log('SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY not set — skipping direct connection.');
    return;
  }

  const { Client } = await import('pg');
  const connString = `postgresql://postgres:${encodeURIComponent(serviceRoleKey)}@db.${projectRef}.supabase.co:5432/postgres`;

  const client = new Client({ connectionString: connString, connectionTimeoutMillis: 6000 });
  try {
    await client.connect();
    console.log('✅ Connected to DB');
    await client.query(createSQL);
    console.log('✅ Coupons table created!');

    const { rows } = await client.query(
      `SELECT column_name, data_type, is_nullable
       FROM information_schema.columns
       WHERE table_schema = 'public' AND table_name = 'coupons'
       ORDER BY ordinal_position`
    );
    console.log('\nColumns:');
    rows.forEach((r: any) => console.log(`  - ${r.column_name} (${r.data_type})`));

    await client.end();
    process.exit(0);
  } catch (err: any) {
    console.error('❌ Connection/query error:', err.message?.substring(0, 120));
    console.log('\nPlease run the SQL manually in Supabase SQL editor.');
    process.exit(1);
  }
}

main();
