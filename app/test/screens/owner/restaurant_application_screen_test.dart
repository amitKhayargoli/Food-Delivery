import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/screens/owner/restaurant_application_screen.dart';

/// Helper that pumps the [RestaurantApplicationScreen] wrapped in a
/// [ProviderScope]. The auth provider is only read inside _submit()
/// (which validation tests never trigger), so no overrides needed.
Future<void> pumpScreen(WidgetTester tester) async {
  await tester.pumpWidget(
    const ProviderScope(
      child: MaterialApp(
        home: RestaurantApplicationScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// ──────────────────────────────────────────────────────────────────
//  Step 0 — Contact Details  (initial step)
// ──────────────────────────────────────────────────────────────────

void main() {
  group('RestaurantApplicationScreen — Step 0 (Contact)', () {
    testWidgets('shows Step 0 on load with Continue button',
        (WidgetTester tester) async {
      await pumpScreen(tester);

      expect(find.text('Partner with us'), findsOneWidget);
      expect(find.text('Continue to Business Information'), findsOneWidget);
    });

    testWidgets('shows validation errors when Continue tapped with empty fields',
        (WidgetTester tester) async {
      await pumpScreen(tester);

      await tester.tap(find.text('Continue to Business Information'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter your full name.'), findsOneWidget);
      expect(find.text('Please enter your email address.'), findsOneWidget);
      expect(find.text('Please enter your phone number.'), findsOneWidget);

      // Should still be on Step 0
      expect(find.text('Continue to Business Information'), findsOneWidget);
      expect(find.text('Partner with us'), findsOneWidget);
    });

    testWidgets('shows email validation error for missing @',
        (WidgetTester tester) async {
      await pumpScreen(tester);

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'John Doe');
      await tester.enterText(textFields.at(1), 'invalid-email');
      await tester.enterText(textFields.at(2), '9812345678');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue to Business Information'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter a valid email address.'), findsOneWidget);
      expect(find.text('Please enter your full name.'), findsNothing);
      expect(find.text('Please enter your phone number.'), findsNothing);

      expect(find.text('Continue to Business Information'), findsOneWidget);
    });

    testWidgets('shows phone validation error for number not starting with 9',
        (WidgetTester tester) async {
      await pumpScreen(tester);

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'John Doe');
      await tester.enterText(textFields.at(1), 'john@test.com');
      await tester.enterText(textFields.at(2), '0812345678');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue to Business Information'));
      await tester.pumpAndSettle();

      expect(
        find.text('Please enter a valid phone number starting with 9.'),
        findsOneWidget,
      );
    });

    testWidgets('shows phone validation error for short number',
        (WidgetTester tester) async {
      await pumpScreen(tester);

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'John Doe');
      await tester.enterText(textFields.at(1), 'john@test.com');
      await tester.enterText(textFields.at(2), '98123');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue to Business Information'));
      await tester.pumpAndSettle();

      expect(
        find.text('Please enter a valid phone number starting with 9.'),
        findsOneWidget,
      );
    });

    testWidgets('advances to Step 1 when all fields are valid',
        (WidgetTester tester) async {
      await pumpScreen(tester);

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'John Doe');
      await tester.enterText(textFields.at(1), 'john@restaurant.com');
      await tester.enterText(textFields.at(2), '9812345678');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue to Business Information'));
      await tester.pumpAndSettle();

      expect(find.text('Business Information'), findsOneWidget);
      expect(find.text('Continue to Menu'), findsOneWidget);
      expect(find.text('Partner with us'), findsNothing);
      expect(find.text('Continue to Business Information'), findsNothing);
    });
  });

  // ──────────────────────────────────────────────────────────────
  //  Step 1 — Business Information
  // ──────────────────────────────────────────────────────────────

  group('RestaurantApplicationScreen — Step 1 (Business)', () {
    /// Fill Step 0 with valid data and advance to Step 1.
    Future<void> navigateToStep1(WidgetTester tester) async {
      await pumpScreen(tester);

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), 'John Doe');
      await tester.enterText(textFields.at(1), 'john@restaurant.com');
      await tester.enterText(textFields.at(2), '9812345678');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue to Business Information'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows Step 1 with Continue to Menu button',
        (WidgetTester tester) async {
      await navigateToStep1(tester);

      expect(find.text('Business Information'), findsOneWidget);
      expect(find.text('Continue to Menu'), findsOneWidget);
    });

    testWidgets('shows validation errors when Continue tapped with empty fields',
        (WidgetTester tester) async {
      await navigateToStep1(tester);

      await tester.ensureVisible(find.text('Continue to Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue to Menu'));
      await tester.pumpAndSettle();

      // All 5 fields should show errors
      expect(find.text('Please enter your restaurant name.'), findsOneWidget);
      expect(find.text('Please enter your restaurant address.'), findsOneWidget);
      expect(find.text('Please select your cuisine type.'), findsOneWidget);
      expect(find.text('Please enter your PAN number.'), findsOneWidget);
      expect(find.text('Please upload your PAN certificate.'), findsOneWidget);

      // Should still be on Step 1
      expect(find.text('Continue to Menu'), findsOneWidget);
    });

    testWidgets('advances to Step 2 when all fields are filled',
        (WidgetTester tester) async {
      // SKIPPED: PAN certificate upload (ImagePicker) returns null in widget
      // tests, preventing navigation past Step 1 validation.
    }, skip: true);

    testWidgets('Go Back returns to Step 0',
        (WidgetTester tester) async {
      await navigateToStep1(tester);

      await tester.ensureVisible(find.text('Go Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Go Back'));
      await tester.pumpAndSettle();

      expect(find.text('Partner with us'), findsOneWidget);
      expect(find.text('Continue to Business Information'), findsOneWidget);
    });
  });

  // ──────────────────────────────────────────────────────────────
  //  Step 2 — Restaurant Details (Menu)
  // ──────────────────────────────────────────────────────────────

  group('RestaurantApplicationScreen — Step 2 (Menu)', () {
    // All Step 2 tests are skipped because they require navigating past
    // Step 1's PAN certificate upload validation. ImagePicker returns null
    // in widget tests, making Step 2 unreachable via automated testing.
    // These scenarios should be covered by integration tests.

    testWidgets('shows Step 2 with Submit Application button',
        (WidgetTester tester) async {
      // SKIPPED: See group-level note above.
    }, skip: true);

    testWidgets('shows error when Submit tapped without selecting food category',
        (WidgetTester tester) async {
      // SKIPPED: See group-level note above.
    }, skip: true);

    testWidgets('Go Back to Business returns to Step 1',
        (WidgetTester tester) async {
      // SKIPPED: See group-level note above.
    }, skip: true);
  });
}
