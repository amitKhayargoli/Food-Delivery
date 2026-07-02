/**
 * Stale Rider Cleanup Service
 *
 * Periodically calls the cleanup_stale_riders() Postgres function to mark
 * riders as offline if they haven't pinged their GPS location within the
 * stale threshold (default 90 seconds).
 *
 * This ensures:
 *   1. Offline/ghost riders are excluded from find_nearest_riders() lookups.
 *   2. The owner/admin dashboard shows accurate online/offline status.
 *   3. Dispatch doesn't attempt to assign orders to riders who disconnected.
 *
 * The function already exists in the DB (created by
 * backend/scripts/create_rider_tracking.sql). This service just calls it
 * on a 30-second interval.
 */

import { supabase } from '../db/supabase';

const CLEANUP_INTERVAL_MS = 30_000; // 30 seconds
const STALE_THRESHOLD_S = 90; // 90 seconds since last ping = stale

let _intervalHandle: ReturnType<typeof setInterval> | null = null;

/**
 * Start the cleanup loop. Called once when the server boots.
 * Logs the first run and every subsequent run that cleans up at least one rider.
 */
export function startStaleRiderCleanup(): void {
  if (_intervalHandle) {
    console.warn('[StaleCleanup] Already running — skipping duplicate start.');
    return;
  }

  console.log(
    `[StaleCleanup] Starting — will run every ${CLEANUP_INTERVAL_MS / 1000}s ` +
    `(stale threshold: ${STALE_THRESHOLD_S}s)`,
  );

  // Run immediately on start, then every interval
  runCleanup();
  _intervalHandle = setInterval(runCleanup, CLEANUP_INTERVAL_MS);
}

/**
 * Stop the cleanup loop. Useful in tests or graceful shutdown.
 */
export function stopStaleRiderCleanup(): void {
  if (_intervalHandle) {
    clearInterval(_intervalHandle);
    _intervalHandle = null;
    console.log('[StaleCleanup] Stopped.');
  }
}

/**
 * Execute a single cleanup run.
 */
async function runCleanup(): Promise<void> {
  try {
    const { data, error } = await supabase.admin.rpc('cleanup_stale_riders', {
      p_stale_seconds: STALE_THRESHOLD_S,
    });

    if (error) {
      console.error('[StaleCleanup] RPC error:', error.message);
      return;
    }

    const cleanedCount = (data as number) ?? 0;
    if (cleanedCount > 0) {
      console.log(`[StaleCleanup] Marked ${cleanedCount} stale rider(s) as offline.`);
    }
  } catch (err) {
    console.error('[StaleCleanup] Unexpected error:', (err as Error).message);
  }
}
