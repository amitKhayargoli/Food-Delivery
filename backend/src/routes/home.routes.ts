import { Router } from 'express';
import { getHomeSuggestions, surpriseMe, getPersonalized } from '../controllers/home.controller';

const router = Router();

// GET /api/home/suggestions — time-of-day curated home screen data
router.get('/suggestions', getHomeSuggestions);

// GET /api/home/surprise-me — pick a random restaurant the user hasn't tried
router.get('/surprise-me', surpriseMe);

// GET /api/home/personalized — favorite restaurants & most ordered items
router.get('/personalized', getPersonalized);

export default router;
