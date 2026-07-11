import { Router } from 'express';
import {
  getDeliveryLocation,
  updateDeliveryLocation,
  updateAvatar,
  updateProfile,
} from '../controllers/profile.controller';

const router = Router();

router.patch('/', updateProfile);
router.get('/delivery-location', getDeliveryLocation);
router.patch('/delivery-location', updateDeliveryLocation);
router.patch('/avatar', updateAvatar);

export default router;
