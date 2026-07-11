import 'package:flutter/material.dart';
import '../../../core/utils/snackbar_helper.dart';

/// Provides standardized snackbar methods with a consistent color scheme
/// across the entire app. Always use these helpers instead of inline SnackBar.
///
/// Colors:
/// - Error:   Color(0xFFF5222D) — brand red
/// - Success: Color(0xFF1E8E3E) — green
/// - Info:    Color(0xFF1A1C1C) — dark gray
class SnackbarHelper {
  SnackbarHelper._();

  /// Show an error snackbar with the brand red background.
  static void error(BuildContext context, String message) {
    _show(context, message, backgroundColor: const Color(0xFFF5222D));
  }

  /// Show a success snackbar with a green background.
  static void success(BuildContext context, String message) {
    _show(context, message, backgroundColor: const Color(0xFF1E8E3E));
  }

  /// Show an informational snackbar with a dark background.
  static void info(BuildContext context, String message) {
    _show(context, message, backgroundColor: const Color(0xFF1A1C1C));
  }

  /// Internal helper that builds and shows a themed SnackBar.
  static void _show(
    BuildContext context,
    String message, {
    required Color backgroundColor,
    Duration duration = const Duration(seconds: 3),
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: duration,
      ),
    );
  }
}
