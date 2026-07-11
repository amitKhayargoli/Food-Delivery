import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:convex_bottom_bar/convex_bottom_bar.dart';
import '../providers/auth_provider.dart';
import '../screens/user/home_screen.dart';
import '../screens/user/search_screen.dart';
import '../screens/user/cart_screen.dart';
import '../screens/user/profile_screen.dart';
import '../screens/owner/owner_dashboard_screen.dart';
import '../screens/owner/owner_menu_screen.dart';
import '../screens/owner/owner_analytics_screen.dart';
import '../screens/delivery/delivery_jobs_screen.dart';
import '../screens/delivery/delivery_profile_screen.dart';
import '../screens/user/active_orders_screen.dart';
import '../screens/admin/admin_dashboard_screen.dart';

class AppNavigation extends StatefulWidget {
  final String role;

  const AppNavigation({super.key, required this.role});

  @override
  State<AppNavigation> createState() => _AppNavigationState();
}

/// Custom style hook to control icon sizes — active icon slightly larger than inactive.
class _NavBarStyle extends StyleHook {
  @override
  double? get iconSize => 24;

  @override
  double get activeIconSize => 28;

  @override
  double get activeIconMargin => 5;

  @override
  TextStyle textStyle(Color color, String? fontFamily) => TextStyle(
        fontSize: 10,
        color: color,
        fontFamily: fontFamily,
      );
}

class _AppNavigationState extends State<AppNavigation> {
  int _currentIndex = 0;
  /// Shared cart icon widget used in the nav bar (inactive state).
  static final Widget _cartIcon = SvgPicture.asset(
    'assets/icons/cart.svg',
    fit: BoxFit.scaleDown,
  );

  /// Cart icon with white fill for the active state (sits on the red circle).
  static final Widget _cartIconActive = SvgPicture.asset(
    'assets/icons/cart.svg',
    fit: BoxFit.scaleDown,
    colorFilter: const ColorFilter.mode(
      Colors.white,
      BlendMode.srcIn,
    ),
  );

  /// The effective role — uses the live value from AuthProvider's activeRole
  /// (which the user can switch without logging out), and falls back to the
  /// constructor parameter if AuthProvider hasn't loaded yet.
  String get _effectiveRole {
    final activeRole = context.watch<AuthProvider>().activeRole;
    if (activeRole.isNotEmpty) return activeRole.toUpperCase();
    return widget.role.toUpperCase();
  }

  List<Widget> get _userScreens => [
        const UserHomeScreen(),
        const SearchScreen(),
        const ActiveOrdersScreen(),
        const CartScreen(),
        const ProfileScreen(),
      ];

  List<Widget> get _adminScreens => [
        const AdminDashboardScreen(),
        const Center(child: Text('Admin Restaurants')),
        const Center(child: Text('Admin Orders')),
      ];

  List<Widget> get _ownerScreens => [
        const OwnerDashboardScreen(),
        const OwnerMenuScreen(),
        const OwnerAnalyticsScreen(),
        const ProfileScreen(),
      ];

  List<Widget> get _deliveryScreens => [
        const DeliveryJobsScreen(),
        const DeliveryProfileScreen(),
      ];

  List<Widget> get _currentScreens {
    switch (_effectiveRole) {
      case 'ADMIN':
        return _adminScreens;
      case 'RESTAURANT_OWNER':
        return _ownerScreens;
      case 'DELIVERY_BOY':
        return _deliveryScreens;
      case 'USER':
      default:
        return _userScreens;
    }
  }

  List<TabItem> get _userNavItems => [
        const TabItem(icon: Icons.home_rounded, title: 'Home'),
        const TabItem(icon: Icons.search_rounded, title: 'Search'),
        const TabItem(icon: Icons.receipt_long_rounded, title: 'Orders'),
        TabItem(
          icon: _cartIcon,
          activeIcon: _cartIconActive,
          title: 'Cart',
          isIconBlend: false,
        ),
        const TabItem(icon: Icons.person_rounded, title: 'Profile'),
      ];

  List<TabItem> get _adminNavItems => const [
        TabItem(icon: Icons.dashboard_rounded, title: 'Dash'),
        TabItem(icon: Icons.store_rounded, title: 'Restaurants'),
        TabItem(icon: Icons.receipt_rounded, title: 'Orders'),
      ];

  List<TabItem> get _ownerNavItems => const [
        TabItem(icon: Icons.list_alt_rounded, title: 'Live Orders'),
        TabItem(icon: Icons.restaurant_menu_rounded, title: 'Menu'),
        TabItem(icon: Icons.bar_chart_rounded, title: 'Insights'),
        TabItem(icon: Icons.person_rounded, title: 'Profile'),
      ];

  List<TabItem> get _deliveryNavItems => const [
        TabItem(icon: Icons.moped_rounded, title: 'Jobs'),
        TabItem(icon: Icons.person_rounded, title: 'My Profile'),
      ];

  List<TabItem> get _currentNavItems {
    switch (_effectiveRole) {
      case 'ADMIN':
        return _adminNavItems;
      case 'RESTAURANT_OWNER':
        return _ownerNavItems;
      case 'DELIVERY_BOY':
        return _deliveryNavItems;
      case 'USER':
      default:
        return _userNavItems;
    }
  }

  /// Show a bottom sheet allowing the user to switch their active role.
  void _showRoleSwitcher(AuthProvider authProvider) {
    final roles = authProvider.availableRoles;
    if (roles.length <= 1) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Switch Role',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1C1C),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Choose how you want to use the app',
                  style: TextStyle(fontSize: 13, color: Color(0xFF8E8E93)),
                ),
                const SizedBox(height: 20),
                ...roles.map((role) => _buildRoleOption(ctx, role, authProvider)),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRoleOption(BuildContext ctx, String role, AuthProvider authProvider) {
    final isActive = authProvider.activeRole == role;
    IconData icon;
    String label;
    String subtitle;

    switch (role) {
      case 'RESTAURANT_OWNER':
        icon = Icons.store_rounded;
        label = 'Restaurant Owner';
        subtitle = 'Manage your restaurant and orders';
        break;
      case 'DELIVERY_BOY':
        icon = Icons.moped_rounded;
        label = 'Delivery Rider';
        subtitle = 'Accept delivery jobs and earn';
        break;
      case 'USER':
      default:
        icon = Icons.person_rounded;
        label = 'Customer';
        subtitle = 'Browse restaurants and order food';
        break;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: isActive
            ? const Color(0xFFFFF1F0)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: isActive
              ? null
              : () {
                  authProvider.switchActiveRole(role);
                  Navigator.pop(ctx);
                },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: isActive
                        ? const Color(0xFFBB0018).withValues(alpha: 0.1)
                        : const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    color: isActive
                        ? const Color(0xFFBB0018)
                        : const Color(0xFF8E8E93),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: isActive
                                  ? const Color(0xFFBB0018)
                                  : const Color(0xFF1A1C1C),
                            ),
                          ),
                          if (isActive) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFBB0018),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Active',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF8E8E93),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isActive)
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: Color(0xFFBFBFBF),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();

    // Show a snackbar if the role was just changed by a realtime update
    final roleChangeMsg = authProvider.roleChangeMessage;
    if (roleChangeMsg != null) {
      authProvider.clearRoleChangeMessage();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.swap_horiz, color: Colors.white, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text(roleChangeMsg)),
              ],
            ),
            backgroundColor: const Color(0xFF1A1C1C),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'OK',
              textColor: const Color(0xFFEB1727),
              onPressed: () {},
            ),
          ),
        );
      });
    }

    // Clamp index when role switch changes screen count
    if (_currentIndex >= _currentScreens.length) {
      _currentIndex = 0;
    }

    return Scaffold(
      body: _currentScreens[_currentIndex],
      bottomNavigationBar: GestureDetector(
        onLongPress: authProvider.availableRoles.length > 1
            ? () => _showRoleSwitcher(authProvider)
            : null,
        child: StyleProvider(
        style: _NavBarStyle(),
        child: ConvexAppBar(
          key: ValueKey(_effectiveRole),
          style: TabStyle.reactCircle,
          backgroundColor: Colors.white,
          activeColor: const Color(0xFFF5222D),
          color: const Color(0xFF424242),
          elevation: 12,
          top: -28,
          initialActiveIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          items: _currentNavItems,
        ),
      ),
        ),
    );
  }

}


