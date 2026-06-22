/**
 * Check if is_accepting_orders column exists and add it if missing.
 * Uses the existing supabase admin client with WebSocket support.
 *
 * Run: npx ts-node backend/scripts/check_and_add_column.ts
 */
import dotenv from 'dotenv';
import path from 'path';
dotenv.config({ path: path.join(__dirname, '..', '.env') });

import { createClient } from '@supabase/supabase-js';
const WebSocket = require('ws');

const url = process.env.SUPABASE_URL || '';
const key = process.env.SUPABASE_SERVICE_ROLE_KEY || '';

const supabase = createClient(url, key, {
  auth: { autoRefreshToken: false, persistSession: false },
  realtime: { transport: WebSocket },
});

async function main() {
  console.log('Checking restaurant_applications table...');

  // Check if column exists by trying to select it
  const { data: test, error: testError } = await supabase
    .from('restaurant_applications')
    .select('is_accepting_orders')
    .limit(1);

  if (testError) {
    const msg = testError.message?.toLowerCase() || '';
    if (msg.includes('column') && (msg.includes('does not exist') || msg.includes('not found'))) {
      console.log('❌ Column is_accepting_orders does NOT exist. Adding it...');

      // We can't run DDL via PostgREST. Need to use a different approach.
      // Option 1: Use the Management REST API via fetch
      // Option 2: Use a custom RPC function

      const projectRef = url.replace('https://', '').replace('.supabase.co', '');
      const managementApiUrl = `https://api.supabase.com/v1/projects/${projectRef}/database/query`;
      const pat = process.env.SUPABASE_PAT || '';

      if (pat) {
        console.log(`Using Management API for project: ${projectRef}`);
        try {
          const response = await fetch(managementApiUrl, {
            method: 'POST',
            headers: {
              'Authorization': `Bearer ${pat}`,
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({
              query: `ALTER TABLE public.restaurant_applications ADD COLUMN IF NOT EXISTS is_accepting_orders BOOLEAN NOT NULL DEFAULT TRUE;`,
            }),
          });
          const result = await response.json();
          console.log('Management API response:', JSON.stringify(result, null, 2));
        } catch (err: any) {
          console.log('Management API error:', err.message);
          console.log('\n⚠️  To add the column, run this SQL in your Supabase Dashboard SQL Editor:\n');
          console.log('ALTER TABLE public.restaurant_applications');
          console.log('ADD COLUMN IF NOT EXISTS is_accepting_orders BOOLEAN NOT NULL DEFAULT TRUE;');
          console.log();
          process.exit(1);
        }
      } else {
        console.log('\n⚠️  SUPABASE_PAT not set in .env');
        console.log('To add the column, run this SQL in your Supabase Dashboard SQL Editor:\n');
        console.log('ALTER TABLE public.restaurant_applications');
        console.log('ADD COLUMN IF NOT EXISTS is_accepting_orders BOOLEAN NOT NULL DEFAULT TRUE;');
        console.log();
        process.exit(1);
      }
    } else {
      console.log('Error accessing table:', testError.message);
      process.exit(1);
    }
  } else {
    console.log('✅ Column is_accepting_orders already exists!');
    console.log('Sample values:', test);
  }

  // Show current columns
  const { data: sample, error: sampleError } = await supabase
    .from('restaurant_applications')
    .select('*')
    .limit(1);

  if (!sampleError && sample && sample.length > 0) {
    console.log('\nCurrent columns:', Object.keys(sample[0]).join(', '));
  } else if (!sampleError) {
    console.log('\nTable exists but is empty.');
  }

  process.exit(0);
}

main().catch((err) => {
  console.error('Fatal error:', err.message);
  process.exit(1);
});
