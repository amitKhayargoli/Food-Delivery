import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../core/services/api_service.dart';
import '../../injection_container.dart' as di;
import '../../providers/auth_provider.dart';
import 'owner_reviews_screen.dart';

class OwnerAnalyticsScreen extends StatefulWidget {
  const OwnerAnalyticsScreen({super.key});

  @override
  State<OwnerAnalyticsScreen> createState() => _OwnerAnalyticsScreenState();
}

class _OwnerAnalyticsScreenState extends State<OwnerAnalyticsScreen> {
  Map<String, dynamic> _analytics = {};
  List<Map<String, dynamic>> _menuItems = [];
  bool _isLoading = true;
  bool _isLoadingMenu = false;
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

      // Fetch menu items for top-selling display
      _fetchMenuItems();

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

  // ── Formatting ──

  Future<void> _fetchMenuItems() async {
    final token = _token;
    if (token == null) return;

    setState(() => _isLoadingMenu = true);

    try {
      final api = di.sl<ApiService>();
      final items = await api.getMenuItems(token: token);
      if (!mounted) return;
      setState(() {
        _menuItems = items;
        _isLoadingMenu = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingMenu = false);
    }
  }

  /// Parse daily_orders from analytics response for the bar chart.
  List<Map<String, dynamic>> _getDailyOrders() {
    final raw = _analytics['daily_orders'];
    if (raw is List) {
      return raw.cast<Map<String, dynamic>>();
    }
    return [];
  }

  // ── Build ──

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

    final dailyOrders = _getDailyOrders();

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
            const SizedBox(height: 20),

            // ── Sales & Orders Row ──
            Row(
              children: [
                Expanded(
                  child: _buildMetricCard(
                    title: 'Total Sales',
                    value: _analytics['total_sales'] != null
                        ? 'Rs ${_analytics['total_sales']}'
                        : 'Rs 12,450',
                    icon: Icons.currency_rupee_rounded,
                    iconColor: const Color(0xFF4CAF50),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildMetricCard(
                    title: 'Total Orders',
                    value: _analytics['total_orders'] != null
                        ? '${_analytics['total_orders']}'
                        : '42',
                    icon: Icons.shopping_bag_rounded,
                    iconColor: const Color(0xFF4CAF50),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // ── Orders Over Time (Bar Chart) ──
            _buildSectionHeader('Orders Over Time'),
            const SizedBox(height: 4),
            const Text('Daily dispatched vs delivered orders (last 7 days)',
                style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93))),
            const SizedBox(height: 16),
            _buildOrdersChart(dailyOrders),

            const SizedBox(height: 32),

            // ── Top Selling Items ──
            _buildSectionHeader('Menu Items'),
            const SizedBox(height: 4),
            const Text('Your restaurant\'s menu items',
                style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93))),
            const SizedBox(height: 16),
            _buildMenuItemsList(),

            // ── Most Ordered Food ──
            _buildSectionHeader('Most Ordered Food'),
            const SizedBox(height: 4),
            const Text('Your most popular menu items by order count',
                style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93))),
            const SizedBox(height: 16),
            _buildMostOrderedItems(),

            const SizedBox(height: 32),

            // ── View Reviews ──
            _buildReviewsLink(),

            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  // ── Section Header ──

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: Color(0xFF1A1C1C),
      ),
    );
  }

  // ── Metric Card (green checkout-card style) ──

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: ShapeDecoration(
        color: const Color(0xFFF5FFF5),
        shape: RoundedRectangleBorder(
          side: const BorderSide(width: 1, color: Color(0x1A4CAF50)),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: Row(
        children: [
          // Icon container
          Container(
            width: 44,
            height: 44,
            decoration: ShapeDecoration(
              color: const Color(0xFFE8F5E9),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Center(
              child: Icon(icon, color: iconColor, size: 22),
            ),
          ),
          const SizedBox(width: 14),
          // Value + title
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A1A1A),
                      height: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF999999),
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Orders Over Time — Bar Chart ──

  Widget _buildOrdersChart(List<Map<String, dynamic>> dailyData) {
    if (dailyData.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: const Column(
          children: [
            Icon(Icons.bar_chart_rounded, size: 40, color: Color(0xFFBFBFBF)),
            SizedBox(height: 8),
            Text(
              'No order data yet',
              style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14),
            ),
            SizedBox(height: 4),
            Text(
              'Orders will appear here once dispatched',
              style: TextStyle(color: Color(0xFFBFBFBF), fontSize: 12),
            ),
          ],
        ),
      );
    }

    // Calculate max Y value for the chart
    double maxY = 0;
    for (final day in dailyData) {
      final d = (day['dispatched'] as num?)?.toDouble() ?? 0;
      final v = (day['delivered'] as num?)?.toDouble() ?? 0;
      maxY = maxY > d ? maxY : d;
      maxY = maxY > v ? maxY : v;
    }
    maxY = (maxY + 2).ceilToDouble();

    // Shared interval for both grid lines and Y-axis labels
    final interval = maxY > 10 ? (maxY / 4).ceilToDouble() : 1.0;

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 20, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Legend
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 16),
            child: Row(
              children: [
                _buildLegendDot(const Color(0xFFBB0018), 'Dispatched'),
                const SizedBox(width: 20),
                _buildLegendDot(const Color(0xFF1E8E3E), 'Delivered'),
              ],
            ),
          ),
          // Chart
          SizedBox(
            height: 220,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY,
                minY: 0,
                barTouchData: BarTouchData(
                  enabled: true,
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final day = dailyData[groupIndex];
                      final label = day['date'] as String? ?? '';
                      final value = rod.toY.toInt();
                      final name = rodIndex == 0 ? 'Dispatched' : 'Delivered';
                      return BarTooltipItem(
                        '$label\n$name: $value',
                        TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= dailyData.length) {
                          return const SizedBox.shrink();
                        }
                        final day = dailyData[index];
                        final dateStr = day['date'] as String? ?? '';
                        // Show short day name
                        final parts = dateStr.split(', ');
                        final shortLabel = parts.isNotEmpty ? parts[0] : dateStr;
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            shortLabel.length > 3 ? shortLabel.substring(0, 3) : shortLabel,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF8E8E93),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: interval,
                      getTitlesWidget: (value, meta) {
                        if (value == 0) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(
                            value.toInt().toString(),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF8E8E93),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: interval,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: const Color(0xFFF0F0F0),
                      strokeWidth: 1,
                    );
                  },
                ),
                borderData: FlBorderData(show: false),
                barGroups: List.generate(dailyData.length, (index) {
                  final day = dailyData[index];
                  final dispatched = (day['dispatched'] as num?)?.toDouble() ?? 0;
                  final delivered = (day['delivered'] as num?)?.toDouble() ?? 0;

                  return BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: dispatched,
                        color: const Color(0xFFBB0018),
                        width: 10,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(4),
                          topRight: Radius.circular(4),
                        ),
                      ),
                      BarChartRodData(
                        toY: delivered,
                        color: const Color(0xFF1E8E3E),
                        width: 10,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(4),
                          topRight: Radius.circular(4),
                        ),
                      ),
                    ],
                    barsSpace: 4,
                  );
                }),
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildLegendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF6B7280),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // ── Menu Items List (with real images) ──

  Widget _buildMenuItemsList() {
    if (_isLoadingMenu) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(color: Color(0xFFBB0018)),
        ),
      );
    }

    if (_menuItems.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E5EA)),
        ),
        child: const Column(
          children: [
            Icon(Icons.restaurant_menu_rounded, size: 40, color: Color(0xFFBFBFBF)),
            SizedBox(height: 8),
            Text(
              'No menu items yet',
              style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14),
            ),
            SizedBox(height: 4),
            Text(
              'Add items to see them here',
              style: TextStyle(color: Color(0xFFBFBFBF), fontSize: 12),
            ),
          ],
        ),
      );
    }

    final displayItems = _menuItems.take(5).toList();

    return Column(
      children: displayItems.asMap().entries.map((entry) {
        final idx = entry.key;
        final item = entry.value;
        return _buildMenuItem(
          index: idx + 1,
          item: item,
        );
      }).toList(),
    );
  }

  Widget _buildMenuItem({
    required int index,
    required Map<String, dynamic> item,
  }) {
    final name = item['name'] as String? ?? 'Unknown Item';
    final price = (item['base_price'] as num?)?.toDouble() ?? 0.0;

    // Get the first image from images array, image_url, or use placeholder
    final imagesRaw = item['images'];
    final imageUrl = (imagesRaw is List && imagesRaw.isNotEmpty)
        ? imagesRaw.first as String?
        : item['image_url'] as String?;

    final rankColor = const Color(0xFF1A1C1C);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E5EA)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Index badge
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Text(
              '$index',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: rankColor,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Image thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: imageUrl != null && imageUrl.isNotEmpty
                ? Image.network(
                    imageUrl,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _buildPlaceholderImage(),
                    loadingBuilder: (_, child, progress) {
                      if (progress == null) return child;
                      return _buildPlaceholderImage();
                    },
                  )
                : _buildPlaceholderImage(),
          ),
          const SizedBox(width: 12),
          // Name
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Rs ${price.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1C1C),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Most Ordered Food ──

  Widget _buildMostOrderedItems() {
    final raw = _analytics['most_ordered_items'];
    final items = raw is List ? raw.cast<Map<String, dynamic>>() : <Map<String, dynamic>>[];

    if (items.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E5EA)),
        ),
        child: const Column(
          children: [
            Icon(Icons.restaurant_menu_rounded, size: 40, color: Color(0xFFBFBFBF)),
            SizedBox(height: 8),
            Text(
              'No order data yet',
              style: TextStyle(color: Color(0xFF8E8E93), fontSize: 14),
            ),
            SizedBox(height: 4),
            Text(
              'Ordered items will appear here',
              style: TextStyle(color: Color(0xFFBFBFBF), fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Column(
      children: items.asMap().entries.map((entry) {
        final idx = entry.key;
        final item = entry.value;
        final name = item['name'] as String? ?? 'Unknown Item';
        final imageUrl = item['image_url'] as String?;
        final totalQty = (item['total_qty'] as num?)?.toInt() ?? 0;
        final totalRevenue = (item['total_revenue'] as num?)?.toDouble() ?? 0.0;

        // Rank badge with clean solid styling
        final rankColor = const Color(0xFF1A1C1C);
        final rankBg = const Color(0xFFF5F5F5);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E5EA)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              // Rank badge
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: rankBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${idx + 1}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: rankColor,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Image thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: imageUrl != null && imageUrl.isNotEmpty
                    ? Image.network(
                        imageUrl,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _buildPlaceholderImage(),
                      )
                    : _buildPlaceholderImage(),
              ),
              const SizedBox(width: 12),
              // Name + order count
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1A1A1A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.shopping_bag_rounded,
                            size: 12, color: Color(0xFF8E8E93)),
                        const SizedBox(width: 4),
                        Text(
                          '$totalQty ordered',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF8E8E93),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Revenue
              Text(
                'Rs ${totalRevenue.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1C1C),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ── Reviews Link ──

  Widget _buildReviewsLink() {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const OwnerReviewsScreen(),
              ),
            );
          },
          icon: const Icon(Icons.rate_review_outlined, size: 18),
          label: const Text('View Customer Reviews'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFBB0018),
            side: const BorderSide(color: Color(0xFFBB0018)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholderImage() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F0),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(
        Icons.restaurant_rounded,
        size: 24,
        color: Color(0xFFBB0018),
      ),
    );
  }
}
