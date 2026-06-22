import { Router } from 'express';
import {
  applyForRestaurant,
  getMyApplication,
  getAllApplications,
  updateApplicationStatus,
  getMyRestaurantProfile,
  updateRestaurantProfile,
  toggleAcceptingOrders,
} from '../controllers/restaurant.controller';

const router = Router();

router.post('/', applyForRestaurant);
router.get('/my', getMyApplication);
router.get('/my/profile', getMyRestaurantProfile);
router.put('/my/profile', updateRestaurantProfile);
router.patch('/my/accepting-orders', toggleAcceptingOrders);
router.get('/', getAllApplications);
router.patch('/:id/status', updateApplicationStatus);

export default router;
