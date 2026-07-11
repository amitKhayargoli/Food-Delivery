import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app/theme/app_theme.dart';

void main() {
  testWidgets('AppTheme defines primary red color', (WidgetTester tester) async {
    final theme = AppTheme.lightTheme;
    expect(theme.primaryColor, const Color(0xFFF5222D));
    expect(theme.colorScheme.primary, const Color(0xFFF5222D));
  });
}
