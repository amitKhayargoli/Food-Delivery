import dotenv from 'dotenv';
import * as path from 'path';
dotenv.config({ path: path.join(__dirname, '..', '.env') });

import { supabase } from '../src/db/supabase';

async function main() {
  // 1. Check if orders table exists via a raw query
  console.log('=== CHECKING ORDERS TABLE ===');
  
  const { data: tableInfo, error: tableError } = await supabase.admin.rpc(
    'get_schema' as any,
    {}
  );
  
  // Try checking with a raw COUNT query
  const { count, error: countError } = await supabase.admin
    .from('orders')
    .select('*', { count: 'exact', head: true });
  
  if (countError) {
    console.log('❌ Orders table error:', countError.message);
    console.log('   Code:', countError.code);
    
    // Check what tables exist
    const { data: tables } = await supabase.admin
      .from('information_schema.tables' as any)
      .select('table_name')
      .eq('table_schema', 'public');
    
    if (tables) {
      console.log('\n📋 Public tables:', tables.map((t: any) => t.table_name).join(', '));
    }
    
    return;
  }
  
  console.log(`✅ Orders table exists with count = ${count}`);
  
  // 2. Get all orders
  const { data: orders } = await supabase.admin
    .from('orders')
    .select('*')
    .limit(10);
  
  console.log(`\n📦 Orders found: ${orders?.length || 0}`);
  if (orders && orders.length > 0) {
    orders.forEach(o => {
      console.log(`   #${o.order_number} | ${o.status} | Rs.${o.total}`);
    });
  }
  
  // 3. Get restaurants with their first menu item
  const { data: rests } = await supabase.admin
    .from('restaurant_applications')
    .select('id, restaurant_name')
    .eq('status', 'APPROVED')
    .limit(5);
    
  const { data: items } = await supabase.admin
    .from('menu_items')
    .select('id, name, price, restaurant_id')
    .limit(10);
  
  console.log(`\n🍽️ Restaurants: ${rests?.length || 0}`);
  console.log(`🥘 Menu items: ${items?.length || 0}`);
  
  if (items && items.length > 0) {
    console.log('\nSample menu items:');
    items.slice(0, 5).forEach(i => console.log(`   ${i.name.padEnd(25)} | Rs.${i.price} | restaurant=${i.restaurant_id.slice(0,8)}...`));
  }
  
  // 4. Get regular customers
  const { data: customers } = await supabase.admin
    .from('users')
    .select('id, username, role')
    .or('role.eq.USER,role.eq.CUSTOMER');
  
  console.log(`\n👤 Regular customers: ${customers?.length || 0}`);
  customers?.slice(0, 3).forEach(c => console.log(`   ${c.username?.padEnd(20)} | ${c.role}`));
}

main().catch(e => console.error('ERROR:', e));
