import { Router } from 'express';
import {
  logDispatchEvent,
  getDispatchLogForOrder,
  getDispatchAnalytics,
  getAllRidersWithStats,
  createRider,
  getRiderPerformance,
} from '../controllers/dispatch.controller';

const router = Router();

// ── Dispatch Logging ──
router.post('/log', logDispatchEvent);
router.get('/log/:orderId', getDispatchLogForOrder);

// ── Owner Analytics ──
router.get('/analytics', getDispatchAnalytics);

// ── Admin Rider Management ──
router.get('/admin/riders', getAllRidersWithStats);
router.post('/admin/riders', createRider);
router.get('/admin/performance', getRiderPerformance);

export default router;
