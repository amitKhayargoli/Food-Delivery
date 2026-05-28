import { Router } from 'express';
import {
  register,
  login,
  googleAuth,
  completeProfile,
  checkAvailability,
  sendOtp,
  verifyOtp,
} from '../controllers/auth.controller';

const router = Router();

router.post('/register', register);
router.post('/login', login);
router.post('/google', googleAuth);
router.post('/complete-profile', completeProfile);
router.post('/check-availability', checkAvailability);
router.post('/send-otp', sendOtp);
router.post('/verify-otp', verifyOtp);

export default router;
