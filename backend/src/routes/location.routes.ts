import { Router } from 'express';
import {
  pingLocation,
  goOffline,
  getRiderLocation,
  getNearbyRiders,
} from '../controllers/location.controller';

const router = Router();

// Rider GPS ping — upserts rider location and sets is_online = true
router.patch('/ping', pingLocation);

// Rider goes offline
router.patch('/offline', goOffline);

// Get a specific rider's current location
router.get('/rider/:id', getRiderLocation);

// Find nearest online riders to a point (used by owner dashboard)
router.get('/nearby', getNearbyRiders);

export default router;
