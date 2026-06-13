import dotenv from 'dotenv';
import * as path from 'path';
dotenv.config({ path: path.join(__dirname, '..', '.env') });

import { supabase } from '../src/db/supabase';

async function main() {
  console.log('=== ORDERS TABLE SCHEMA CHECK ===\n');

  const testColumns = ['id', 'status', 'user_id', 'restaurant_id', 'items', 'subtotal', 'total', 'created_at'];
  
  for (const col of testColumns) {
    const { error } = await supabase.admin.from('orders').select(col).limit(1);
    console.log(error ? `❌ "${col}": ERROR - ${error.message.substring(0, 80)}` : `✅ "${col}": OK`);
  }

  const extraCols = [
    'order_number', 'delivery_fee', 'delivery_address', 'delivery_notes',
    'special_instructions', 'estimated_prep_time', 'delivery_boy_id',
    'assigned_at', 'accepted_at', 'preparing_at', 'ready_at',
    'picked_up_at', 'delivered_at', 'cancelled_at', 'rejection_reason', 'updated_at'
  ];
  
  console.log('\n--- Extra columns ---');
  for (const col of extraCols) {
    const { error } = await supabase.admin.from('orders').select(col).limit(1);
    console.log(error ? `❌ "${col}": ERROR - ${error.message.substring(0, 80)}` : `✅ "${col}": OK`);
  }

  // 3. Try minimal inserts to find the working column set
  console.log('\n--- Minimal insert test ---');
  
  const { data: users } = await supabase.admin.from('users').select('id').limit(1);
  const { data: rests } = await supabase.admin.from('restaurant_applications').select('id').eq('status', 'APPROVED').limit(1);
  
  if (users?.[0] && rests?.[0]) {
    // Attempt 1: basic columns only
    const { error: e1 } = await supabase.admin.from('orders').insert({
      user_id: users[0].id,
      restaurant_id: rests[0].id,
      status: 'PENDING',
      items: [{ name: 'Test Item', quantity: 1, price: 100 }],
      subtotal: 100,
      total: 100
    }).select().single();
    console.log(e1 ? `❌ basic insert: ${e1.message.substring(0, 80)}` : `✅ basic insert worked!`);

    // Attempt 2: with delivery_fee
    const { error: e2 } = await supabase.admin.from('orders').insert({
      user_id: users[0].id,
      restaurant_id: rests[0].id,
      status: 'PENDING',
      items: [{ name: 'Test Item', quantity: 1, price: 100 }],
      subtotal: 100,
      total: 100,
      delivery_fee: 40
    }).select().single();
    console.log(e2 ? `❌ with delivery_fee: ${e2.message.substring(0, 80)}` : `✅ with delivery_fee worked!`);

    // Attempt 3: with order_number
    const { error: e3 } = await supabase.admin.from('orders').insert({
      user_id: users[0].id,
      restaurant_id: rests[0].id,
      status: 'PENDING',
      items: [{ name: 'Test', quantity: 1, price: 100 }],
      subtotal: 100,
      total: 100,
      order_number: 'TEST-ABC'
    }).select().single();
    console.log(e3 ? `❌ with order_number: ${e3.message.substring(0, 80)}` : `✅ with order_number worked!`);
  }
}

main().catch(e => console.error('ERROR:', e));
