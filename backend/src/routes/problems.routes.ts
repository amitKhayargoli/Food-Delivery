import { Router } from 'express';
import {
  submitProblem,
  getMyProblems,
  getProblemByOrder,
  getRestaurantProblems,
  getAllProblems,
  updateProblemStatus,
} from '../controllers/problems.controller';

const router = Router();

// Customer endpoints
router.post('/', submitProblem);
router.get('/my', getMyProblems);
router.get('/order/:orderId', getProblemByOrder);

// Owner endpoint
router.get('/restaurant', getRestaurantProblems);

// Admin endpoint
router.get('/all', getAllProblems);

// Shared (owner + admin)
router.patch('/:id/status', updateProblemStatus);

export default router;
