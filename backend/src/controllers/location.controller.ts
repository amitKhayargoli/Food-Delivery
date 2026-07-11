import { Request, Response } from 'express';
import { supabase } from '../db/supabase';
import { getUserId } from '../utils/auth';

// ──────────────────────────────────────────────
// PATCH /api/location/ping
// Upsert the rider's current GPS position.
// Called every 5-10 seconds by the rider app.
// ──────────────────────────────────────────────
export const pingLocation = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const { latitude, longitude, heading, speed, accuracy } = req.body;

    if (latitude == null || longitude == null) {
      res.status(400).json({ error: 'latitude and longitude are required.' });
      return;
    }

    const now = new Date().toISOString();

    const { error: upsertError } = await supabase.admin
      .from('rider_locations')
      .upsert(
        {
          user_id: userId,
          latitude,
          longitude,
          heading: heading ?? null,
          speed: speed ?? null,
          accuracy: accuracy ?? null,
          is_online: true,
          last_active_at: now,
          updated_at: now,
        },
        { onConflict: 'user_id' },
      );

    if (upsertError) {
      console.error('[Location] Upsert error:', upsertError.message);
      res.status(500).json({ error: 'Failed to update location.' });
      return;
    }

    res.status(200).json({ status: 'ok' });
  } catch (error) {
    console.error('[Location] Ping error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// PATCH /api/location/offline
// Set the rider's is_online flag to false.
// Called when the rider goes offline or the app is closed.
// ──────────────────────────────────────────────
export const goOffline = async (req: Request, res: Response): Promise<void> => {
  try {
    const userId = await getUserId(req);
    if (!userId) {
      res.status(401).json({ error: 'Authentication required' });
      return;
    }

    const now = new Date().toISOString();

    const { error } = await supabase.admin
      .from('rider_locations')
      .update({
        is_online: false,
        updated_at: now,
      })
      .eq('user_id', userId);

    if (error) {
      console.error('[Location] Offline error:', error.message);
      res.status(500).json({ error: 'Failed to go offline.' });
      return;
    }

    res.status(200).json({ status: 'offline' });
  } catch (error) {
    console.error('[Location] Offline error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// GET /api/location/rider/:id
// Get a specific rider's current location.
// ──────────────────────────────────────────────
export const getRiderLocation = async (req: Request, res: Response): Promise<void> => {
  try {
    const { id } = req.params;

    const { data: location, error } = await supabase.admin
      .from('rider_locations')
      .select('user_id, latitude, longitude, heading, speed, accuracy, is_online, is_on_delivery, last_active_at')
      .eq('user_id', id)
      .maybeSingle();

    if (error) {
      console.error('[Location] Fetch rider error:', error.message);
      res.status(500).json({ error: 'Failed to fetch rider location.' });
      return;
    }

    if (!location) {
      res.status(404).json({ error: 'Rider location not found.' });
      return;
    }

    res.status(200).json({ location });
  } catch (error) {
    console.error('[Location] Get rider error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};

// ──────────────────────────────────────────────
// GET /api/location/nearby?lat=...&lng=...&limit=5&radius_km=10
// Find nearest online, non-delivering riders to a point.
// Uses the PostGIS KNN function created in the migration.
// ──────────────────────────────────────────────
export const getNearbyRiders = async (req: Request, res: Response): Promise<void> => {
  try {
    const lat = parseFloat(req.query.lat as string);
    const lng = parseFloat(req.query.lng as string);
    const limit = Math.min(Math.max(parseInt(req.query.limit as string) || 5, 1), 20);
    const radiusKm = Math.min(Math.max(parseFloat(req.query.radius_km as string) || 10, 1), 50);

    if (isNaN(lat) || isNaN(lng)) {
      res.status(400).json({ error: 'lat and lng query parameters are required.' });
      return;
    }

    const { data: riders, error } = await supabase.admin.rpc('find_nearest_riders', {
      p_lat: lat,
      p_lng: lng,
      p_limit: limit,
      p_max_radius_km: radiusKm,
    });

    if (error) {
      console.error('[Location] Nearby riders error:', error.message);
      res.status(500).json({ error: 'Failed to find nearby riders.' });
      return;
    }

    // Enrich with user details (username, phone)
    if (riders && riders.length > 0) {
      const userIds = riders.map((r: any) => r.user_id);
      const { data: users } = await supabase.admin
        .from('users')
        .select('id, username, phone')
        .in('id', userIds);

      const userMap = new Map<string, any>();
      if (users) {
        for (const u of users) {
          userMap.set(u.id, u);
        }
      }

      const enriched = riders.map((r: any) => ({
        ...r,
        username: userMap.get(r.user_id)?.username ?? 'Unknown',
        phone: userMap.get(r.user_id)?.phone ?? null,
      }));

      res.status(200).json({ riders: enriched });
      return;
    }

    res.status(200).json({ riders: [] });
  } catch (error) {
    console.error('[Location] Nearby error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
};
