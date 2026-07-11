import dotenv from 'dotenv';
import * as path from 'path';
dotenv.config({ path: path.join(__dirname, '..', '.env') });

import { supabase } from '../src/db/supabase';

async function main() {
  console.log('=== FULL DATABASE CHECK ===\n');

  // 1. Restaurants
  const { data: rests } = await supabase.admin
    .from('restaurant_applications')
    .select('id, restaurant_name, cuisine_type, user_id')
    .eq('status', 'APPROVED');

  console.log(`🍽️ RESTAURANTS (${rests?.length || 0}):`);
  rests?.forEach(r => console.log(`   ${r.restaurant_name.padEnd(30)} | id=${r.id.slice(0,10)}... | owner=${r.user_id.slice(0,10)}...`));

  if (!rests || rests.length === 0) {
    console.log('\n❌ No restaurants found. Aborting.');
    return;
  }

  // 2. Menu items - check with different approaches
  console.log('\n🥘 MENU ITEMS:');
  
  // Check first restaurant's items
  const firstRest = rests[0];
  const { data: items, error: itemsError } = await supabase.admin
    .from('menu_items')
    .select('id, name, base_price, category')
    .eq('restaurant_id', firstRest.id);
  
  if (itemsError) {
    console.log(`   ❌ Error: ${itemsError.message}`);
    console.log(`   Code: ${itemsError.code}`);
  } else {
    console.log(`   Count: ${items?.length || 0}`);
    items?.slice(0, 5).forEach(i => console.log(`   - ${i.name.padEnd(25)} | Rs.${i.base_price}`));
  }

  // Check ALL restaurants for items
  console.log('\n📋 Menu items by restaurant:');
  for (const r of rests) {
    const { data: ri, error: re } = await supabase.admin
      .from('menu_items')
      .select('id', { count: 'exact', head: true })
      .eq('restaurant_id', r.id);
    
    if (re) console.log(`   ❌ ${r.restaurant_name.padEnd(30)} | Error: ${re.message.substring(0, 60)}`);
    else {
      // Try getting the count a different way
      const { data: ri2 } = await supabase.admin
        .from('menu_items')
        .select('id')
        .eq('restaurant_id', r.id);
      console.log(`   ${r.restaurant_name.padEnd(30)} | ${ri2?.length || 0} items`);
    }
  }

  // 3. Users
  const { data: users } = await supabase.admin
    .from('users')
    .select('id, username, role');
  
  console.log(`\n👤 USERS (${users?.length || 0}):`);
  const owners = users?.filter(u => u.role === 'RESTAURANT_OWNER') || [];
  const regulars = users?.filter(u => !['RESTAURANT_OWNER', 'ADMIN'].includes(u.role || '')) || [];
  console.log(`   Owners: ${owners.length}`);
  owners?.slice(0, 4).forEach(o => console.log(`   - ${o.id.slice(0,12)}... | ${o.username?.padEnd(15)} | ${o.role}`));
  console.log(`   Regular customers: ${regulars.length}`);
  regulars?.slice(0, 4).forEach(c => console.log(`   - ${c.id.slice(0,12)}... | ${c.username?.padEnd(15)} | ${c.role}`));

  // Find a good owner for testing (one that has restaurants)
  console.log('\n🔑 PICKING BEST OWNER FOR TEST:');
  const ownersWithRestaurants = rests.map(r => r.user_id);
  for (const ownerId of [...new Set(ownersWithRestaurants)]) {
    const owner = owners?.find(u => u.id === ownerId);
    const theirRests = rests.filter(r => r.user_id === ownerId);
    console.log(`   ${owner?.username?.padEnd(15) || '?'} | id=${ownerId.slice(0,12)}... | runs: ${theirRests.map(r => r.restaurant_name).join(', ')}`);
  }

  // 4. Orders
  const { data: orders } = await supabase.admin
    .from('orders')
    .select('id, order_number, status')
    .limit(5);
  
  console.log(`\n📦 ORDERS: ${orders?.length || 0}`);
}

main().catch(e => console.error('ERROR:', e));
