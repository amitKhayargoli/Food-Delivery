import dotenv from 'dotenv';
import * as path from 'path';
dotenv.config({ path: path.join(__dirname, '..', '.env') });
import { supabase } from '../src/db/supabase';

function esc(s: string) { return s.replace(/'/g, "''"); }

async function main() {
  console.log('-- ============================================');
  console.log('-- EXPAND RESTAURANTS TABLE + SYNC DATA');
  console.log('-- ============================================\n');

  // Add columns
  const cols = [
    'cover_image_url TEXT',
    'logo_url TEXT',
    'description TEXT',
    'cuisine_type TEXT',
    'address TEXT',
    'is_accepting_orders BOOLEAN DEFAULT TRUE',
    'open_time TEXT',
    'close_time TEXT',
    'phone TEXT',
    'email TEXT',
    'rating DECIMAL(3,1) DEFAULT 4.5',
    'delivery_time_minutes INTEGER DEFAULT 30',
    'updated_at TIMESTAMPTZ DEFAULT NOW()',
  ];

  for (const col of cols) {
    console.log(`ALTER TABLE public.restaurants ADD COLUMN IF NOT EXISTS ${col};`);
  }
  console.log('');

  // Fetch data from restaurant_applications
  const { data: apps } = await supabase.admin
    .from('restaurant_applications')
    .select('id, restaurant_name, description, logo_url, cover_image_url, cuisine_type, address, is_accepting_orders, open_time, close_time, phone, email')
    .eq('status', 'APPROVED');

  if (!apps || apps.length === 0) {
    console.log('-- No approved restaurants found to sync');
    return;
  }

  console.log('-- Sync data from restaurant_applications to restaurants');
  for (const a of apps) {
    const name = esc(a.restaurant_name || '');
    const desc = a.description ? `'${esc(a.description)}'` : 'NULL';
    const logo = a.logo_url ? `'${esc(a.logo_url)}'` : 'NULL';
    const cover = a.cover_image_url ? `'${esc(a.cover_image_url)}'` : 'NULL';
    const cuisine = a.cuisine_type ? `'${esc(a.cuisine_type)}'` : 'NULL';
    const addr = a.address ? `'${esc(a.address)}'` : 'NULL';
    const accepting = a.is_accepting_orders ?? true;
    const ot = a.open_time ? `'${esc(a.open_time)}'` : 'NULL';
    const ct = a.close_time ? `'${esc(a.close_time)}'` : 'NULL';
    const phone = a.phone ? `'${esc(a.phone)}'` : 'NULL';
    const email = a.email ? `'${esc(a.email)}'` : 'NULL';

    console.log(
      `UPDATE public.restaurants SET ` +
      `description = ${desc}, ` +
      `logo_url = ${logo}, ` +
      `cover_image_url = ${cover}, ` +
      `cuisine_type = ${cuisine}, ` +
      `address = ${addr}, ` +
      `is_accepting_orders = ${accepting}, ` +
      `open_time = ${ot}, ` +
      `close_time = ${ct}, ` +
      `phone = ${phone}, ` +
      `email = ${email}, ` +
      `updated_at = NOW() ` +
      `WHERE id = '${a.id}';`
    );
  }

  // Set default rating for restaurants without one
  console.log("\n-- Set default values for any restaurants not in restaurant_applications");
  console.log("UPDATE public.restaurants SET rating = 4.5, delivery_time_minutes = 30, is_accepting_orders = TRUE WHERE rating IS NULL;");

  console.log('\n-- Verify');
  console.log('SELECT id, name, cover_image_url, cuisine_type, is_accepting_orders FROM public.restaurants ORDER BY name;');

  console.log('\n-- Refresh schema cache');
  console.log("NOTIFY pgrst, 'reload schema';");
}

main().catch(console.error);
