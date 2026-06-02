import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../screens/user/home_screen.dart';
import '../screens/user/search_screen.dart';
import '../screens/user/cart_screen.dart';
import '../screens/user/profile_screen.dart';
import '../screens/owner/owner_dashboard_screen.dart';
import '../screens/owner/owner_menu_screen.dart';
import '../screens/owner/owner_analytics_screen.dart';
import '../screens/delivery/delivery_jobs_screen.dart';
import '../screens/admin/admin_dashboard_screen.dart';

class AppNavigation extends StatefulWidget {
  final String role;
  
  const AppNavigation({super.key, required this.role});

  @override
  State<AppNavigation> createState() => _AppNavigationState();
}

class _AppNavigationState extends State<AppNavigation> {
  int _currentIndex = 0;

  List<Widget> get _userScreens => [
    const UserHomeScreen(),
    const SearchScreen(),
    const Center(child: Text('Your Orders')),
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
    switch (widget.role.toUpperCase()) {
      case 'ADMIN': return _adminScreens;
      case 'RESTAURANT_OWNER': return _ownerScreens;
      case 'DELIVERY_BOY': return _deliveryScreens;
      case 'USER':
      default: return _userScreens;
    }
  }

  BottomNavigationBarItem _navItem(String path, String label, bool selected) {
    return BottomNavigationBarItem(
      icon: SvgPicture.asset(
        path,
        width: 24,
        height: 24,
        colorFilter: ColorFilter.mode(
          selected ? const Color(0xFFF5222D) : const Color(0xFF8E8E93),
          BlendMode.srcIn,
        ),
      ),
      label: label,
    );
  }

  List<BottomNavigationBarItem> _buildUserItems(int index) => [
    _navItem('assets/icons/home.svg', 'Home', index == 0),
    _navItem('assets/icons/search.svg', 'Search', index == 1),
    _navItem('assets/icons/orders.svg', 'Orders', index == 2),
    _navItem('assets/icons/cart.svg', 'Cart', index == 3),
    _navItem('assets/icons/profile.svg', 'Profile', index == 4),
  ];

  List<BottomNavigationBarItem> get _adminItems => const [
    BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'Dash'),
    BottomNavigationBarItem(icon: Icon(Icons.store), label: 'Restaurants'),
    BottomNavigationBarItem(icon: Icon(Icons.receipt), label: 'Orders'),
  ];

  List<BottomNavigationBarItem> get _ownerItems => const [
    BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: 'Live Orders'),
    BottomNavigationBarItem(icon: Icon(Icons.restaurant_menu), label: 'Menu'),
    BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'Insights'),
  ];

  List<BottomNavigationBarItem> get _deliveryItems => const [
    BottomNavigationBarItem(icon: Icon(Icons.moped), label: 'Jobs'),
    BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
    BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
  ];

  List<BottomNavigationBarItem> get _currentItems {
    switch (widget.role.toUpperCase()) {
      case 'ADMIN': return _adminItems;
      case 'RESTAURANT_OWNER': return _ownerItems;
      case 'DELIVERY_BOY': return _deliveryItems;
      case 'USER':
      default: return _buildUserItems(_currentIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _currentScreens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        selectedItemColor: const Color(0xFFF5222D),
        unselectedItemColor: const Color(0xFF8E8E93),
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        items: _currentItems,
      ),
    );
  }
}
