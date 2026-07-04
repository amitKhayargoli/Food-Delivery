import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
import path from 'path';
import WebSocket from 'ws';
dotenv.config({ path: path.join(__dirname, '..', '.env') });

const supabaseUrl = process.env.SUPABASE_URL!;
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY!;

const admin = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false },
  realtime: { transport: WebSocket as any },
});

async function discover() {
  // Try inserting with just order_id to see what columns are required
  const testOrderId = '00000000-0000-0000-0000-000000000000';
  
  // Try minimal insert
  console.log('1. Try insert with order_id only:');
  const r1 = await admin.from('order_items').insert({ order_id: testOrderId }).select('*');
  console.log(JSON.stringify(r1.error?.message || r1.data, null, 2));
  
  if (r1.data) {
    console.log('✅ Columns:', Object.keys(r1.data[0]));
    await admin.from('order_items').delete().eq('order_id', testOrderId);
    return;
  }
  
  // Try with order_id + food_id
  console.log('\n2. Try with order_id + food_id:');
  const r2 = await admin.from('order_items').insert({ order_id: testOrderId, food_id: 'test' }).select('*');
  console.log(JSON.stringify(r2.error?.message || r2.data, null, 2));
  if (r2.data) {
    console.log('✅ Columns:', Object.keys(r2.data[0]));
    await admin.from('order_items').delete().eq('order_id', testOrderId);
    return;
  }
  
  // Try order_id + name
  console.log('\n3. Try with order_id + name:');
  const r3 = await admin.from('order_items').insert({ order_id: testOrderId, name: 'test' }).select('*');
  console.log(JSON.stringify(r3.error?.message || r3.data, null, 2));
  if (r3.data) {
    console.log('✅ Columns:', Object.keys(r3.data[0]));
    await admin.from('order_items').delete().eq('order_id', testOrderId);
    return;
  }
  
  // Try with order_id + name + price
  console.log('\n4. Try with order_id + name + price:');
  const r4 = await admin.from('order_items').insert({ order_id: testOrderId, name: 'test', price: 100 }).select('*');
  console.log(JSON.stringify(r4.error?.message || r4.data, null, 2));
  if (r4.data) {
    console.log('✅ Columns:', Object.keys(r4.data[0]));
    await admin.from('order_items').delete().eq('order_id', testOrderId);
    return;
  }
  
  // Try with order_id + name + price + quantity
  console.log('\n5. Try with order_id + name + price + quantity:');
  const r5 = await admin.from('order_items').insert({ order_id: testOrderId, name: 'test', price: 100, quantity: 1 }).select('*');
  console.log(JSON.stringify(r5.error?.message || r5.data, null, 2));
  if (r5.data) {
    console.log('✅ Columns:', Object.keys(r5.data[0]));
    await admin.from('order_items').delete().eq('order_id', testOrderId);
    return;
  }
}

discover().catch(console.error);
