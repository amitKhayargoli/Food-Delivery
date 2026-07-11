import 'package:flutter/material.dart';
import '../core/services/api_service.dart';

/// Tracks the currently applied coupon during checkout.
/// Manages validation, discount calculation, and clearing.
class CouponProvider with ChangeNotifier {
  final ApiService _api;

  CouponProvider(this._api);

  // ── State ──

  String? _appliedCode;
  String? _couponId;
  double _discountAmount = 0.0;
  String? _discountDescription;
  bool _isValidating = false;
  String? _error;

  // ── Getters ──

  bool get hasAppliedCoupon => _appliedCode != null && _couponId != null && _discountAmount > 0;
  String? get appliedCode => _appliedCode;
  String? get couponId => _couponId;
  double get discountAmount => _discountAmount;
  String? get discountDescription => _discountDescription;
  bool get isValidating => _isValidating;
  String? get error => _error;

  /// The final total after subtracting discount from [subtotal].
  double totalAfterDiscount(double subtotal) {
    final discounted = subtotal - _discountAmount;
    return discounted > 0 ? discounted : 0;
  }

  // ── Actions ──

  /// Validate a coupon code and apply it if valid.
  Future<bool> applyCoupon({
    required String code,
    required double orderTotal,
    String? restaurantId,
    required String token,
  }) async {
    if (code.trim().isEmpty) return false;

    setState(isValidating: true, error: null);

    try {
      final response = await _api.validateCoupon(
        code: code.trim(),
        orderTotal: orderTotal,
        restaurantId: restaurantId,
        token: token,
      );

      if (response.valid && response.discountAmount != null) {
        _appliedCode = response.code ?? code.trim().toUpperCase();
        _couponId = response.couponId;
        _discountAmount = response.discountAmount!;
        _discountDescription = response.description;
        setState(isValidating: false, error: null);
        return true;
      } else {
        clearCoupon();
        setState(isValidating: false, error: response.error ?? 'Invalid coupon code.');
        return false;
      }
    } on ApiException catch (e) {
      clearCoupon();
      setState(isValidating: false, error: e.message);
      return false;
    } catch (e) {
      clearCoupon();
      setState(isValidating: false, error: 'Failed to validate coupon.');
      return false;
    }
  }

  /// Remove the applied coupon.
  void clearCoupon() {
    _appliedCode = null;
    _couponId = null;
    _discountAmount = 0.0;
    _discountDescription = null;
    _error = null;
    notifyListeners();
  }

  void setState({
    bool? isValidating,
    String? error,
  }) {
    _isValidating = isValidating ?? _isValidating;
    if (error != null) _error = error;
    notifyListeners();
  }
}
