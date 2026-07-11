import dotenv from 'dotenv';
import * as path from 'path';
dotenv.config({ path: path.join(__dirname, '..', '.env') });
import { supabase } from '../src/db/supabase';

async function main() {
  // Check LIFECYCLE orders
  const { data: orders } = await supabase.admin
    .from('orders')
    .select('order_number, status, total, created_at')
    .ilike('order_number', 'LIFECYCLE-%')
    .order('created_at', { ascending: true });

  console.log(`📦 LIFECYCLE orders: ${orders?.length || 0}`);
  orders?.forEach(o => console.log(`   ${o.order_number.padEnd(18)} | ${(o.status as string).padEnd(30)} | Rs.${o.total}`));

  // Check ACTIVE-LIFECYCLE
  const { data: active } = await supabase.admin
    .from('orders')
    .select('id, order_number, status')
    .eq('order_number', 'ACTIVE-LIFECYCLE')
    .maybeSingle();

  if (active) {
    console.log(`\n✅ ACTIVE-LIFECYCLE: FOUND (${active.id.slice(0,12)}... | ${active.status})`);
  } else {
    console.log(`\n❌ ACTIVE-LIFECYCLE: NOT FOUND`);
  }

  // Also check restaurants
  const { data: rests } = await supabase.admin.from('restaurants').select('id, name');
  console.log(`\n🏪 Restaurants in table: ${rests?.length || 0}`);
  rests?.forEach(r => console.log(`   ${r.id.slice(0,12)}... | ${r.name}`));
}

main().catch(console.error);
