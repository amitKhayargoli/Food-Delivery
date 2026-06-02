import 'package:flutter/material.dart';
import 'dart:math';

class OrderConfirmedScreen extends StatefulWidget {
  final String paymentMethod;
  final String? deliveryAddress;
  final double totalAmount;

  const OrderConfirmedScreen({
    super.key,
    required this.paymentMethod,
    this.deliveryAddress,
    required this.totalAmount,
  });

  @override
  State<OrderConfirmedScreen> createState() => _OrderConfirmedScreenState();
}

class _OrderConfirmedScreenState extends State<OrderConfirmedScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;

  final String _orderNumber = _generateOrderNumber();
  final String _estimatedTime = '${Random().nextInt(20) + 20}';

  static String _generateOrderNumber() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rand = Random();
    return '#DAILO-${chars[rand.nextInt(chars.length)]}${rand.nextInt(10)}${rand.nextInt(10)}${rand.nextInt(10)}${rand.nextInt(10)}';
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: const ElasticOutCurve(0.8),
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.4, 1.0, curve: Curves.easeOut),
      ),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // ── Scrollable content ──
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
                child: Column(
                  children: [
                    // Success animation
                    AnimatedBuilder(
                      animation: _scaleAnimation,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: _scaleAnimation.value,
                          child: child,
                        );
                      },
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: const ShapeDecoration(
                          gradient: LinearGradient(
                            begin: Alignment(0.41, -0.41),
                            end: Alignment(0.59, 1.41),
                            colors: [Color(0xFF4CAF50), Color(0xFF66BB6A)],
                          ),
                          shape: OvalBorder(),
                          shadows: [
                            BoxShadow(
                              color: Color(0x334CAF50),
                              blurRadius: 20,
                              offset: Offset(0, 8),
                              spreadRadius: -4,
                            ),
                          ],
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.check_rounded,
                            size: 48,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Order Confirmed text
                    FadeTransition(
                      opacity: _fadeAnimation,
                      child: Column(
                        children: [
                          const Text(
                            'Order Confirmed!',
                            style: TextStyle(
                              color: Color(0xFF1A1A1A),
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Your order has been placed successfully',
                            style: TextStyle(
                              color: const Color(0xFF666666),
                              fontSize: 15,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          const SizedBox(height: 32),

                          // Order number card
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 16,
                            ),
                            decoration: ShapeDecoration(
                              color: const Color(0xFFFFF8F8),
                              shape: RoundedRectangleBorder(
                                side: const BorderSide(
                                  width: 1,
                                  color: Color(0x1AF5222D),
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: ShapeDecoration(
                                    color: const Color(0xFFFFF1F0),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  child: const Center(
                                    child: Icon(
                                      Icons.receipt_long_rounded,
                                      color: Color(0xFFF5222D),
                                      size: 22,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Order Number',
                                        style: TextStyle(
                                          color: Color(0xFF999999),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w400,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _orderNumber,
                                        style: const TextStyle(
                                          color: Color(0xFF1A1A1A),
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () {
                                    // Copy to clipboard
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content:
                                            Text('Order number copied!'),
                                        duration: Duration(seconds: 1),
                                      ),
                                    );
                                  },
                                  child: Container(
                                    width: 36,
                                    height: 36,
                                    decoration: ShapeDecoration(
                                      color: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.copy_rounded,
                                      size: 16,
                                      color: Color(0xFF999999),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Estimated delivery time card
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 16,
                            ),
                            decoration: ShapeDecoration(
                              color: const Color(0xFFF5FFF5),
                              shape: RoundedRectangleBorder(
                                side: const BorderSide(
                                  width: 1,
                                  color: Color(0x1A4CAF50),
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: ShapeDecoration(
                                    color: const Color(0xFFE8F5E9),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  child: const Center(
                                    child: Icon(
                                      Icons.timer_outlined,
                                      color: Color(0xFF4CAF50),
                                      size: 22,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Estimated Delivery',
                                        style: TextStyle(
                                          color: Color(0xFF999999),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w400,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '$_estimatedTime minutes',
                                        style: const TextStyle(
                                          color: Color(0xFF1A1A1A),
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: ShapeDecoration(
                                    color: const Color(0xFF4CAF50),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                  ),
                                  child: const Text(
                                    'On Time',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Divider
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Divider(
                                    color: Color(0xFFF0F0F0),
                                    thickness: 1,
                                  ),
                                ),
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 16),
                                  child: Text(
                                    'Order Summary',
                                    style: TextStyle(
                                      color: Color(0xFF999999),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Divider(
                                    color: Color(0xFFF0F0F0),
                                    thickness: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Delivery address (if provided)
                          if (widget.deliveryAddress != null) ...[
                            _buildSummaryRow(
                              icon: Icons.location_on_outlined,
                              iconColor: const Color(0xFFF5222D),
                              label: 'Delivery Address',
                              value: widget.deliveryAddress!,
                            ),
                            const SizedBox(height: 16),
                          ],

                          // Payment method
                          _buildSummaryRow(
                            icon: Icons.payment_outlined,
                            iconColor: const Color(0xFF4CAF50),
                            label: 'Payment Method',
                            value: widget.paymentMethod,
                          ),
                          const SizedBox(height: 16),

                          // Total amount
                          _buildSummaryRow(
                            icon: Icons.receipt_outlined,
                            iconColor: const Color(0xFF1A1A1A),
                            label: 'Total Amount',
                            value: 'रु${widget.totalAmount.toStringAsFixed(2)}',
                            valueStyle: const TextStyle(
                              color: Color(0xFFF5222D),
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Bottom Buttons ──
            Container(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              decoration: const BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x0C000000),
                    blurRadius: 4,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Track Order button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Track Order coming soon'),
                            behavior: SnackBarBehavior.floating,
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF5222D),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.near_me_rounded, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Track Order',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Back to Home button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.popUntil(context, (route) => route.isFirst);
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF1A1A1A),
                        shape: RoundedRectangleBorder(
                          side: const BorderSide(
                            width: 1,
                            color: Color(0xFFE8E8E8),
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.home_outlined, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Back to Home',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    TextStyle? valueStyle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: ShapeDecoration(
            color: iconColor.withValues(alpha: 0.10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: Center(
            child: Icon(icon, color: iconColor, size: 18),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF999999),
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: valueStyle ??
                    const TextStyle(
                      color: Color(0xFF1A1A1A),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
