/**
 * Assignment Timeout Service
 *
 * Phase 2.2 fallback chain. Runs every 30 seconds and scans for
 * orders that have been assigned to a rider (status OUT_FOR_DELIVERY,
 * delivery_boy_id IS NOT NULL) but where the rider has not responded
 * within the timeout window (3 minutes).
 *
 * For each timed-out order:
 *   1. Release the current rider (is_on_delivery = false)
 *   2. Clear the assignment (delivery_boy_id = null)
 *   3. Log the timeout to dispatch_log
 *   4. Notify the restaurant owner about the timeout
 *   5. Attempt to auto-assign the next nearest rider (skipping the timed-out one)
 *   6. If no riders available, notify the owner (Phase 3.3 fallback)
 */

import { supabase } from '../db/supabase';
import { autoAssignRider, releaseRider } from './dispatch.service';
import { notifyUser } from './fcm.service';

/// How long a rider has to respond before timing out (milliseconds).
const TIMEOUT_MS = 3 * 60 * 1000; // 3 minutes

/// How often the scanner runs (milliseconds).
const SCAN_INTERVAL_MS = 30 * 1000; // 30 seconds

let _intervalHandle: ReturnType<typeof setInterval> | null = null;

// ──────────────────────────────────────────────
//  Public entry point
// ──────────────────────────────────────────────

/**
 * Start the assignment timeout scanner.
 * Runs immediately on call, then every 30 seconds.
 * Safe to call multiple times — duplicate start is detected.
 */
export function startAssignmentTimeoutScanner(): void {
  if (_intervalHandle) {
    console.warn('[AssignTimeout] Already running — skipping duplicate start.');
    return;
  }

  console.log(
    `[AssignTimeout] Starting — scanning every ${SCAN_INTERVAL_MS / 1000}s ` +
    `(timeout threshold: ${TIMEOUT_MS / 1000}s)`,
  );

  scan();
  _intervalHandle = setInterval(scan, SCAN_INTERVAL_MS);
}

/**
 * Stop the assignment timeout scanner (e.g. on server shutdown).
 */
export function stopAssignmentTimeoutScanner(): void {
  if (_intervalHandle) {
    clearInterval(_intervalHandle);
    _intervalHandle = null;
    console.log('[AssignTimeout] Stopped.');
  }
}

// ──────────────────────────────────────────────
//  Scan logic
// ──────────────────────────────────────────────

async function scan(): Promise<void> {
  try {
    const cutoff = new Date(Date.now() - TIMEOUT_MS).toISOString();

    const { data: orders, error } = await supabase.admin
      .from('orders')
      .select('id, order_number, delivery_boy_id, restaurant_id, assigned_at, user_id')
      .eq('status', 'OUT_FOR_DELIVERY')
      .not('delivery_boy_id', 'is', null)
      .lt('assigned_at', cutoff)
      .limit(10);

    if (error) {
      console.error('[AssignTimeout] Query error:', error.message);
      return;
    }

    if (!orders || orders.length === 0) return;

    console.log(`[AssignTimeout] Found ${orders.length} timed-out order(s) to reassign`);

    for (const order of orders) {
      await handleTimeout(order);
    }
  } catch (err) {
    console.error('[AssignTimeout] Scan error:', err);
  }
}

/**
 * Handle a single timed-out order: release rider, log, notify, reassign.
 */
async function handleTimeout(order: {
  id: string;
  order_number: string | null;
  delivery_boy_id: string | null;
  restaurant_id: string;
  assigned_at: string | null;
  user_id: string;
}): Promise<void> {
  const riderId = order.delivery_boy_id;
  if (!riderId) return;

  console.log(
    `[AssignTimeout] ⏰ Order ${order.id.slice(0, 8)} timed out for rider ${riderId.slice(0, 8)}`,
  );

  // 1. Release the rider
  await releaseRider(riderId);

  // 2. Clear the order assignment
  const { error: clearError } = await supabase.admin
    .from('orders')
    .update({
      delivery_boy_id: null,
      assigned_at: null,
      assigned_by: null,
      updated_at: new Date().toISOString(),
    })
    .eq('id', order.id);

  if (clearError) {
    console.error('[AssignTimeout] Clear assignment error:', clearError.message);
    return;
  }

  // 3. Log the timeout in dispatch_log (fire-and-forget)
  (async () => {
    const { error: logError } = await supabase.admin
      .from('dispatch_log')
      .insert({
        order_id: order.id,
        rider_id: riderId,
        assigned_by: 'SYSTEM',
        status: 'TIMEOUT',
      });
    if (logError) {
      console.error('[AssignTimeout] Log error:', logError.message);
    }
  })();

  // 4. Notify the restaurant owner about the timeout
  const { data: restaurant } = await supabase.admin
    .from('restaurant_applications')
    .select('user_id, restaurant_name')
    .eq('id', order.restaurant_id)
    .maybeSingle();

  if (restaurant?.user_id) {
    notifyUser(restaurant.user_id, supabase.admin, {
      title: 'Rider Assignment Timed Out ⏰',
      body: `Rider did not respond for order ${order.order_number || ''}. Reassigning to next available rider...`,
      data: {
        type: 'rider_timeout',
        order_id: order.id,
        rider_id: riderId,
        restaurant_id: order.restaurant_id,
      },
    }).catch((err: any) =>
      console.error('[AssignTimeout] Owner notification failed:', err?.message),
    );
  }

  // 5. Attempt to auto-assign the next nearest rider (skip the timed-out one)
  const result = await autoAssignRider(order.id, order.restaurant_id, [riderId]);

  // 6. If no riders available, notify owner (Phase 3.3 fallback)
  if (!result.assigned) {
    console.warn(
      `[AssignTimeout] ⚠️ Reassignment failed for order ${order.id.slice(0, 8)}: ${result.reason}`,
    );

    if (restaurant?.user_id) {
      notifyUser(restaurant.user_id, supabase.admin, {
        title: 'Delivery Reassignment Failed ⚠️',
        body: `Unable to reassign order ${order.order_number || ''}: ${result.reason || 'No riders available'}. Please assign manually.`,
        data: {
          type: 'reassignment_failed',
          order_id: order.id,
          restaurant_id: order.restaurant_id,
          reason: result.reason || '',
        },
      }).catch((err: any) =>
        console.error('[AssignTimeout] Reassign fail notification error:', err?.message),
      );
    }
  } else {
    console.log(
      `[AssignTimeout] ✅ Reassigned order ${order.id.slice(0, 8)} to rider ${result.riderId?.slice(0, 8)}`,
    );
  }
}
