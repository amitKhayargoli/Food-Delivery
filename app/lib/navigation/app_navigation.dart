import 'package:flutter/material.dart';
import '../screens/user/home_screen.dart';
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
    const Center(child: Text('User Orders')),
    const Center(child: Text('User Profile')),
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

  List<BottomNavigationBarItem> get _userItems => const [
    BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Home'),
    BottomNavigationBarItem(icon: Icon(Icons.receipt_long), label: 'Orders'),
    BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
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
      default: return _userItems;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      body: _currentScreens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        selectedItemColor: theme.colorScheme.primary,
        unselectedItemColor: const Color(0xFF8E8E93),
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        items: _currentItems,
      ),
    );
  }
}
