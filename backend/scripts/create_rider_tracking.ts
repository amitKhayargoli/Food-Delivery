/**
 * Rider Location Tracking — Migration Script
 *
 * Creates:
 *   - rider_locations table with PostGIS spatial column
 *   - GiST index for efficient KNN nearest-rider lookups
 *   - sync_rider_geo() trigger to keep geo in sync
 *   - find_nearest_riders() function (indexed KNN)
 *   - cleanup_stale_riders() function
 *   - RLS policies
 *
 * Run via:
 *   npx ts-node backend/scripts/create_rider_tracking.ts
 *
 * Or paste backend/scripts/create_rider_tracking.sql into the
 * Supabase SQL editor.
 */
import { Client } from 'pg';
import dotenv from 'dotenv';
import * as path from 'path';
dotenv.config({ path: path.join(__dirname, '..', '.env') });

const projectRef = process.env.SUPABASE_URL!.replace('https://', '').replace('.supabase.co', '');
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY!;

const createSQL = `
-- 1. Enable PostGIS (idempotent)
CREATE EXTENSION IF NOT EXISTS postgis;

-- 2. Create the rider_locations table
CREATE TABLE IF NOT EXISTS public.rider_locations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE UNIQUE,
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  heading REAL,
  speed REAL,
  accuracy REAL,
  is_online BOOLEAN NOT NULL DEFAULT false,
  is_on_delivery BOOLEAN NOT NULL DEFAULT false,
  last_active_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  geo GEOGRAPHY(POINT, 4326)
);

-- Ensure spatial column exists on re-runs (CREATE TABLE IF NOT EXISTS
-- won't add columns to an existing table).
ALTER TABLE public.rider_locations ADD COLUMN IF NOT EXISTS geo GEOGRAPHY(POINT, 4326);

-- 3. Indexes
CREATE INDEX IF NOT EXISTS idx_rider_locations_user_id
  ON public.rider_locations (user_id);

CREATE INDEX IF NOT EXISTS idx_rider_locations_online
  ON public.rider_locations (last_active_at DESC)
  WHERE is_online = true;

CREATE INDEX IF NOT EXISTS idx_rider_locations_geo
  ON public.rider_locations USING GIST (geo)
  WHERE is_online = true AND is_on_delivery = false;

-- 4. Trigger: keep geo column in sync
CREATE OR REPLACE FUNCTION public.sync_rider_geo() RETURNS TRIGGER AS $$
BEGIN
  NEW.geo := ST_SetSRID(ST_MakePoint(NEW.longitude, NEW.latitude), 4326)::GEOGRAPHY;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_sync_rider_geo ON public.rider_locations;
CREATE TRIGGER trg_sync_rider_geo
  BEFORE INSERT OR UPDATE OF latitude, longitude ON public.rider_locations
  FOR EACH ROW EXECUTE FUNCTION public.sync_rider_geo();

-- 5. RLS
ALTER TABLE public.rider_locations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Riders can upsert their own location" ON public.rider_locations;
CREATE POLICY "Riders can upsert their own location"
  ON public.rider_locations FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Riders can update their own location"
  ON public.rider_locations FOR UPDATE
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Owners can view online riders" ON public.rider_locations;
CREATE POLICY "Owners can view online riders"
  ON public.rider_locations FOR SELECT
  USING (is_online = true OR auth.uid() = user_id);

-- 6. KNN nearest-riders function
CREATE OR REPLACE FUNCTION public.find_nearest_riders(
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION,
  p_limit INTEGER DEFAULT 5,
  p_max_radius_km DOUBLE PRECISION DEFAULT 10
) RETURNS TABLE(
  user_id UUID,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  distance_km DOUBLE PRECISION,
  heading REAL,
  last_active_at TIMESTAMPTZ
) LANGUAGE sql STABLE
AS $$
  SELECT
    rl.user_id,
    rl.latitude,
    rl.longitude,
    ST_Distance(rl.geo, ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::GEOGRAPHY) / 1000.0 AS distance_km,
    rl.heading,
    rl.last_active_at
  FROM public.rider_locations rl
  WHERE rl.is_online = true
    AND rl.is_on_delivery = false
    AND ST_DWithin(rl.geo, ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::GEOGRAPHY, p_max_radius_km * 1000)
  ORDER BY rl.geo <-> ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::GEOGRAPHY
  LIMIT p_limit;
$$;

-- 7. Stale rider cleanup function
CREATE OR REPLACE FUNCTION public.cleanup_stale_riders(
  p_stale_seconds INTEGER DEFAULT 90
) RETURNS INTEGER LANGUAGE plpgsql
AS $$
DECLARE
  v_updated INTEGER;
BEGIN
  UPDATE public.rider_locations
  SET is_online = false,
      updated_at = NOW()
  WHERE is_online = true
    AND EXTRACT(EPOCH FROM (NOW() - last_active_at)) > p_stale_seconds;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN v_updated;
END;
$$;

-- 8. Enable Realtime for live GPS updates
ALTER PUBLICATION supabase_realtime ADD TABLE ONLY public.rider_locations;
`;

interface ConnectionAttempt {
  name: string;
  connString: string;
}

function buildConnections(): ConnectionAttempt[] {
  const escapedKey = encodeURIComponent(serviceRoleKey);
  return [
    { name: 'direct (port 5432)', connString: `postgresql://postgres:${escapedKey}@db.${projectRef}.supabase.co:5432/postgres` },
    { name: 'direct (port 6543)', connString: `postgresql://postgres:${escapedKey}@db.${projectRef}.supabase.co:6543/postgres` },
    { name: 'pooler ap-southeast-1', connString: `postgresql://postgres.${projectRef}:${escapedKey}@ap-southeast-1.pooler.supabase.com:6543/postgres` },
    { name: 'pooler ap-southeast-2', connString: `postgresql://postgres.${projectRef}:${escapedKey}@ap-southeast-2.pooler.supabase.com:6543/postgres` },
    { name: 'pooler ap-south-1', connString: `postgresql://postgres.${projectRef}:${escapedKey}@ap-south-1.pooler.supabase.com:6543/postgres` },
    { name: 'pooler us-east-1', connString: `postgresql://postgres.${projectRef}:${escapedKey}@us-east-1.pooler.supabase.com:6543/postgres` },
    { name: 'pooler (anon) ap-southeast-1', connString: `postgresql://postgres.${projectRef}:${escapedKey}@ap-southeast-1.pooler.supabase.com:5432/postgres` },
  ];
}

async function tryConnect(conn: ConnectionAttempt): Promise<boolean> {
  const client = new Client({ connectionString: conn.connString, connectionTimeoutMillis: 6000 });
  try {
    await client.connect();
    console.log(`✅ Connected: ${conn.name}`);

    await client.query(createSQL);
    console.log('   ✅ rider_locations table created!');

    const { rows } = await client.query(
      `SELECT column_name, data_type, is_nullable
       FROM information_schema.columns
       WHERE table_schema = 'public' AND table_name = 'rider_locations'
       ORDER BY ordinal_position`
    );
    console.log('   Columns:');
    rows.forEach((r: any) => console.log(`     - ${r.column_name} (${r.data_type})`));

    // Verify the function was created
    const { rows: funcs } = await client.query(
      `SELECT proname FROM pg_proc
       WHERE proname IN ('find_nearest_riders', 'cleanup_stale_riders', 'sync_rider_geo')`
    );
    console.log('   Functions:');
    funcs.forEach((f: any) => console.log(`     - ${f.proname}()`));

    await client.end();
    return true;
  } catch (err: any) {
    const msg = err.message || String(err);
    console.log(`❌ ${conn.name}: ${msg.substring(0, 120)}`);
    await client.end().catch(() => {});
    return false;
  }
}

async function main() {
  console.log('Creating rider tracking infrastructure...\n');
  console.log(`Project ref: ${projectRef}\n`);

  const connections = buildConnections();

  for (const conn of connections) {
    const ok = await tryConnect(conn);
    if (ok) {
      console.log('\n✅ Migration complete.');
      process.exit(0);
    }
  }

  console.log('\n❌ All connections failed.');
  console.log('Please run the SQL manually via the Supabase SQL editor:');
  console.log('  → backend/scripts/create_rider_tracking.sql');
  process.exit(1);
}

main();
