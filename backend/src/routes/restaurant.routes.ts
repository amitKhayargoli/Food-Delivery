import { Router } from 'express';
import {
  applyForRestaurant,
  getMyApplication,
  getAllApplications,
  updateApplicationStatus,
  updateRestaurant,
} from '../controllers/restaurant.controller';

const router = Router();

router.post('/', applyForRestaurant);
router.get('/my', getMyApplication);
router.put('/my', updateRestaurant);
router.get('/', getAllApplications);
router.patch('/:id/status', updateApplicationStatus);

export default router;
