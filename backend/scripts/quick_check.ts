import dotenv from 'dotenv';
import * as path from 'path';
dotenv.config({ path: path.join(__dirname, '..', '.env') });

import { supabase } from '../src/db/supabase';

async function main() {
  // Get all approved restaurants with owners
  const { data: rests } = await supabase.admin
    .from('restaurant_applications')
    .select('id, restaurant_name, user_id')
    .eq('status', 'APPROVED');

  if (!rests || rests.length === 0) {
    console.log('❌ No approved restaurants found');
    return;
  }

  console.log(`\n🍽️  APPROVED RESTAURANTS (${rests.length}):`);
  rests.forEach(r => console.log(`   ${r.restaurant_name.padEnd(28)} | owner=${r.user_id.slice(0,12)}...`));

  // Get the restaurant owners
  const ownerIds = rests.map(r => r.user_id);
  const { data: owners } = await supabase.admin
    .from('users')
    .select('id, username, role, phone')
    .in('id', ownerIds);

  console.log(`\n👤 OWNER USERS:`);
  owners?.forEach(o => console.log(`   ${o.username?.padEnd(20)} | id=${o.id.slice(0,12)}... | role=${o.role}`));

  // Get all orders with restaurant names
  const { data: orders } = await supabase.admin
    .from('orders')
    .select('id, order_number, status, restaurant_id, total')
    .order('created_at', { ascending: true })
    .limit(20);

  console.log(`\n📦 ORDERS (${orders?.length || 0}):`);
  orders?.forEach(o => {
    const rest = rests.find(r => r.id === o.restaurant_id);
    console.log(`   #${o.order_number?.padEnd(8)} | ${o.status?.padEnd(12)} | ${rest?.restaurant_name?.padEnd(28) || 'N/A'} | Rs. ${o.total}`);
  });

  // Get a regular customer user for test orders
  if (orders && orders.length > 0) {
    const p = orders.find(o => o.status === 'PENDING' || o.status === 'pending');
    if (p) {
      const rest = rests.find(r => r.id === p.restaurant_id);
      console.log(`\n✅ BEST ORDER FOR TESTING:`);
      console.log(`   Order #${p.order_number} | ${p.status} | ${rest?.restaurant_name || 'N/A'}`);
      console.log(`   Order ID: ${p.id}`);
      console.log(`   Restaurant ID: ${p.restaurant_id}`);
    } else {
      console.log(`\n⚠️  No PENDING orders found. First order:`);
      if (orders[0]) console.log(`   Order #${orders[0].order_number} | ${orders[0].status} | ID: ${orders[0].id}`);
    }
  }

  // Show the first owner for login
  if (owners && owners.length > 0) {
    console.log(`\n🔑 USE THIS OWNER FOR AUTH:`);
    console.log(`   ID: ${owners[0].id}`);
    console.log(`   Username: ${owners[0].username}`);
    console.log(`   JWT_SECRET: supersecretkey`);
  }
}

main().catch(e => console.error('ERROR:', e));
