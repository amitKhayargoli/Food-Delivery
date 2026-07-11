/**
 * Dispatch Log Table Migration
 *
 * Run this to create the dispatch_log table:
 *   npx ts-node backend/scripts/create_dispatch_log.ts
 *
 * This creates the dispatch_log table that records every automatic or
 * manual rider assignment so owners/admins can audit dispatch decisions.
 */
import { Client } from 'pg';
import dotenv from 'dotenv';
import * as path from 'path';
import * as fs from 'fs';
dotenv.config({ path: path.join(__dirname, '..', '.env') });

const projectRef = process.env.SUPABASE_URL?.replace('https://', '').replace('.supabase.co', '');
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!projectRef || !serviceRoleKey) {
  console.error('❌ SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set in backend/.env');
  process.exit(1);
}

// Read the SQL from the .sql file
const sqlPath = path.join(__dirname, 'create_dispatch_log.sql');
const createSQL = fs.readFileSync(sqlPath, 'utf-8');

const connections: { name: string; connString: string }[] = [
  { name: 'direct (port 5432)', connString: `postgresql://postgres:${encodeURIComponent(serviceRoleKey)}@db.${projectRef}.supabase.co:5432/postgres` },
  { name: 'direct (port 6543)', connString: `postgresql://postgres:${encodeURIComponent(serviceRoleKey)}@db.${projectRef}.supabase.co:6543/postgres` },
  { name: 'pooler ap-southeast-1', connString: `postgresql://postgres.${projectRef}:${encodeURIComponent(serviceRoleKey)}@ap-southeast-1.pooler.supabase.com:6543/postgres` },
  { name: 'pooler ap-southeast-2', connString: `postgresql://postgres.${projectRef}:${encodeURIComponent(serviceRoleKey)}@ap-southeast-2.pooler.supabase.com:6543/postgres` },
  { name: 'pooler ap-south-1', connString: `postgresql://postgres.${projectRef}:${encodeURIComponent(serviceRoleKey)}@ap-south-1.pooler.supabase.com:6543/postgres` },
  { name: 'pooler us-east-1', connString: `postgresql://postgres.${projectRef}:${encodeURIComponent(serviceRoleKey)}@us-east-1.pooler.supabase.com:6543/postgres` },
  { name: 'pooler (anon) ap-southeast-1', connString: `postgresql://postgres.${projectRef}:${encodeURIComponent(serviceRoleKey)}@ap-southeast-1.pooler.supabase.com:5432/postgres` },
];

async function tryConnect(conn: { name: string; connString: string }): Promise<boolean> {
  const client = new Client({ connectionString: conn.connString, connectionTimeoutMillis: 6000 });
  try {
    await client.connect();
    console.log(`✅ Connected: ${conn.name}`);

    await client.query(createSQL);
    console.log('   ✅ dispatch_log table created/verified!');

    const { rows } = await client.query(
      `SELECT column_name, data_type, is_nullable 
       FROM information_schema.columns 
       WHERE table_schema = 'public' AND table_name = 'dispatch_log'
       ORDER BY ordinal_position`
    );
    console.log('   Columns:');
    rows.forEach((r: any) => console.log(`     - ${r.column_name} (${r.data_type})`));

    // Show CHECK constraints
    const { rows: constraints } = await client.query(
      `SELECT pg_get_constraintdef(oid) AS constraint_def
       FROM pg_constraint
       WHERE conrelid = 'public.dispatch_log'::regclass
         AND contype = 'c'`
    );
    if (constraints.length > 0) {
      console.log('   Constraints:');
      constraints.forEach((c: any) => console.log(`     - ${c.constraint_def}`));
    }

    await client.end();
    return true;
  } catch (err: any) {
    const msg = err.message || String(err);
    console.log(`❌ ${conn.name}: ${msg.substring(0, 200)}`);
    await client.end().catch(() => {});
    return false;
  }
}

async function main() {
  for (const conn of connections) {
    const ok = await tryConnect(conn);
    if (ok) process.exit(0);
  }
  console.log('\n❌ All connections failed. Please create the table manually via Supabase SQL Editor with:');
  console.log(createSQL);
  process.exit(1);
}

main();
