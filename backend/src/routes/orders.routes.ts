import { Router } from 'express';
import {
  createOrder,
  getRestaurantOrders,
  getOrderById,
  getMyOrders,
  searchOrders,
  getMyDeliveryJobs,
  getOrderHistory,
  acceptOrder,
  rejectOrder,
  cancelOrder,
  markAsPreparing,
  markAsReady,
  markAsPickedUp,
  markAsDelivered,
  getRiderStats,
  getDeliveryBoys,
  assignDeliveryBoy,
  declineOrder,
  addRiderNote,
  getAllOrders,
} from '../controllers/orders.controller';

const router = Router();

// Create order (customer checkout)
router.post('/', createOrder);

// Customer orders
router.get('/my', getMyOrders);

// Delivery boy assigned jobs
router.get('/delivery/my', getMyDeliveryJobs);

// Delivery rider stats — MUST be placed before /:id to avoid route conflict
router.get('/delivery/stats', getRiderStats);

// Customer order history — MUST be placed before /:id to avoid route conflict
router.get('/history', getOrderHistory);

// Owner order search — MUST be placed before /:id to avoid route conflict
router.get('/search', searchOrders);

// Admin endpoints
router.get('/admin/all', getAllOrders);

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
router.patch('/:id/cancel', cancelOrder);
router.patch('/:id/decline', declineOrder);
router.patch('/:id/deliver', markAsDelivered);
router.patch('/:id/rider-note', addRiderNote);

export default router;
