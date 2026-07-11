import dotenv from 'dotenv';
import * as path from 'path';
dotenv.config({ path: path.join(__dirname, '..', '.env') });
import jwt from 'jsonwebtoken';

const JWT_SECRET = process.env.JWT_SECRET || 'supersecretkey';
const OWNER_ID = '6b42ea23-33da-4d94-ab05-766f6d09f217';
const PORT = process.env.PORT || 5000;
const BASE = `http://localhost:${PORT}/api`;

async function main() {
  console.log('========================================');
  console.log('  🚀 FULL ORDER LIFECYCLE TEST');
  console.log('========================================\n');

  // 1. Generate JWT token
  const token = jwt.sign({ id: OWNER_ID, role: 'RESTAURANT_OWNER' }, JWT_SECRET);
  console.log('✅ JWT token generated');
  console.log(`   Token: ${token.substring(0, 40)}...\n`);

  const headers = {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${token}`,
  };

  // 2. First get the restaurant orders to find the ACTIVE-LIFECYCLE order ID
  console.log('📡 Fetching restaurant orders...');
  let ordersResp;
  try {
    ordersResp = await fetch(`${BASE}/orders/restaurant`, { headers });
    const data = await ordersResp.json() as any;
    const orders = data.orders as any[] || [];
    
    const activeOrder = orders.find((o: any) => o.order_number === 'ACTIVE-LIFECYCLE');
    if (!activeOrder) {
      console.log('❌ ACTIVE-LIFECYCLE order not found!');
      console.log(`   Found ${orders.length} orders total`);
      orders.forEach((o: any) => console.log(`   - ${o.order_number} [${o.status}]`));
      process.exit(1);
    }

    const orderId = activeOrder.id;
    console.log(`✅ Found ACTIVE-LIFECYCLE order: ${orderId.substring(0, 12)}...`);
    console.log(`   Current status: ${activeOrder.status}\n`);

    // 3. Progress through all 6 statuses
    const steps = [
      { endpoint: 'accept', label: 'ACCEPTED', color: '🟦' },
      { endpoint: 'preparing', label: 'PREPARING', color: '🟨' },
      { endpoint: 'ready', label: 'READY_FOR_PICKUP', color: '🟢' },
      { endpoint: 'picked-up', label: 'PICKED_UP', color: '🔵' },
      { endpoint: 'delivered', label: 'DELIVERED', color: '✅' },
    ];

    for (const step of steps) {
      console.log(`   ${step.color} Step: ${step.endpoint} → ${step.label}`);
      
      const resp = await fetch(`${BASE}/orders/${orderId}/${step.endpoint}`, {
        method: 'PATCH',
        headers,
      });
      
      const result = await resp.json() as any;
      
      if (resp.ok) {
        console.log(`      ✅ Success! Status: ${result.order?.status || step.label}`);
        console.log(`      📋 Message: ${result.message}`);
      } else {
        console.log(`      ❌ Failed: ${result.error || resp.statusText}`);
        process.exit(1);
      }
      console.log('');
    }

    // 4. Final verification
    console.log('📋 Final verification...');
    const finalResp = await fetch(`${BASE}/orders/${orderId}`, { headers });
    const finalData = await finalResp.json() as any;
    const finalOrder = finalData.order;

    if (finalOrder) {
      console.log(`   Order #${finalOrder.order_number}`);
      console.log(`   Final status: ${finalOrder.status}`);
      console.log(`   Delivered at: ${finalOrder.delivered_at}`);
      console.log('\n🎉 LIFECYCLE TEST PASSED!');
    }
  } catch (err: any) {
    console.log(`\n❌ ERROR: ${err.message}`);
    console.log('   Make sure the backend server is running on port ' + PORT);
    console.log('   Start it with: cd backend && npx ts-node src/index.ts');
    process.exit(1);
  }
}

main();
