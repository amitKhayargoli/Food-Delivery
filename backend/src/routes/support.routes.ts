import { Router } from 'express';
import {
  createConversation,
  getMyConversations,
  getAllConversations,
  getMessages,
  sendMessage,
  closeConversation,
} from '../controllers/support.controller';

const router = Router();

// Customer endpoints
router.post('/conversations', createConversation);
router.get('/conversations', getMyConversations);
router.get('/conversations/:id/messages', getMessages);
router.post('/conversations/:id/messages', sendMessage);
router.patch('/conversations/:id/close', closeConversation);

// Admin endpoints
router.get('/conversations/admin/all', getAllConversations);

export default router;
