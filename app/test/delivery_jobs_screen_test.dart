import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:get_it/get_it.dart';
import 'package:dio/dio.dart';
import 'package:app/core/services/api_service.dart';
import 'package:app/providers/auth_provider.dart';
import 'package:app/screens/delivery/delivery_jobs_screen.dart';

void main() {
  setUp(() {
    final sl = GetIt.instance;
    if (!sl.isRegistered<Dio>()) {
      sl.registerLazySingleton<Dio>(() => Dio(BaseOptions(baseUrl: 'http://localhost')));
    }
    if (!sl.isRegistered<ApiService>()) {
      sl.registerLazySingleton<ApiService>(() => ApiService(sl<Dio>()));
    }
    if (!sl.isRegistered<GlobalKey<NavigatorState>>()) {
      sl.registerLazySingleton<GlobalKey<NavigatorState>>(() => GlobalKey<NavigatorState>());
    }
  });

  testWidgets('DeliveryJobsScreen shows app bar title', (WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: AuthProvider()),
        ],
        child: const MaterialApp(
          home: DeliveryJobsScreen(),
        ),
      ),
    );

    // Should settle (token is null, so it shows error state)
    await tester.pumpAndSettle();

    // Should show app bar title
    expect(find.text('Assigned Jobs'), findsOneWidget);
  });
}
