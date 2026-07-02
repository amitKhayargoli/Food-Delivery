/**
 * Automated Dispatch Service
 *
 * Phase 3 of the dispatch system. When an order reaches OUT_FOR_DELIVERY
 * status and the restaurant has auto_dispatch_enabled = true, this service
 * finds the nearest eligible rider, scores candidates, atomically claims
 * the best rider, and sends an FCM push notification.
 *
 * Algorithm:
 *   1. Fetch restaurant lat/lng from restaurant_applications
 *   2. Call find_nearest_riders() PostGIS KNN function (up to 5 candidates)
 *   3. Score each rider on distance, heading, and fairness
 *   4. Try to claim the best rider atomically
 *   5. If already taken, try the next candidate
 *   6. Send FCM push to the assigned rider
 *   7. Log dispatch decision to order.dispatch_metadata
 */

import { supabase } from '../db/supabase';
import { notifyUser } from './fcm.service';

interface RiderCandidate {
  user_id: string;
  latitude: number;
  longitude: number;
  distance_km: number;
  heading: number | null;
  last_active_at: string;
  score: number;
}

interface DispatchResult {
  assigned: boolean;
  riderId?: string;
  riderName?: string;
  reason?: string;
}

// ──────────────────────────────────────────────
//  Public entry point
// ──────────────────────────────────────────────

/**
 * Attempt to auto-assign the nearest eligible rider to an order.
 *
 * @param orderId     The order to assign
 * @param restaurantId The restaurant the order belongs to
 * @returns DispatchResult indicating success or failure
 */
export async function autoAssignRider(
  orderId: string,
  restaurantId: string,
  skipRiderIds: string[] = [],
): Promise<DispatchResult> {
  try {
    console.log(`[Dispatch] 🚚 Auto-assigning rider for order ${orderId}`);

    // 1. Fetch restaurant location
    const { data: restaurant, error: restError } = await supabase.admin
      .from('restaurant_applications')
      .select('id, restaurant_name, latitude, longitude')
      .eq('id', restaurantId)
      .maybeSingle();

    if (restError || !restaurant) {
      console.error('[Dispatch] Restaurant not found:', restError?.message);
      return { assigned: false, reason: 'Restaurant not found' };
    }

    const { latitude: restLat, longitude: restLng } = restaurant;
    if (restLat == null || restLng == null) {
      console.warn('[Dispatch] Restaurant has no location set — cannot auto-dispatch');
      return { assigned: false, reason: 'Restaurant location not configured' };
    }

    // 2. Find nearest riders via PostGIS KNN function
    const { data: riders, error: ridersError } = await supabase.admin.rpc(
      'find_nearest_riders',
      {
        p_lat: restLat,
        p_lng: restLng,
        p_limit: 5,
        p_max_radius_km: 15,
      },
    );

    if (ridersError) {
      console.error('[Dispatch] find_nearest_riders failed:', ridersError.message);
      return { assigned: false, reason: 'Failed to query nearby riders' };
    }

    if (!riders || riders.length === 0) {
      console.warn('[Dispatch] No online riders found nearby');
      return { assigned: false, reason: 'No riders available nearby' };
    }

    // Filter out riders that should be skipped (e.g. previously timed out/declined)
    const filteredRiders = skipRiderIds.length > 0
      ? riders.filter((r: any) => !skipRiderIds.includes(r.user_id))
      : riders;

    if (filteredRiders.length === 0) {
      console.warn('[Dispatch] All nearby riders have been already tried — none available');
      return { assigned: false, reason: 'All nearby riders have been tried' };
    }

    // 3. Score candidates
    const candidates: RiderCandidate[] = filteredRiders.map((r: any) => {
      let score = 100 - r.distance_km * 5; // Base: closer = higher (0-100 range)

      // Heading bonus: +10 if heading roughly toward restaurant
      if (r.heading != null) {
        const bearing = calculateBearing(
          r.latitude,
          r.longitude,
          restLat,
          restLng,
        );
        const headingDiff = Math.abs(r.heading - bearing);
        if (headingDiff < 30 || headingDiff > 330) {
          score += 10; // Heading toward restaurant
        }
      }

      // Recency bonus: +5 if last_active_at is within 15 seconds
      const lastActive = new Date(r.last_active_at).getTime();
      const now = Date.now();
      if (now - lastActive < 15_000) {
        score += 5; // Recently pinged = more reliable
      }

      return {
        user_id: r.user_id,
        latitude: r.latitude,
        longitude: r.longitude,
        distance_km: r.distance_km,
        heading: r.heading,
        last_active_at: r.last_active_at,
        score: Math.round(score * 10) / 10,
      };
    });

    // Sort by score descending (best first)
    candidates.sort((a, b) => b.score - a.score);
    console.log(
      `[Dispatch] Candidates scored:`,
      candidates.map((c) => ({
        riderId: c.user_id.slice(0, 8),
        distance: `${c.distance_km.toFixed(1)}km`,
        score: c.score,
      })),
    );

    // 4 & 5. Try to claim riders in order
    for (const candidate of candidates) {
      const claimed = await tryClaimRider(candidate.user_id, orderId);
      if (claimed) {
        // Fetch rider name for the notification
        const { data: userData } = await supabase.admin
          .from('users')
          .select('username')
          .eq('id', candidate.user_id)
          .maybeSingle();

        const riderName = userData?.username || 'Rider';

        // Build dispatch metadata
        const metadata = {
          distance_km: Math.round(candidate.distance_km * 100) / 100,
          score: candidate.score,
          rider_candidates: candidates.map((c) => ({
            user_id: c.user_id,
            distance_km: Math.round(c.distance_km * 100) / 100,
            score: c.score,
          })),
          assigned_at: new Date().toISOString(),
        };

        // Update the order
        const { error: updateError } = await supabase.admin
          .from('orders')
          .update({
            delivery_boy_id: candidate.user_id,
            assigned_at: new Date().toISOString(),
            assigned_by: 'SYSTEM',
            dispatch_metadata: JSON.stringify(metadata),
            updated_at: new Date().toISOString(),
          })
          .eq('id', orderId)
          .eq('status', 'OUT_FOR_DELIVERY')  // Defensive: order must still need a rider
          .is('delivery_boy_id', null);       // Defensive: no one else grabbed it

        if (updateError) {
          console.error('[Dispatch] Order update failed:', updateError.message);
          // Release rider claim if order update failed
          await releaseRider(candidate.user_id);
          continue; // Try next candidate
        }

        console.log(
          `[Dispatch] ✅ Assigned rider ${candidate.user_id.slice(0, 8)} ` +
            `to order ${orderId} (score: ${candidate.score}, distance: ${candidate.distance_km.toFixed(1)}km)`,
        );

        // 6. Send FCM push notification to the rider
        notifyUser(candidate.user_id, supabase.admin, {
          title: 'New Delivery Assigned 🚚',
          body: `Order #${orderId.slice(0, 8)} from ${restaurant.restaurant_name} has been assigned to you!`,
          data: {
            type: 'delivery_assigned',
            order_id: orderId,
            restaurant_name: restaurant.restaurant_name,
          },
        }).catch((err) =>
          console.error('[Dispatch] FCM notification error:', err),
        );

        return {
          assigned: true,
          riderId: candidate.user_id,
          riderName,
        };
      }
    }

    // All candidates exhausted
    console.warn('[Dispatch] All nearby riders busy — none could be claimed');
    return { assigned: false, reason: 'All nearby riders are currently on delivery' };
  } catch (error) {
    console.error('[Dispatch] Auto-assign error:', error);
    return { assigned: false, reason: 'Internal dispatch error' };
  }
}

// ──────────────────────────────────────────────
//  Atomic rider claim
// ──────────────────────────────────────────────

/**
 * Try to atomically claim a rider by setting is_on_delivery = true.
 * Only succeeds if the rider is currently NOT on delivery.
 *
 * Uses `.select().single()` on the UPDATE chain: if the WHERE clause
 * matches zero rows (e.g., rider already on delivery or offline),
 * `.single()` throws PGRST116 and we return false.
 * This prevents double-assignment when two dispatch threads race.
 */
async function tryClaimRider(
  riderId: string,
  _orderId: string,
): Promise<boolean> {
  const { data, error } = await supabase.admin
    .from('rider_locations')
    .update({
      is_on_delivery: true,
      updated_at: new Date().toISOString(),
    })
    .eq('user_id', riderId)
    .eq('is_on_delivery', false)  // Critical: only claim if not already on delivery
    .eq('is_online', true)        // Must still be online
    .select('is_on_delivery')
    .single();

  if (error) {
    // PGRST116: The result contains 0 rows — rider was already claimed or offline
    console.log(`[Dispatch] Claim rider ${riderId.slice(0, 8)} unavailable:`, error.message);
    return false;
  }

  return data?.is_on_delivery === true;
}

/**
 * Release a rider from delivery (rollback on failure).
 */
export async function releaseRider(riderId: string): Promise<void> {
  await supabase.admin
    .from('rider_locations')
    .update({
      is_on_delivery: false,
      updated_at: new Date().toISOString(),
    })
    .eq('user_id', riderId);
}

// ──────────────────────────────────────────────
//  Utility
// ──────────────────────────────────────────────

/**
 * Calculate bearing (compass direction) from point A to point B.
 * Returns degrees (0 = North, 90 = East, etc.).
 */
function calculateBearing(
  lat1: number,
  lng1: number,
  lat2: number,
  lng2: number,
): number {
  const toRad = (deg: number) => (deg * Math.PI) / 180;
  const toDeg = (rad: number) => (rad * 180) / Math.PI;

  const φ1 = toRad(lat1);
  const φ2 = toRad(lat2);
  const Δλ = toRad(lng2 - lng1);

  const y = Math.sin(Δλ) * Math.cos(φ2);
  const x =
    Math.cos(φ1) * Math.sin(φ2) -
    Math.sin(φ1) * Math.cos(φ2) * Math.cos(Δλ);

  const bearing = toDeg(Math.atan2(y, x));
  return (bearing + 360) % 360;
}
