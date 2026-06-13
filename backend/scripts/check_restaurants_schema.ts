import dotenv from 'dotenv';
import * as path from 'path';
dotenv.config({ path: path.join(__dirname, '..', '.env') });
import { supabase } from '../src/db/supabase';

async function main() {
  // Check what columns are in restaurants
  const cols = ['id', 'name', 'description', 'address', 'cuisine_type', 'phone', 'email', 'owner_id', 'user_id', 'logo_url', 'cover_image_url', 'created_at'];
  console.log('=== RESTAURANTS TABLE COLUMNS ===\n');
  
  for (const col of cols) {
    const { error } = await supabase.admin.from('restaurants').select(col).limit(1);
    console.log(error ? `❌ "${col}": ERROR` : `✅ "${col}": OK`);
  }

  // Get data from restaurant_applications
  const { data: apps } = await supabase.admin
    .from('restaurant_applications')
    .select('id, restaurant_name, description, address, cuisine_type, phone, email, user_id, logo_url, cover_image_url, created_at');
  
  if (!apps || apps.length === 0) {
    console.log('\n❌ No restaurant_applications found');
    return;
  }

  console.log(`\n=== GENERATING INSERT SQL FOR ${apps.length} RESTAURANTS ===\n`);

  // Generate INSERT statements
  for (const a of apps) {
    const name = a.restaurant_name?.replace(/'/g, "''") || 'Unknown';
    const desc = a.description ? `'${a.description.replace(/'/g, "''")}'` : 'NULL';
    const addr = a.address ? `'${a.address.replace(/'/g, "''")}'` : 'NULL';
    const cuisine = a.cuisine_type ? `'${a.cuisine_type.replace(/'/g, "''")}'` : 'NULL';
    const phone = a.phone ? `'${a.phone.replace(/'/g, "''")}'` : 'NULL';
    const email = a.email ? `'${a.email.replace(/'/g, "''")}'` : 'NULL';
    const logo = a.logo_url ? `'${a.logo_url.replace(/'/g, "''")}'` : 'NULL';
    const cover = a.cover_image_url ? `'${a.cover_image_url.replace(/'/g, "''")}'` : 'NULL';
    const createdAt = a.created_at ? `'${a.created_at}'` : 'NOW()';

    // Try with name column first (most likely)
    console.log(`INSERT INTO public.restaurants (id, name, description, address, cuisine_type, phone, email, user_id, logo_url, cover_image_url, created_at) VALUES ('${a.id}', '${name}', ${desc}, ${addr}, ${cuisine}, ${phone}, ${email}, '${a.user_id}', ${logo}, ${cover}, ${createdAt}) ON CONFLICT (id) DO NOTHING;`);
  }

  console.log('\n-- Verify');
  console.log('SELECT id, name FROM public.restaurants;');
}

main().catch(e => console.error('ERROR:', e));
