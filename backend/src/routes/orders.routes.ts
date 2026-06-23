import { Router } from 'express';
import {
  getRestaurantOrders,
  getOrderById,
  getMyOrders,
  searchOrders,
  getMyDeliveryJobs,
  getOrderHistory,
  acceptOrder,
  rejectOrder,
  markAsPreparing,
  markAsReady,
  markAsPickedUp,
  getDeliveryBoys,
  assignDeliveryBoy,
  addRiderNote,
} from '../controllers/orders.controller';

const router = Router();

// Customer orders
router.get('/my', getMyOrders);

// Delivery boy assigned jobs
router.get('/delivery/my', getMyDeliveryJobs);

// Customer order history — MUST be placed before /:id to avoid route conflict
router.get('/history', getOrderHistory);

// Owner order search — MUST be placed before /:id to avoid route conflict
router.get('/search', searchOrders);

// Restaurant owner endpoints
router.get('/restaurant', getRestaurantOrders);
router.get('/delivery-boys', getDeliveryBoys);
router.get('/:id', getOrderById);

// Order status transitions
router.patch('/:id/accept', acceptOrder);
router.patch('/:id/reject', rejectOrder);
router.patch('/:id/preparing', markAsPreparing);
router.patch('/:id/ready', markAsReady);
router.patch('/:id/picked-up', markAsPickedUp);
router.patch('/:id/assign', assignDeliveryBoy);
router.patch('/:id/rider-note', addRiderNote);

export default router;
