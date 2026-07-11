/**
 * Generates a JWT token for testing purposes.
 * Usage: npx ts-node scripts/generate_jwt.ts <userId>
 *
 * If no userId is provided, it lists users from the database so you can pick one.
 */

import jwt from 'jsonwebtoken';
import { createClient } from '@supabase/supabase-js';
import dotenv from 'dotenv';
dotenv.config();

const JWT_SECRET = process.env.JWT_SECRET || 'supersecretkey';

async function main() {
  const userId = process.argv[2];

  if (!userId) {
    // No userId provided — query the database for available users
    const supabaseUrl = process.env.SUPABASE_URL;
    const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

    if (!supabaseUrl || !supabaseKey) {
      console.log('Usage: npx ts-node scripts/generate_jwt.ts <userId>');
      console.log('');
      console.log('Or set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in .env');
      console.log('to list users automatically.');
      console.log('');
      console.log('Known user IDs from the database:');
      console.log('  2811bd43-6919-4d2e-b3cc-29e5b391c8b6 (Amit Khayargoli / CUSTOMER)');
      console.log('  22435cb4-53b5-4317-9674-806bdb62fda9 (Delivery Guy / DELIVERY_BOY)');
      console.log('');
      console.log('Example:');
      console.log('  npx ts-node scripts/generate_jwt.ts 2811bd43-6919-4d2e-b3cc-29e5b391c8b6');
      return;
    }

    const supabase = createClient(supabaseUrl, supabaseKey, {
      auth: { persistSession: false },
    });

    const { data: users } = await supabase
      .from('users')
      .select('id, username, role')
      .limit(20);

    if (users && users.length > 0) {
      console.log('Available users:\n');
      for (const user of users) {
        console.log(`  ${user.id}  (${user.username} / ${user.role})`);
      }
      console.log('');
      console.log('Usage: npx ts-node scripts/generate_jwt.ts <userId>');
    }
    return;
  }

  const roles = ['CUSTOMER'];
  const token = jwt.sign(
    { id: userId, role: 'CUSTOMER', roles },
    JWT_SECRET,
    { expiresIn: '7d' }
  );

  console.log('\nJWT Token:');
  console.log(token);
  console.log('\nTest command:');
  console.log('');
  console.log(`curl -X POST http://localhost:5000/api/fcm/test-send \\`);
  console.log(`  -H "Content-Type: application/json" \\`);
  console.log(`  -H "Authorization: Bearer ${token}" \\`);
  console.log(`  -d '{
    "targetUserId": "${userId}",
    "title": "🧪 Test Notification",
    "body": "Hello from the backend!",
    "data": {"type": "test_notification"}
  }'`);
}

main().catch(console.error);
