import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:app/providers/auth_provider.dart';
import 'package:app/screens/auth/login_screen.dart';
import 'package:app/screens/auth/signup_screen.dart';

void main() {
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

    expect(find.text('Welcome back!'), findsOneWidget);
    expect(find.text('Email or Phone Number'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Forgot Password?'), findsOneWidget);
    expect(find.text('Login'), findsWidgets);
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

    expect(find.text('Create an Account'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Email Address'), findsOneWidget);
    expect(find.text('Phone Number'), findsOneWidget);
    expect(find.text('Password'), findsWidgets);
    expect(find.text('Sign Up'), findsWidgets);
    expect(find.text('Continue with Google'), findsOneWidget);
  });
}
