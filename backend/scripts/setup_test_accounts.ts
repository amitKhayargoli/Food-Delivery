/**
 * Setup script for multi-role test accounts.
 *
 * Run with: npx ts-node scripts/setup_test_accounts.ts
 * (from the backend/ directory)
 *
 * This script:
 * 1. Ensures the `roles` column exists (runs migration if needed)
 * 2. Sets amitkhayargoli99@gmail.com → CUSTOMER + DELIVERY_BOY
 * 3. Sets khayargoliamit99@gmail.com → CUSTOMER + RESTAURANT_OWNER
 */
import dotenv from 'dotenv';
dotenv.config({ path: require('path').join(__dirname, '..', '.env') });

import { supabase } from '../src/db/supabase';

async function main() {
  console.log('🚀 Setting up multi-role test accounts...\n');

  // ── Step 1: Ensure roles column exists ──
  console.log('📦 Ensuring roles column exists...');
  const { error: alterError } = await supabase.admin.rpc('exec_sql', {
    sql: `
      ALTER TABLE public.users
        ADD COLUMN IF NOT EXISTS roles TEXT[] DEFAULT ARRAY['CUSTOMER'];

      UPDATE public.users
        SET roles = ARRAY[role]
        WHERE roles IS NULL
           OR array_length(roles, 1) IS NULL
           OR roles = ARRAY[]::text[];

      CREATE INDEX IF NOT EXISTS idx_users_roles
        ON public.users USING GIN (roles);
    `,
  });

  if (alterError) {
    // `exec_sql` RPC often doesn't exist on Supabase — fall back to direct update
    console.log('   ⚠️ Could not run migration via RPC (this is normal).');
    console.log('   ✅ The update queries below will work as long as the column exists.');
    console.log('   If you see column errors, run create_roles_array.sql first.');
  } else {
    console.log('   ✅ Migration complete.');
  }

  // ── Step 2: Set amitkhayargoli99@gmail.com → CUSTOMER + DELIVERY_BOY ──
  console.log('\n📦 Updating amitkhayargoli99@gmail.com → CUSTOMER + DELIVERY_BOY...');
  
  const { data: user1, error: err1 } = await supabase.admin
    .from('users')
    .update({
      role: 'DELIVERY_BOY',
      roles: ['CUSTOMER', 'DELIVERY_BOY'],
      status: 'ACTIVE',
    })
    .eq('email', 'amitkhayargoli99@gmail.com')
    .select('id, username, email, role, roles');

  if (err1) {
    console.error('   ❌ Error:', err1.message);
  } else if (user1 && user1.length > 0) {
    console.log(`   ✅ Updated: ${user1[0].username} (${user1[0].email})`);
    console.log(`      Roles: ${user1[0].roles?.join(', ') || 'N/A'}`);
  } else {
    console.log('   ⚠️ No user found with that email.');
  }

  // ── Step 3: Set khayargoliamit99@gmail.com → CUSTOMER + RESTAURANT_OWNER ──
  console.log('\n📦 Updating khayargoliamit99@gmail.com → CUSTOMER + RESTAURANT_OWNER...');
  
  const { data: user2, error: err2 } = await supabase.admin
    .from('users')
    .update({
      role: 'RESTAURANT_OWNER',
      roles: ['CUSTOMER', 'RESTAURANT_OWNER'],
      status: 'ACTIVE',
    })
    .eq('email', 'khayargoliamit99@gmail.com')
    .select('id, username, email, role, roles');

  if (err2) {
    console.error('   ❌ Error:', err2.message);
  } else if (user2 && user2.length > 0) {
    console.log(`   ✅ Updated: ${user2[0].username} (${user2[0].email})`);
    console.log(`      Roles: ${user2[0].roles?.join(', ') || 'N/A'}`);
  } else {
    console.log('   ⚠️ No user found with that email.');
  }

  // ── Summary ──
  console.log('\n📋 Summary of all users with roles:');
  const { data: allUsers } = await supabase.admin
    .from('users')
    .select('username, email, role, roles')
    .in('email', ['amitkhayargoli99@gmail.com', 'khayargoliamit99@gmail.com']);

  if (allUsers) {
    for (const u of allUsers) {
      console.log(`   • ${u.username.padEnd(20)} ${u.email.padEnd(35)} roles: [${(u.roles || [u.role]).join(', ')}]`);
    }
  }

  console.log('\n✅ Done! Restart the app and you should see the role switcher.');
  console.log('   Tap the "Switch to..." button on the bottom-left of any screen.');
}

main().catch(console.error);
