import { Router } from 'express';
import {
  getAllRestaurants,
  getRestaurantById,
  getRestaurantMenu,
} from '../controllers/public.controller';

const router = Router();

router.get('/', getAllRestaurants);
router.get('/:id', getRestaurantById);
router.get('/:id/menu', getRestaurantMenu);

export default router;
