import dotenv from 'dotenv';
import * as path from 'path';
dotenv.config({ path: path.join(__dirname, '..', '.env') });

import { supabase } from '../src/db/supabase';

async function main() {
  console.log('=== ENUM & COLUMN TYPE CHECK ===\n');

  // 1. Try to get enum values by attempting various status values
  const testStatuses = ['pending', 'PENDING', 'Pending', 'order_placed', 'Order_Placed', 'PLACED', 'placed', 'new', 'NEW'];
  
  const { data: users } = await supabase.admin.from('users').select('id').limit(1);
  const { data: rests } = await supabase.admin.from('restaurant_applications').select('id').eq('status', 'APPROVED').limit(1);
  const { data: existingOrders } = await supabase.admin.from('orders').select('id, status').limit(5);

  if (existingOrders && existingOrders.length > 0) {
    console.log('✅ Existing orders found! Showing their status values:');
    for (const o of existingOrders) {
      console.log(`   id=${o.id.slice(0, 12)}... status="${o.status}"`);
    }
    console.log('\nThe existing status values tell us what the enum accepts!');
    return;
  }

  // Try inserting with different status values
  if (users?.[0] && rests?.[0]) {
    for (const status of testStatuses) {
      const { error } = await supabase.admin.from('orders').insert({
        user_id: users[0].id,
        restaurant_id: rests[0].id,
        status: status,
        items: [{ name: 'Test' }],
        subtotal: 100,
        total: 100,
        order_number: `TEST-${status}`
      }).select().single();
      
      if (error) {
        console.log(`❌ status="${status}": ${error.message.substring(0, 60)}`);
      } else {
        console.log(`✅ status="${status}": INSERT SUCCEEDED!`);
      }
    }
  }

  // Also try selecting the column type directly
  const { data: colInfo } = await supabase.admin.rpc('get_schema' as any);
  if (colInfo) console.log('\nSchema info:', JSON.stringify(colInfo).substring(0, 500));
}

main().catch(e => console.error('ERROR:', e));
