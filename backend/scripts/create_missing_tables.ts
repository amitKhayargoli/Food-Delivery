import { Client } from 'pg';
import dotenv from 'dotenv';
import * as path from 'path';
import * as fs from 'fs';
dotenv.config({ path: path.join(__dirname, '..', '.env') });

const projectRef = process.env.SUPABASE_URL!.replace('https://', '').replace('.supabase.co', '');
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY!;

// Read the SQL migration files
const supportSQL = fs.readFileSync(path.join(__dirname, 'create_support_tables.sql'), 'utf8');
const problemsSQL = fs.readFileSync(path.join(__dirname, 'create_order_problems_table.sql'), 'utf8');
const combinedSQL = supportSQL + '\n' + problemsSQL;

const connections: { name: string; connString: string }[] = [
  { name: 'direct (port 5432)', connString: `postgresql://postgres:${encodeURIComponent(serviceRoleKey)}@db.${projectRef}.supabase.co:5432/postgres` },
  { name: 'direct (port 6543)', connString: `postgresql://postgres:${encodeURIComponent(serviceRoleKey)}@db.${projectRef}.supabase.co:6543/postgres` },
  { name: 'pooler ap-southeast-1', connString: `postgresql://postgres.${projectRef}:${encodeURIComponent(serviceRoleKey)}@ap-southeast-1.pooler.supabase.com:6543/postgres` },
  { name: 'pooler ap-southeast-2', connString: `postgresql://postgres.${projectRef}:${encodeURIComponent(serviceRoleKey)}@ap-southeast-2.pooler.supabase.com:6543/postgres` },
  { name: 'pooler ap-south-1', connString: `postgresql://postgres.${projectRef}:${encodeURIComponent(serviceRoleKey)}@ap-south-1.pooler.supabase.com:6543/postgres` },
  { name: 'pooler us-east-1', connString: `postgresql://postgres.${projectRef}:${encodeURIComponent(serviceRoleKey)}@us-east-1.pooler.supabase.com:6543/postgres` },
];

async function tryConnect(conn: { name: string; connString: string }): Promise<boolean> {
  const client = new Client({ connectionString: conn.connString, connectionTimeoutMillis: 6000 });
  try {
    await client.connect();
    console.log(`✅ Connected: ${conn.name}`);

    // Run the combined SQL
    await client.query(combinedSQL);
    console.log('   ✅ Tables created (support_conversations, support_messages, order_problems)');

    // Verify tables exist
    const { rows } = await client.query(
      `SELECT table_name FROM information_schema.tables 
       WHERE table_schema = 'public' 
       AND table_name IN ('support_conversations', 'support_messages', 'order_problems')
       ORDER BY table_name`
    );
    console.log('   Tables in database:');
    rows.forEach((r: any) => console.log(`     - ${r.table_name}`));

    await client.end();
    return true;
  } catch (err: any) {
    const msg = err.message || String(err);
    console.log(`❌ ${conn.name}: ${msg.substring(0, 150)}`);
    await client.end().catch(() => {});
    return false;
  }
}

async function main() {
  for (const conn of connections) {
    const ok = await tryConnect(conn);
    if (ok) process.exit(0);
  }
  console.log('\n❌ All connections failed.');
  console.log('\nPlease run the SQL manually in the Supabase SQL editor:');
  console.log('1. Go to https://supabase.com/dashboard/project/hsiaguzxkytfsstvatep/sql/new');
  console.log('2. Paste the contents of these files:');
  console.log('   - scripts/create_support_tables.sql');
  console.log('   - scripts/create_order_problems_table.sql');
  console.log('3. Click "Run"');
  process.exit(1);
}

main();
