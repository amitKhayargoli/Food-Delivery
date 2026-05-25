import { Router } from 'express';
import { register, login, googleAuth, completeProfile } from '../controllers/auth.controller';

const router = Router();

router.post('/register', register);
router.post('/login', login);
router.post('/google', googleAuth);
router.post('/complete-profile', completeProfile);

export default router;
