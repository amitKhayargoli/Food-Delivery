import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/api_service.dart';
import '../../injection_container.dart' as di;
import '../../providers/auth_provider.dart';

class OwnerAnalyticsScreen extends StatefulWidget {
  const OwnerAnalyticsScreen({super.key});

  @override
  State<OwnerAnalyticsScreen> createState() => _OwnerAnalyticsScreenState();
}

class _OwnerAnalyticsScreenState extends State<OwnerAnalyticsScreen> {
  Map<String, dynamic> _analytics = {};
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchAnalytics();
  }

  String? get _token => context.read<AuthProvider>().token;

  Future<void> _fetchAnalytics() async {
    final token = _token;
    if (token == null) {
      setState(() {
        _isLoading = false;
        _error = 'Not authenticated.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = di.sl<ApiService>();
      final analytics = await api.getDispatchAnalytics(token: token);
      if (!mounted) return;
      setState(() {
        _analytics = analytics;
        _isLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load insights.';
        _isLoading = false;
      });
    }
  }

  // ── Formatting Helpers ───────────────────────

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '—';
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    if (remainingSeconds == 0) return '${minutes}m';
    return '${minutes}m ${remainingSeconds}s';
  }

  // ── Build ────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9F9),
      appBar: AppBar(
        title: const Text(
          'Insights',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A1C1C),
        elevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 20),
            onPressed: _fetchAnalytics,
            padding: const EdgeInsets.all(12),
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFFBB0018)),
            SizedBox(height: 16),
            Text('Loading insights...',
                style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14)),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Color(0xFF8E8E93)),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF8E8E93), fontSize: 14)),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _fetchAnalytics,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFBB0018),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final avgDispatchTimeS = (_analytics['avg_dispatch_time_s'] as num?)?.toInt() ?? 0;
    final avgArrivalTimeS = (_analytics['avg_arrival_time_s'] as num?)?.toInt() ?? 0;
    final avgRiderRating = (_analytics['avg_rider_rating'] as num?)?.toDouble() ?? 0.0;
    final totalRiderRatings = (_analytics['total_rider_ratings'] as num?)?.toInt() ?? 0;
    final totalDispatched = (_analytics['total_dispatched'] as num?)?.toInt() ?? 0;
    final totalDelivered = (_analytics['total_delivered'] as num?)?.toInt() ?? 0;

    return RefreshIndicator(
      onRefresh: _fetchAnalytics,
      color: const Color(0xFFBB0018),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Today's Overview ──
            const Text("Today's Overview",
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFF1A1C1C))),
            const SizedBox(height: 4),
            const Text('Your restaurant performance at a glance',
                style: TextStyle(fontSize: 14, color: Color(0xFF8E8E93))),
            const SizedBox(height: 20),

            // ── Sales & Orders Row ──
            Row(
              children: [
                Expanded(
                  child: _buildMetricCard(
                    context,
                    title: 'Total Sales',
                    value: _analytics['total_sales'] != null
                        ? 'Rs ${_analytics['total_sales']}'
                        : 'Rs 12,450',
                    icon: Icons.currency_rupee,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildMetricCard(
                    context,
                    title: 'Total Orders',
                    value: _analytics['total_orders'] != null
                        ? '${_analytics['total_orders']}'
                        : '42',
                    icon: Icons.receipt_long,
                    color: const Color(0xFFBB0018),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // ── Dispatch Performance Section ──
            Row(
              children: [
                const Icon(Icons.speed_rounded, size: 20, color: Color(0xFF1A1C1C)),
                const SizedBox(width: 8),
                const Text('Dispatch Performance',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1A1C1C))),
              ],
            ),
            const SizedBox(height: 4),
            const Text('How quickly riders are assigned and arrive',
                style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93))),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: _buildAnalyticCard(
                    icon: Icons.timer_outlined,
                    label: 'Avg Dispatch Time',
                    value: _formatDuration(avgDispatchTimeS),
                    subtitle: 'Ready → Assigned',
                    color: const Color(0xFF1967D2),
                    valueColor: avgDispatchTimeS > 0 && avgDispatchTimeS < 300
                        ? const Color(0xFF1E8E3E)
                        : const Color(0xFFF9A825),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildAnalyticCard(
                    icon: Icons.directions_walk_rounded,
                    label: 'Avg Arrival Time',
                    value: _formatDuration(avgArrivalTimeS),
                    subtitle: 'Assigned → Picked Up',
                    color: const Color(0xFFF9A825),
                    valueColor: avgArrivalTimeS > 0 && avgArrivalTimeS < 600
                        ? const Color(0xFF1E8E3E)
                        : const Color(0xFFF9A825),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Stats row
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                children: [
                  _buildStatItem('Orders Dispatched', '$totalDispatched', const Color(0xFF1967D2)),
                  Container(width: 1, height: 30, color: const Color(0xFFE5E7EB)),
                  Expanded(
                    child: _buildStatItem('Delivered', '$totalDelivered', const Color(0xFF1E8E3E)),
                  ),
                  Container(width: 1, height: 30, color: const Color(0xFFE5E7EB)),
                  Expanded(
                    child: _buildStatItem(
                        'Success Rate',
                        totalDispatched > 0
                            ? '${(totalDelivered / totalDispatched * 100).toInt()}%'
                            : '—',
                        const Color(0xFFBB0018)),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // ── Rider Ratings Section ──
            Row(
              children: [
                const Icon(Icons.star_rounded, size: 20, color: Color(0xFF1A1C1C)),
                const SizedBox(width: 8),
                const Text('Rider Ratings',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1A1C1C))),
              ],
            ),
            const SizedBox(height: 4),
            const Text('How customers rate your delivery riders',
                style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93))),
            const SizedBox(height: 16),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        avgRiderRating > 0 ? avgRiderRating.toStringAsFixed(1) : '—',
                        style: const TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1C1C),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: List.generate(5, (i) {
                              final filled = i < avgRiderRating.round();
                              return Icon(
                                filled ? Icons.star_rounded : Icons.star_border_rounded,
                                color: const Color(0xFFF9A825),
                                size: 20,
                              );
                            }),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$totalRiderRatings rating${totalRiderRatings == 1 ? '' : 's'}',
                            style: const TextStyle(fontSize: 13, color: Color(0xFF8E8E93)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // ── Top Selling Items (existing) ──
            Row(
              children: [
                const Icon(Icons.trending_up_rounded, size: 20, color: Color(0xFF1A1C1C)),
                const SizedBox(width: 8),
                const Text('Top Selling Items',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1A1C1C))),
              ],
            ),
            const SizedBox(height: 16),
            _buildTopItem(context, '1. Classic Smash Burger', '24 orders'),
            _buildTopItem(context, '2. French Fries', '18 orders'),
            _buildTopItem(context, '3. Crispy Chicken Burger', '12 orders'),

            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard(
    BuildContext context, {
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF8E8E93),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticCard({
    required IconData icon,
    required String label,
    required String value,
    required String subtitle,
    required Color color,
    required Color valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF1A1C1C),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF8E8E93),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: Color(0xFF8E8E93),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildTopItem(BuildContext context, String name, String orders) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E5EA)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            name,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A1A),
            ),
          ),
          Text(
            orders,
            style: const TextStyle(
              color: Color(0xFF8E8E93),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
