import { Router } from 'express';
import {
  submitRating,
  getRiderRating,
  getMyRatings,
} from '../controllers/ratings.controller';

const router = Router();

// Submit a rating for a rider (authenticated customer)
router.post('/', submitRating);

// Get ratings submitted by the authenticated user
router.get('/my', getMyRatings);

// Get average rating for a specific rider
router.get('/rider/:riderId', getRiderRating);

export default router;
