import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/screens/admin/admin_dashboard_screen.dart';

void main() {
  testWidgets('AdminDashboardScreen shows high-level metrics', (WidgetTester tester) async {
    // 1. Arrange: Assume a class AdminDashboardScreen will exist
    await tester.pumpWidget(
      const MaterialApp(
        home: AdminDashboardScreen(),
      ),
    );

    // 2. Act: Wait for the render
    await tester.pumpAndSettle();

    // 3. Assert: verify critical text is present
    expect(find.text('Admin Dashboard'), findsOneWidget);
    expect(find.text('Total GMV'), findsOneWidget);
    expect(find.text('Active Deliveries'), findsOneWidget);
    expect(find.text('Recent System Alerts'), findsOneWidget);
  });
}
