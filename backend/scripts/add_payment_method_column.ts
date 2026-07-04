/**
 * Migration: Add payment_method column to orders table
 *
 * Run with: npx ts-node scripts/add_payment_method_column.ts
 *
 * Also adds a rider_note column if it doesn't exist yet.
 */
import { supabase } from '../src/db/supabase';

async function migrate() {
  console.log('Running migration: add payment_method column\n');

  // Check if payment_method column exists
  const { data: sample, error: sampleError } = await supabase.admin
    .from('orders')
    .select('payment_method, rider_note')
    .limit(1);

  if (sampleError && sampleError.message.includes('column "payment_method" does not exist')) {
    console.log('❌ payment_method column does not exist. Creating it via raw SQL...');

    // Use pg-query to execute raw SQL. Alternative: we can try inserting a row and catching
    // the error, but that's messy. Let's use the pg client directly.

    // We can't easily do ALTER TABLE via the supabase client. Let's use the RESTful SQL endpoint.
    const supabaseUrl = process.env.SUPABASE_URL!;
    const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY!;

    if (!supabaseUrl || !serviceRoleKey) {
      console.log('SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set in .env');
      console.log('');
      console.log('Please run this SQL in your Supabase dashboard SQL editor:\n');
      console.log("ALTER TABLE IF EXISTS public.orders");
      console.log("  ADD COLUMN IF NOT EXISTS payment_method TEXT NOT NULL DEFAULT 'COD';");
      console.log('');
      console.log("ALTER TABLE IF EXISTS public.orders");
      console.log('  ADD COLUMN IF NOT EXISTS rider_note TEXT;');
      process.exit(1);
    }

    // Try using the Supabase Management API or direct SQL via fetch
    try {
      const response = await fetch(
        `${supabaseUrl}/rest/v1/`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'apikey': serviceRoleKey,
            'Authorization': `Bearer ${serviceRoleKey}`,
            'Prefer': 'params=single-object',
          },
        }
      );
      // This is a generic approach - Supabase REST API doesn't support raw SQL
      // So we'll use the pg module instead
      console.log('Supabase REST API does not support raw ALTER TABLE.');
      console.log('Please run the SQL below manually.\n');
    } catch (e) {
      console.log('Could not connect via REST API.');
    }

    console.log('Run this SQL in your Supabase dashboard SQL Editor:\n');
    console.log('-- ============================================');
    console.log('-- Add payment_method column');
    console.log('-- ============================================');
    console.log("ALTER TABLE IF EXISTS public.orders");
    console.log("  ADD COLUMN IF NOT EXISTS payment_method TEXT NOT NULL DEFAULT 'COD';");
    console.log('');
    console.log('-- ============================================');
    console.log('-- Add rider_note column (if not present)');
    console.log('-- ============================================');
    console.log('ALTER TABLE IF EXISTS public.orders');
    console.log('  ADD COLUMN IF NOT EXISTS rider_note TEXT;');
    console.log('');
    console.log('-- ============================================');
    console.log('-- Verify both columns were added');
    console.log('-- ============================================');
    console.log("SELECT column_name, data_type, is_nullable, column_default");
    console.log("FROM information_schema.columns");
    console.log("WHERE table_schema = 'public' AND table_name = 'orders'");
    console.log("ORDER BY ordinal_position;");
    process.exit(0);
  } else if (!sampleError) {
    console.log('✅ payment_method and rider_note columns already exist!');
    const cols = sample ? Object.keys(sample).join(', ') : '(no rows)';
    console.log(`   Columns accessible: ${cols}`);
  } else if (sampleError) {
    // Some other error — could be table doesn't exist
    console.log('⚠️  Error checking columns:', sampleError.message);
    console.log('Please verify the orders table exists and has the required columns.');
  }

  // Also verify order_items table
  const { data: itemsSample, error: itemsError } = await supabase.admin
    .from('order_items')
    .select('id')
    .limit(1);

  if (itemsError) {
    console.log('\n⚠️  order_items table not found:', itemsError.message);
  } else {
    console.log('✅ order_items table exists.');
  }
}

migrate().catch(console.error);
