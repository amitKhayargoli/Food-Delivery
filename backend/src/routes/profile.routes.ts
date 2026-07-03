import { Router } from 'express';
import {
  getDeliveryLocation,
  updateDeliveryLocation,
  updateAvatar,
} from '../controllers/profile.controller';

const router = Router();

router.get('/delivery-location', getDeliveryLocation);
router.patch('/delivery-location', updateDeliveryLocation);
router.patch('/avatar', updateAvatar);

export default router;
