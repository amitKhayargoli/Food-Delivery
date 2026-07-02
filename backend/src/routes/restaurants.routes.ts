import { Router } from 'express';
import { getRestaurants } from '../controllers/restaurants.controller';

const router = Router();

// GET /api/restaurants — public list of approved restaurants with menu items
router.get('/', getRestaurants);

export default router;
