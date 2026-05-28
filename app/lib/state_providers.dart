import 'package:flutter_riverpod/legacy.dart';

import 'cart_provider.dart';
import 'features/auth/presentation/viewmodels/auth_viewmodel.dart';
import 'injection_container.dart' as di;

final authViewModelProvider = ChangeNotifierProvider<AuthViewModel>((ref) {
  return di.sl<AuthViewModel>();
});

final cartStateProvider = ChangeNotifierProvider<CartProvider>((ref) {
  return CartProvider();
});
