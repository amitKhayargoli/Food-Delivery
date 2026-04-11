import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/theme/app_theme.dart';

void main() {
  testWidgets('AppTheme defines primary coral color', (WidgetTester tester) async {
    final theme = AppTheme.lightTheme;
    expect(theme.primaryColor, const Color(0xFFFF5A36));
    expect(theme.colorScheme.primary, const Color(0xFFFF5A36));
  });
}
