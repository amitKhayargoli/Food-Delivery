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
import '../screens/user/active_orders_screen.dart';
import '../screens/delivery/delivery_jobs_screen.dart';
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
  double? get iconSize => 24; // inactive icons

  @override
  double get activeIconSize => 28; // active icon: slightly bigger, but not too big

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
  /// Explicit width/height match the StyleHook's iconSize (24) so the SVG
  /// doesn't render at its native (larger) size — the ConvexAppBar handles
  /// the active size bump to 28 via activeIconSize.
  /// Cart icon — uses the SVG's native 24×24 dimensions from the file.
  /// BoxFit.scaleDown prevents the ConvexAppBar's active circle from
  /// scaling it up larger than the other nav icons.
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

  /// The effective role — uses the live value from AuthProvider (which
  /// is updated in real-time via Supabase Realtime subscription) and
  /// falls back to the constructor parameter.
  String get _effectiveRole =>
      context.watch<AuthProvider>().role?.toUpperCase() ??
      widget.role.toUpperCase();

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
  ];

  List<Widget> get _deliveryScreens => [
    const DeliveryJobsScreen(),
    const Center(child: Text('Delivery History')),
    const Center(child: Text('Delivery Profile')),
  ];

  List<Widget> get _currentScreens {
    switch (_effectiveRole) {
      case 'ADMIN': return _adminScreens;
      case 'RESTAURANT_OWNER': return _ownerScreens;
      case 'DELIVERY_BOY': return _deliveryScreens;
      case 'USER':
      default: return _userScreens;
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
  ];

  List<TabItem> get _deliveryNavItems => const [
    TabItem(icon: Icons.moped_rounded, title: 'Jobs'),
    TabItem(icon: Icons.history_rounded, title: 'History'),
    TabItem(icon: Icons.person_rounded, title: 'Profile'),
  ];

  List<TabItem> get _currentNavItems {
    switch (_effectiveRole) {
      case 'ADMIN': return _adminNavItems;
      case 'RESTAURANT_OWNER': return _ownerNavItems;
      case 'DELIVERY_BOY': return _deliveryNavItems;
      case 'USER':
      default: return _userNavItems;
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();

    // Show a snackbar if the role was just changed by a realtime update
    final roleChangeMsg = authProvider.roleChangeMessage;
    if (roleChangeMsg != null) {
      // Consume the message immediately so duplicate rebuilds
      // in the same frame don't show multiple snackbars.
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
      bottomNavigationBar: StyleProvider(
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
    );
  }
}
