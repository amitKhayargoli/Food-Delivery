import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/screens/delivery/delivery_jobs_screen.dart';

void main() {
  testWidgets('DeliveryJobsScreen shows list of assigned jobs', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: DeliveryJobsScreen(),
      ),
    );

    // 2. Act: Ensure we are fully loaded
    await tester.pumpAndSettle();

    // 3. Assert: We should see "Assigned Jobs" in the app bar
    expect(find.text('Assigned Jobs'), findsOneWidget);
    
    // 3. Assert: We should see at least one order like "Order #1025"
    expect(find.text('Order #1025'), findsOneWidget);

    // 3. Assert: We should see an "Accept Job" button
    expect(find.text('Accept Job'), findsWidgets);
  });
}
