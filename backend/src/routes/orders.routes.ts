import { Router } from 'express';
import {
  getRestaurantOrders,
  getOrderById,
  acceptOrder,
  rejectOrder,
  markAsPreparing,
  markAsReady,
  getDeliveryBoys,
  assignDeliveryBoy,
} from '../controllers/orders.controller';

const router = Router();

// Restaurant owner endpoints
router.get('/restaurant', getRestaurantOrders);
router.get('/delivery-boys', getDeliveryBoys);
router.get('/:id', getOrderById);

// Order status transitions
router.patch('/:id/accept', acceptOrder);
router.patch('/:id/reject', rejectOrder);
router.patch('/:id/preparing', markAsPreparing);
router.patch('/:id/ready', markAsReady);
router.patch('/:id/assign', assignDeliveryBoy);

export default router;
