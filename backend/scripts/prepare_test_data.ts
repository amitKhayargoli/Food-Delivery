import dotenv from 'dotenv';
import * as path from 'path';
dotenv.config({ path: path.join(__dirname, '..', '.env') });
import { supabase } from '../src/db/supabase';

async function main() {
  // 1. Get all restaurants with their owners and menu items
  const { data: rests } = await supabase.admin
    .from('restaurant_applications')
    .select('id, restaurant_name, user_id')
    .eq('status', 'APPROVED');

  const { data: users } = await supabase.admin
    .from('users')
    .select('id, username, role');

  const { data: items } = await supabase.admin
    .from('menu_items')
    .select('id, name, base_price, restaurant_id');

  console.log('=== EXACT IDS FOR TEST ORDER ===\n');

  // Show all restaurants with their owners
  console.log('RESTAURANTS:');
  for (const r of rests || []) {
    const owner = users?.find(u => u.id === r.user_id);
    const restItems = items?.filter(i => i.restaurant_id === r.id) || [];
    console.log(`  [${r.id}]`);
    console.log(`    Name: ${r.restaurant_name}`);
    console.log(`    Owner: ${owner?.username} (${owner?.id})`);
    console.log(`    Items (${restItems.length}):`);
    restItems.slice(0, 3).forEach(i => 
      console.log(`      [${i.id}] ${i.name} - Rs.${i.base_price}`)
    );
    console.log();
  }

  // Find a good combo: customer != owner
  const owners = users?.filter(u => u.role === 'RESTAURANT_OWNER') || [];
  const customers = users?.filter(u => u.role !== 'RESTAURANT_OWNER' && u.role !== 'ADMIN') || [];

  console.log('USERS:');
  users?.forEach(u => console.log(`  [${u.id}] ${u.username?.padEnd(20)} | ${u.role}`));
  console.log();

  // Pick first owner and first customer for the test
  if (owners.length > 0 && customers.length > 0) {
    const owner = owners[0];
    const customer = customers[0];
    const ownerRests = rests?.filter(r => r.user_id === owner.id) || [];
    
    if (ownerRests.length > 0) {
      const rest = ownerRests[0];
      const restItems = items?.filter(i => i.restaurant_id === rest.id) || [];
      
      console.log('=== RECOMMENDED TEST SETUP ===');
      console.log(`OWNER (for auth): ${owner.username} (${owner.id})`);
      console.log(`CUSTOMER: ${customer.username} (${customer.id})`);
      console.log(`RESTAURANT: ${rest.restaurant_name} (${rest.id})`);
      
      // Generate SQL for a test order
      const orderItems = restItems.slice(0, 3).map(i => ({
        menu_item_id: i.id,
        name: i.name,
        quantity: Math.floor(Math.random() * 3) + 1,
        price: Number(i.base_price),
        size: 'Regular'
      }));

      const subtotal = orderItems.reduce((s, i) => s + (i.price * i.quantity), 0);
      const deliveryFee = 40;
      const total = subtotal + deliveryFee;

      const sql = `-- ============================================
-- CREATE TEST ORDER FOR LIFECYCLE TEST
-- ============================================

INSERT INTO public.orders (
  user_id, restaurant_id, order_number, status,
  items, subtotal, delivery_fee, total,
  delivery_address, delivery_notes, special_instructions,
  estimated_prep_time, created_at, updated_at
) VALUES (
  '${customer.id}', '${rest.id}', 'LIFECYCLE-001', 'PENDING',
  '${JSON.stringify(orderItems).replace(/'/g, "''")}'::jsonb,
  ${subtotal}, ${deliveryFee}, ${total},
  '{"address": "Lakeside, Pokhara", "city": "Pokhara", "lat": 28.2096, "lng": 83.9856}'::jsonb,
  'Leave at the reception desk',
  'Extra spicy please',
  20,
  NOW(), NOW()
);

-- Create more orders for a richer test
INSERT INTO public.orders (
  user_id, restaurant_id, order_number, status,
  items, subtotal, delivery_fee, total,
  delivery_address, special_instructions,
  estimated_prep_time, created_at, updated_at
) VALUES (
  '${customer.id}', '${rest.id}', 'LIFECYCLE-002', 'ACCEPTED',
  '${JSON.stringify(orderItems.slice(0, 2)).replace(/'/g, "''")}'::jsonb,
  ${subtotal - 200}, ${deliveryFee}, ${total - 200},
  '{"address": "Thamel, Kathmandu", "city": "Kathmandu", "lat": 27.7172, "lng": 85.3240}'::jsonb,
  'Call when arriving',
  15,
  NOW() - INTERVAL '30 minutes', NOW()
);

-- Update the ACCEPTED order to have proper timestamps
UPDATE public.orders SET accepted_at = NOW() - INTERVAL '25 minutes' WHERE order_number = 'LIFECYCLE-002';

-- A PREPARING order
INSERT INTO public.orders (
  user_id, restaurant_id, order_number, status,
  items, subtotal, delivery_fee, total,
  delivery_address, special_instructions,
  estimated_prep_time, created_at, updated_at
) VALUES (
  '${customer.id}', '${rest.id}', 'LIFECYCLE-003', 'PREPARING',
  '${JSON.stringify(restItems.slice(1, 3)).replace(/'/g, "''")}'::jsonb,
  350, ${deliveryFee}, 390,
  '{"address": "Boudha, Kathmandu", "city": "Kathmandu", "lat": 27.7219, "lng": 85.3622}'::jsonb,
  'No onions please',
  20,
  NOW() - INTERVAL '45 minutes', NOW()
);
UPDATE public.orders SET accepted_at = NOW() - INTERVAL '40 minutes', preparing_at = NOW() - INTERVAL '15 minutes' WHERE order_number = 'LIFECYCLE-003';

-- A READY order
INSERT INTO public.orders (
  user_id, restaurant_id, order_number, status,
  items, subtotal, delivery_fee, total,
  delivery_address, special_instructions,
  estimated_prep_time, created_at, updated_at
) VALUES (
  '${customer.id}', '${rest.id}', 'LIFECYCLE-004', 'READY',
  '${JSON.stringify([restItems[0]]).replace(/'/g, "''")}'::jsonb,
  120, ${deliveryFee}, 160,
  '{"address": "Patan Durbar Square", "city": "Lalitpur", "lat": 27.6724, "lng": 85.3264}'::jsonb,
  'Ring the bell',
  10,
  NOW() - INTERVAL '60 minutes', NOW()
);
UPDATE public.orders SET accepted_at = NOW() - INTERVAL '55 minutes', preparing_at = NOW() - INTERVAL '40 minutes', ready_at = NOW() - INTERVAL '10 minutes' WHERE order_number = 'LIFECYCLE-004';

-- A PICKED_UP order
INSERT INTO public.orders (
  user_id, restaurant_id, order_number, status,
  items, subtotal, delivery_fee, total,
  delivery_address,
  estimated_prep_time, created_at, updated_at
) VALUES (
  '${customer.id}', '${rest.id}', 'LIFECYCLE-005', 'PICKED_UP',
  '${JSON.stringify(restItems.slice(0, 2)).replace(/'/g, "''")}'::jsonb,
  280, ${deliveryFee}, 320,
  '{"address": "Jawalakhel", "city": "Lalitpur", "lat": 27.6684, "lng": 85.3225}'::jsonb,
  15,
  NOW() - INTERVAL '75 minutes', NOW()
);
UPDATE public.orders SET 
  accepted_at = NOW() - INTERVAL '70 minutes', 
  preparing_at = NOW() - INTERVAL '55 minutes', 
  ready_at = NOW() - INTERVAL '30 minutes', 
  picked_up_at = NOW() - INTERVAL '15 minutes' 
WHERE order_number = 'LIFECYCLE-005';

-- A DELIVERED order
INSERT INTO public.orders (
  user_id, restaurant_id, order_number, status,
  items, subtotal, delivery_fee, total,
  delivery_address,
  estimated_prep_time, created_at, updated_at
) VALUES (
  '${customer.id}', '${rest.id}', 'LIFECYCLE-006', 'DELIVERED',
  '${JSON.stringify(restItems).replace(/'/g, "''")}'::jsonb,
  450, ${deliveryFee}, 490,
  '{"address": "Durbar Marg", "city": "Kathmandu", "lat": 27.7161, "lng": 85.3172}'::jsonb,
  20,
  NOW() - INTERVAL '90 minutes', NOW()
);
UPDATE public.orders SET 
  accepted_at = NOW() - INTERVAL '85 minutes', 
  preparing_at = NOW() - INTERVAL '70 minutes', 
  ready_at = NOW() - INTERVAL '45 minutes', 
  picked_up_at = NOW() - INTERVAL '30 minutes', 
  delivered_at = NOW() - INTERVAL '10 minutes' 
WHERE order_number = 'LIFECYCLE-006';

SELECT '✅ Orders created!' AS result;

-- Verify
SELECT order_number, status, total FROM public.orders WHERE order_number LIKE 'LIFECYCLE-%' ORDER BY order_number;`;

      console.log('\n=== COPY THIS SQL INTO SUPABASE SQL EDITOR ===\n');
      console.log(sql);
      console.log('\n=== END SQL ===\n');

      // Also generate the JWT and curl commands for the test
      console.log('=== CURL COMMANDS FOR LIFECYCLE TEST (run after SQL) ===');
      console.log(`\n1. Generate JWT token:\n`);
      console.log(`curl -s -X POST http://localhost:5000/api/auth/test-token 2>/dev/null || echo "(will generate manually)"`);
      console.log(`\n2. Or create token directly with node:`);
      console.log(`node -e "const jwt = require('jsonwebtoken'); console.log(jwt.sign({ id: '${owner.id}', role: 'RESTAURANT_OWNER' }, 'supersecretkey'));"`);
    }
  }
}

main().catch(e => console.error('ERROR:', e));
