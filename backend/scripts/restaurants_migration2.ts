import dotenv from 'dotenv';
import * as path from 'path';
dotenv.config({ path: path.join(__dirname, '..', '.env') });
import { supabase } from '../src/db/supabase';

function esc(s: string) { return (s || '').replace(/'/g, "''"); }

async function main() {
  console.log('-- STEP 1: Add columns to restaurants table');
  console.log('ALTER TABLE public.restaurants ADD COLUMN IF NOT EXISTS cover_image_url TEXT;');
  console.log('ALTER TABLE public.restaurants ADD COLUMN IF NOT EXISTS logo_url TEXT;');
  console.log('ALTER TABLE public.restaurants ADD COLUMN IF NOT EXISTS description TEXT;');
  console.log('ALTER TABLE public.restaurants ADD COLUMN IF NOT EXISTS cuisine_type TEXT;');
  console.log('ALTER TABLE public.restaurants ADD COLUMN IF NOT EXISTS address TEXT;');
  console.log('ALTER TABLE public.restaurants ADD COLUMN IF NOT EXISTS is_accepting_orders BOOLEAN DEFAULT TRUE;');
  console.log('ALTER TABLE public.restaurants ADD COLUMN IF NOT EXISTS open_time TEXT;');
  console.log('ALTER TABLE public.restaurants ADD COLUMN IF NOT EXISTS close_time TEXT;');
  console.log('ALTER TABLE public.restaurants ADD COLUMN IF NOT EXISTS phone TEXT;');
  console.log('ALTER TABLE public.restaurants ADD COLUMN IF NOT EXISTS email TEXT;');
  console.log('ALTER TABLE public.restaurants ADD COLUMN IF NOT EXISTS rating DECIMAL(3,1) DEFAULT 4.5;');
  console.log('ALTER TABLE public.restaurants ADD COLUMN IF NOT EXISTS delivery_time_minutes INTEGER DEFAULT 30;');
  console.log('ALTER TABLE public.restaurants ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();');
  console.log('');

  const { data: apps } = await supabase.admin.from('restaurant_applications')
    .select('id, restaurant_name, description, logo_url, cover_image_url, cuisine_type, address, is_accepting_orders, open_time, close_time, phone, email')
    .eq('status', 'APPROVED');

  if (!apps || apps.length === 0) { console.log('-- No approved restaurants'); return; }

  console.log('-- STEP 2: Sync data from restaurant_applications');

  for (const a of apps) {
    const parts: string[] = [];
    parts.push(`description = ${a.description ? `'${esc(a.description)}'` : 'NULL'}`);
    parts.push(`logo_url = ${a.logo_url ? `'${esc(a.logo_url)}'` : 'NULL'}`);
    parts.push(`cover_image_url = ${a.cover_image_url ? `'${esc(a.cover_image_url)}'` : 'NULL'}`);
    parts.push(`cuisine_type = ${a.cuisine_type ? `'${esc(a.cuisine_type)}'` : 'NULL'}`);
    parts.push(`address = ${a.address ? `'${esc(a.address)}'` : 'NULL'}`);
    parts.push(`is_accepting_orders = ${a.is_accepting_orders ?? true}`);
    parts.push(`open_time = ${a.open_time ? `'${esc(a.open_time)}'` : 'NULL'}`);
    parts.push(`close_time = ${a.close_time ? `'${esc(a.close_time)}'` : 'NULL'}`);
    parts.push(`phone = ${a.phone ? `'${esc(a.phone)}'` : 'NULL'}`);
    parts.push(`email = ${a.email ? `'${esc(a.email)}'` : 'NULL'}`);
    parts.push('updated_at = NOW()');

    console.log(`UPDATE public.restaurants SET ${parts.join(', ')} WHERE id = '${a.id}';`);
  }

  console.log('\n-- STEP 3: Set defaults for any remaining');
  console.log("UPDATE public.restaurants SET rating = 4.5, delivery_time_minutes = 30, is_accepting_orders = TRUE WHERE rating IS NULL;");
  console.log('');
  console.log('-- STEP 4: Verify');
  console.log('SELECT id, name, cover_image_url, cuisine_type, is_accepting_orders FROM public.restaurants ORDER BY name;');
  console.log('');
  console.log('-- STEP 5: Refresh schema cache');
  console.log("NOTIFY pgrst, 'reload schema';");
}

main().catch(console.error);
