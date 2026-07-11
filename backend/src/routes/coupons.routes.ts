import { Router } from 'express';
import {
  validateCoupon,
  createCoupon,
  getMyCoupons,
  getAvailableCoupons,
  deleteCoupon,
  applyCoupon,
} from '../controllers/coupons.controller';

const router = Router();

// POST /api/coupons/validate — validate a coupon code and return discount info
router.post('/validate', validateCoupon);

// POST /api/coupons — create a new coupon (owner or admin)
router.post('/', createCoupon);

// GET /api/coupons/my — list coupons for the owner's restaurant (or all for admin)
router.get('/my', getMyCoupons);

// GET /api/coupons/available — fetch active coupons for a restaurant (customer-facing)
router.get('/available', getAvailableCoupons);

// DELETE /api/coupons/:id — delete a coupon
router.delete('/:id', deleteCoupon);

// POST /api/coupons/:id/apply — increment coupon usage count after order
router.post('/:id/apply', applyCoupon);

export default router;
