import 'package:flutter/material.dart';
import '../../widgets/primary_button.dart';

class OwnerDashboardScreen extends StatelessWidget {
  const OwnerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        appBar: AppBar(
          title: const Text('Live Orders'),
          actions: [
            Row(
              children: [
                Text(
                  'Accepting Orders',
                  style: theme.textTheme.bodySmall,
                ),
                Switch(
                  value: true,
                  activeThumbColor: theme.colorScheme.primary,
                  onChanged: (val) {},
                ),
              ],
            ),
          ],
          bottom: TabBar(
            labelColor: theme.colorScheme.primary,
            unselectedLabelColor: const Color(0xFF8E8E93),
            indicatorColor: theme.colorScheme.primary,
            tabs: const [
              Tab(text: 'New (2)'),
              Tab(text: 'Preparing (1)'),
              Tab(text: 'Ready (0)'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildNewOrdersList(context),
            _buildPreparingOrdersList(context),
            _buildReadyOrdersList(context),
          ],
        ),
      ),
    );
  }

  Widget _buildNewOrdersList(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildOrderCard(
          context,
          orderId: '#1023',
          time: '2 mins ago',
          items: ['2x Classic Smash Burger', '1x French Fries'],
          total: 'Rs 850',
          actions: [
            Expanded(
              child: PrimaryButton(
                text: 'Reject',
                isOutlined: true,
                onPressed: () {},
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: PrimaryButton(
                text: 'Accept',
                onPressed: () {},
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildOrderCard(
          context,
          orderId: '#1024',
          time: 'Just now',
          items: ['1x Crispy Chicken Burger'],
          total: 'Rs 320',
          actions: [
            Expanded(
              child: PrimaryButton(
                text: 'Reject',
                isOutlined: true,
                onPressed: () {},
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: PrimaryButton(
                text: 'Accept',
                onPressed: () {},
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPreparingOrdersList(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildOrderCard(
          context,
          orderId: '#1022',
          time: '15 mins ago',
          items: ['1x Margherita Pizza', '1x Garlic Bread'],
          total: 'Rs 900',
          actions: [
            Expanded(
              child: PrimaryButton(
                text: 'Mark as Ready',
                onPressed: () {},
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildReadyOrdersList(BuildContext context) {
    return const Center(
      child: Text(
        'No orders ready for pickup.',
        style: TextStyle(color: Color(0xFF8E8E93)),
      ),
    );
  }

  Widget _buildOrderCard(
    BuildContext context, {
    required String orderId,
    required String time,
    required List<String> items,
    required String total,
    required List<Widget> actions,
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Order $orderId',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A1A1A),
                ),
              ),
              Text(
                time,
                style: const TextStyle(
                  color: Color(0xFFF5222D),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          ...items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  item,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
              )),
          const SizedBox(height: 8),
          Text(
            'Total: $total',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1A1A1A),
            ),
          ),
          const SizedBox(height: 24),
          Row(children: actions),
        ],
      ),
    );
  }
}
