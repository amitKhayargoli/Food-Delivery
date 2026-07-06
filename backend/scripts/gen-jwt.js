/**
 * Generate a JWT for testing notifications.
 *
 * Usage:
 *   node scripts/gen-jwt.js [userId]
 *
 * Default userId: 2811bd43-6919-4d2e-b3cc-29e5b391c8b6 (Amit Khayargoli - CUSTOMER)
 */
const jwt = require('jsonwebtoken');

const JWT_SECRET = 'supersecretkey';
const userId = process.argv[2] || '2811bd43-6919-4d2e-b3cc-29e5b391c8b6';

const token = jwt.sign(
  { id: userId, role: 'CUSTOMER', roles: ['CUSTOMER'] },
  JWT_SECRET,
  { expiresIn: '7d' }
);

console.log('\n=== JWT Token ===');
console.log(token);
console.log('');

console.log('=== Test Notification Command ===');
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
console.log('');
