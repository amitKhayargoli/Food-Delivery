import { Client } from 'pg';
import dotenv from 'dotenv';
import * as path from 'path';
dotenv.config({ path: path.join(__dirname, '..', '.env') });

const projectRef = process.env.SUPABASE_URL!.replace('https://', '').replace('.supabase.co', '');
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY!;

const alterSQL = `
ALTER TABLE IF EXISTS public.restaurant_applications
ADD COLUMN IF NOT EXISTS is_accepting_orders BOOLEAN NOT NULL DEFAULT TRUE;
`;

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

    await client.query(alterSQL);
    console.log('   ✅ Column "is_accepting_orders" added (or already existed)!');

    const { rows } = await client.query(
      `SELECT column_name, data_type, is_nullable, column_default
       FROM information_schema.columns
       WHERE table_schema = 'public' AND table_name = 'restaurant_applications'
       ORDER BY ordinal_position`
    );
    console.log('   Columns after migration:');
    rows.forEach((r: any) =>
      console.log(`     - ${r.column_name} (${r.data_type})${r.is_nullable === 'YES' ? ' NULL' : ' NOT NULL'}${r.column_default ? ` DEFAULT ${r.column_default}` : ''}`)
    );

    await client.end();
    return true;
  } catch (err: any) {
    const msg = err.message || String(err);
    console.log(`❌ ${conn.name}: ${msg.substring(0, 100)}`);
    await client.end().catch(() => {});
    return false;
  }
}

async function main() {
  for (const conn of connections) {
    const ok = await tryConnect(conn);
    if (ok) process.exit(0);
  }
  console.log('\nAll connections failed. Run manually via Supabase SQL editor with:');
  console.log(alterSQL);
  process.exit(1);
}

main();
