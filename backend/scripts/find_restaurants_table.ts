import dotenv from 'dotenv';
import * as path from 'path';
dotenv.config({ path: path.join(__dirname, '..', '.env') });
import { supabase } from '../src/db/supabase';

async function main() {
  console.log('=== FINDING RESTAURANTS TABLE ===\n');

  // Check if restaurants table exists
  const { data: r1, error: e1 } = await supabase.admin.from('restaurants').select('id, name').limit(10);
  if (e1) console.log('❌ restaurants table:', e1.message.substring(0, 80));
  else {
    console.log(`✅ restaurants table! Found ${r1?.length || 0} rows:`);
    r1?.forEach(r => console.log(`   id=${r.id} | name=${(r as any).name || '(no name)'}`));
  }

  // Check restaurant_applications
  const { data: r2, error: e2 } = await supabase.admin.from('restaurant_applications').select('id, restaurant_name').limit(10);
  if (e2) console.log('❌ restaurant_applications:', e2.message.substring(0, 80));
  else {
    console.log(`\n✅ restaurant_applications table! Found ${r2?.length || 0} rows:`);
    r2?.forEach(r => console.log(`   id=${r.id} | name=${r.restaurant_name}`));
  }

  // Check foreign key constraint details
  const { data: fk } = await supabase.admin
    .from('information_schema.table_constraints' as any)
    .select('constraint_name, constraint_type, table_name')
    .eq('table_name', 'orders');
  
  if (fk) console.log('\nOrders table constraints:', JSON.stringify(fk, null, 2));
  
  // Check the actual column types for restaurant_id in orders
  const { data: colInfo } = await supabase.admin
    .from('information_schema.columns' as any)
    .select('column_name, data_type, udt_name')
    .eq('table_name', 'orders');
  
  if (colInfo) {
    console.log('\nOrders columns:');
    colInfo.forEach((c: any) => console.log(`   ${c.column_name}: ${c.data_type}${c.udt_name ? ` (${c.udt_name})` : ''}`));
  }
}

main().catch(e => console.error('ERROR:', e));
