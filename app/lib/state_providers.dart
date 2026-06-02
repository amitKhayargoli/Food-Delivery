import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'cart_provider.dart';
import 'favorites_provider.dart';
import 'features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'injection_container.dart' as di;

final authViewModelProvider = ChangeNotifierProvider<AuthViewModel>((ref) {
  return di.sl<AuthViewModel>();
});

final cartStateProvider = ChangeNotifierProvider<CartProvider>((ref) {
  return CartProvider(di.sl<SharedPreferences>());
});

final favoritesProvider = ChangeNotifierProvider<FavoritesProvider>((ref) {
  return FavoritesProvider(di.sl<SharedPreferences>());
});
