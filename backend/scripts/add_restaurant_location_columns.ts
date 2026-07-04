/**
 * Migration: Add latitude/longitude columns to restaurant_applications
 *
 * Run with: npx ts-node backend/scripts/add_restaurant_location_columns.ts
 *
 * This script:
 *   1. Attempts to connect to Supabase using known connection sources
 *      (same pattern as create_orders_table.ts)
 *   2. Executes ALTER TABLE via raw SQL to add latitude & longitude columns
 *   3. Creates an index for spatial queries
 *   4. Verifies the columns were added
 */

import { createClient } from '@supabase/supabase-js';

const MIGRATION_NAME = 'add_restaurant_location_columns';
const migrateSQL = `
  -- Add latitude column
  ALTER TABLE IF EXISTS public.restaurant_applications
    ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION;

  -- Add longitude column
  ALTER TABLE IF EXISTS public.restaurant_applications
    ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION;

  -- Create index for spatial queries
  CREATE INDEX IF NOT EXISTS idx_restaurant_applications_location
    ON public.restaurant_applications (latitude, longitude)
    WHERE latitude IS NOT NULL AND longitude IS NOT NULL;
`;

const verifySQL = `
  SELECT
    column_name,
    data_type,
    is_nullable
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'restaurant_applications'
    AND column_name IN ('latitude', 'longitude');
`;

async function tryConnection(url: string, key: string, label: string): Promise<boolean> {
  if (!url || !key || url === 'YOUR_SUPABASE_URL' || key === 'YOUR_SERVICE_ROLE_KEY') {
    console.log(`  ⤷ Skipping ${label}: not configured`);
    return false;
  }

  const supabase = createClient(url, key);
  const { error } = await supabase.from('restaurant_applications').select('id').limit(1);

  if (error) {
    console.log(`  ⤷ ${label}: connection failed (${error.message})`);
    return false;
  }

  console.log(`  ✅ ${label}: connected`);

  // Run migration
  console.log(`  └─ Running ALTER TABLE ...`);
  const { error: alterError } = await supabase.rpc('exec_sql', { sql: migrateSQL });

  if (alterError) {
    // Fallback: try raw REST query if RPC is not available
    console.log(`  └─ RPC not available, trying direct query...`);
    const { error: directError } = await supabase.from('restaurant_applications').update({
      latitude: null,
      longitude: null,
    }).eq('id', '00000000-0000-0000-0000-000000000000');

    if (directError && directError.message?.includes('does not exist')) {
      console.log(`  ⚠️  Columns might not exist yet. Please run the SQL manually:`);
      console.log(`     ${migrateSQL}`);
      return true;
    }
  }

  // Verify
  console.log(`  └─ Verifying columns...`);
  const { data: columns, error: verifyError } = await supabase
    .from('restaurant_applications')
    .select('latitude, longitude')
    .limit(1);

  if (verifyError) {
    console.log(`  ❌ Verify error: ${verifyError.message}`);
    console.log(`  └─ Columns may not exist. Run the SQL manually if needed.`);
    return true;
  }

  console.log(`  ✅ Migration "${MIGRATION_NAME}" completed successfully.`);
  console.log(`  └─ Columns exist. Sample: latitude=${columns?.[0]?.latitude}, longitude=${columns?.[0]?.longitude}`);
  return true;
}

async function main() {
  console.log(`\n🚀 Running migration: ${MIGRATION_NAME}\n`);

  const connections = [
    { url: process.env.SUPABASE_URL || '', key: process.env.SUPABASE_SERVICE_ROLE_KEY || '', label: 'SUPABASE_URL' },
    { url: process.env.VITE_SUPABASE_URL || '', key: process.env.VITE_SUPABASE_SERVICE_ANON_KEY || '', label: 'VITE_SUPABASE_URL' },
    { url: process.env.NEXT_PUBLIC_SUPABASE_URL || '', key: process.env.SUPABASE_SERVICE_ROLE_KEY || '', label: 'NEXT_PUBLIC_SUPABASE_URL' },
  ];

  for (const conn of connections) {
    const ok = await tryConnection(conn.url, conn.key, conn.label);
    if (ok) return;
  }

  console.log(`\n❌ Could not connect to any Supabase instance.`);
  console.log(`\nTo run this migration manually, copy the SQL from:`);
  console.log(`  backend/scripts/add_restaurant_location_columns.sql`);
  console.log(`\nAnd paste it into the Supabase SQL editor.\n`);
}

main().catch(console.error);
