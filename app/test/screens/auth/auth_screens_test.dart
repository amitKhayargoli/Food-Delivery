import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:get_it/get_it.dart';
import 'package:app/core/services/api_service.dart';
import 'package:app/providers/auth_provider.dart';
import 'package:app/screens/auth/login_screen.dart';
import 'package:app/screens/auth/signup_screen.dart';

void main() {
  setUp(() {
    // Register ApiService in GetIt so SignUpScreen can access it
    final sl = GetIt.instance;
    if (!sl.isRegistered<Dio>()) {
      sl.registerLazySingleton<Dio>(() => Dio(BaseOptions(baseUrl: 'http://localhost')));
    }
    if (!sl.isRegistered<ApiService>()) {
      sl.registerLazySingleton<ApiService>(() => ApiService(sl<Dio>()));
    }
  });

  testWidgets('LoginScreen has required fields and buttons', (WidgetTester tester) async {
    final authProvider = AuthProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ],
        child: const MaterialApp(
          home: LoginScreen(),
        ),
      ),
    );

    // The actual text is 'Welcome Back' (capital B)
    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('Sign in to continue'), findsOneWidget);
    expect(find.text('Enter Your Phone Number'), findsOneWidget);
    expect(find.text('Continue'), findsWidgets);
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testWidgets('SignUpScreen has required fields and buttons', (WidgetTester tester) async {
    final authProvider = AuthProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
        ],
        child: const MaterialApp(
          home: SignUpScreen(),
        ),
      ),
    );

    // The actual text is 'Create an account' (lowercase 'a')
    expect(find.text('Create an account'), findsOneWidget);
    expect(find.text('Sign up with your details'), findsOneWidget);
    expect(find.text('Enter your Full Name'), findsOneWidget);
    expect(find.text('Enter your Phone Number'), findsOneWidget);
    expect(find.text('Enter Your Email (optional)'), findsOneWidget);
    expect(find.text('Continue'), findsWidgets);
    expect(find.text('Continue with Google'), findsNothing);
  });
}
