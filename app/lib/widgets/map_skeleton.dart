import 'dart:math';
import 'package:flutter/material.dart';

/// Paints a light grid-outline map skeleton with thin road lines on a pulsing
/// gray background. No filled blocks — just a wireframe street pattern.
/// Used as a loading placeholder while Baato map tiles are loading.
/// The [shimmerValue] (0.0–1.0) controls the pulse cycle for all colors.
class MapSkeletonPainter extends CustomPainter {
  final double shimmerValue;

  MapSkeletonPainter({required this.shimmerValue});

  @override
  void paint(Canvas canvas, Size size) {
    final s = shimmerValue;

    // ── Pulsing colors (subtle range) ──
    final bg = Color.lerp(const Color(0xFFE8E8E8), const Color(0xFFF7F7F7), s)!;
    final road =
        Color.lerp(const Color(0xFFD4D4D4), const Color(0xFFE8E8E8), s)!;

    // ── Background fill ──
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = bg,
    );

    // Deterministic "random" pattern (same seed = same pattern every frame)
    final rng = Random(42);
    const grid = 65.0;
    final cols = (size.width / grid).ceil();
    final rows = (size.height / grid).ceil();

    // ── Horizontal roads (thin lines) ──
    final roadPaint = Paint()
      ..color = road
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    for (int r = 0; r <= rows; r++) {
      final offset =
          (r % 2 == 0) ? rng.nextDouble() * 10 : -rng.nextDouble() * 10;
      final y = (r * grid + offset).clamp(0.0, size.height);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), roadPaint);
    }

    // ── Vertical roads (thin lines) ──
    for (int c = 0; c <= cols; c++) {
      final offset =
          (c % 2 == 0) ? rng.nextDouble() * 10 : -rng.nextDouble() * 10;
      final x = (c * grid + offset).clamp(0.0, size.width);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), roadPaint);
    }


  }

  @override
  bool shouldRepaint(MapSkeletonPainter oldDelegate) =>
      oldDelegate.shimmerValue != shimmerValue;
}
