import { Router } from 'express';
import {
  applyForRider,
  getMyRiderApplication,
  getAllRiderApplications,
  updateRiderApplicationStatus,
} from '../controllers/riders.controller';

const router = Router();

router.post('/apply', applyForRider);
router.get('/apply/my', getMyRiderApplication);
router.get('/apply', getAllRiderApplications);
router.patch('/apply/:id/status', updateRiderApplicationStatus);

export default router;
