/**
 * Migration: Add missing columns to order_items table.
 *
 * Run with: npx ts-node scripts/add_order_items_columns.ts
 */
import pg from 'pg';
import dotenv from 'dotenv';
import path from 'path';
dotenv.config({ path: path.join(__dirname, '..', '.env') });

const { SUPABASE_URL: url, SUPABASE_SERVICE_ROLE_KEY: key } = process.env;
const ref = url!.replace('https://', '').replace('.supabase.co', '');

const sql = [
  `ALTER TABLE IF EXISTS public.order_items ADD COLUMN IF NOT EXISTS name TEXT NOT NULL DEFAULT '';`,
  `ALTER TABLE IF EXISTS public.order_items ADD COLUMN IF NOT EXISTS price DECIMAL(10,2) NOT NULL DEFAULT 0;`,
  `ALTER TABLE IF EXISTS public.order_items ADD COLUMN IF NOT EXISTS quantity INTEGER NOT NULL DEFAULT 1;`,
  `ALTER TABLE IF EXISTS public.order_items ADD COLUMN IF NOT EXISTS image_url TEXT;`,
  `ALTER TABLE IF EXISTS public.order_items ADD COLUMN IF NOT EXISTS special_instructions TEXT;`,
];

const connections = [
  `postgresql://postgres:${encodeURIComponent(key!)}@db.${ref}.supabase.co:5432/postgres`,
  `postgresql://postgres:${encodeURIComponent(key!)}@db.${ref}.supabase.co:6543/postgres`,
];

async function run() {
  for (const cs of connections) {
    const client = new pg.Client({ connectionString: cs, connectionTimeoutMillis: 5000 });
    try {
      await client.connect();
      console.log('Connected');
      for (const stmt of sql) {
        await client.query(stmt);
        console.log('  OK:', stmt.substring(0, 60));
      }
      // Verify
      const { rows } = await client.query(
        `SELECT column_name, data_type FROM information_schema.columns
         WHERE table_schema = 'public' AND table_name = 'order_items'
         ORDER BY ordinal_position`
      );
      console.log('\nColumns:');
      rows.forEach((r: any) => console.log(`  ${r.column_name} (${r.data_type})`));
      await client.end();
      return;
    } catch (e: any) {
      console.log('Failed:', cs.substring(0, 50), e.message?.substring(0, 80));
      await client.end().catch(() => {});
    }
  }
  console.log('\nRun this SQL in Supabase Dashboard SQL Editor:\n');
  sql.forEach(s => console.log(s + '\n'));
}

run().catch(console.error);
