import { Router } from 'express';
import {
  applyForRestaurant,
  getMyApplication,
  getAllApplications,
  updateApplicationStatus,
  updateRestaurant,
  toggleAcceptingOrders,
} from '../controllers/restaurant.controller';

const router = Router();

router.post('/', applyForRestaurant);
router.get('/my', getMyApplication);
router.put('/my', updateRestaurant);
router.patch('/my/accepting-orders', toggleAcceptingOrders);
router.get('/', getAllApplications);
router.patch('/:id/status', updateApplicationStatus);

export default router;
