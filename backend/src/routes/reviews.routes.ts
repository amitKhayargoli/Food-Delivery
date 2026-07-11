import { Router } from 'express';
import {
  createReview,
  getRestaurantReviews,
  getMyReviews,
  getOwnerReviews,
  updateReview,
  deleteReview,
  adminDeleteReview,
} from '../controllers/reviews.controller';

const router = Router();

// Public: get reviews for a restaurant
router.get('/restaurant/:restaurantId', getRestaurantReviews);

// Authenticated: create a review
router.post('/', createReview);

// Authenticated: get my reviews
router.get('/my', getMyReviews);

// Owner: get reviews for my restaurant
router.get('/owner', getOwnerReviews);

// Authenticated: update my review
router.put('/:reviewId', updateReview);

// Authenticated: delete my review
router.delete('/:reviewId', deleteReview);

// Admin: delete any review
router.delete('/admin/:reviewId', adminDeleteReview);

export default router;
