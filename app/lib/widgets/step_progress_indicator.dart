import 'package:flutter/material.dart';

/// Configuration for a single step in the progress indicator.
class StepInfo {
  final String number;
  final String label;

  const StepInfo({
    required this.number,
    required this.label,
  });
}

/// A horizontal step progress indicator showing numbered circles
/// connected by lines, with labels beneath each step dot.
///
/// Example:
/// ```dart
/// StepProgressIndicator(
///   currentStep: 1,
///   steps: const [
///     StepInfo(number: '1', label: 'Contact'),
///     StepInfo(number: '2', label: 'Business'),
///     StepInfo(number: '3', label: 'Menu'),
///   ],
/// )
/// ```
class StepProgressIndicator extends StatelessWidget {
  /// The current active step (0-indexed). Steps at or before this index
  /// are rendered with the active color; steps after are grayed out.
  final int currentStep;

  /// The list of steps to display. Each step has a [number] (shown inside
  /// the circle) and a [label] (shown below the circle).
  final List<StepInfo> steps;

  /// Active color for completed/current steps. Defaults to [Color(0xFFF5222D)].
  final Color activeColor;

  /// Inactive color for future steps. Defaults to [Color(0xFFE8E8E8)].
  final Color inactiveColor;

  /// Inactive text color for future step labels. Defaults to [Color(0xFFBFBFBF)].
  final Color inactiveTextColor;

  const StepProgressIndicator({
    super.key,
    required this.currentStep,
    required this.steps,
    this.activeColor = const Color(0xFFF5222D),
    this.inactiveColor = const Color(0xFFE8E8E8),
    this.inactiveTextColor = const Color(0xFFBFBFBF),
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: Row(
        children: [
          const Spacer(),
          for (int i = 0; i < steps.length; i++) ...[
            if (i > 0)
              Container(
                width: 48,
                height: 2,
                decoration: BoxDecoration(
                  color: currentStep >= i ? activeColor : inactiveColor,
                ),
              ),
            _StepDot(
              number: steps[i].number,
              label: steps[i].label,
              isActive: currentStep >= i,
              bold: currentStep == i,
              activeColor: activeColor,
              inactiveColor: inactiveColor,
              inactiveTextColor: inactiveTextColor,
            ),
          ],
          const Spacer(),
        ],
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  final String number;
  final String label;
  final bool isActive;
  final bool bold;
  final Color activeColor;
  final Color inactiveColor;
  final Color inactiveTextColor;

  const _StepDot({
    required this.number,
    required this.label,
    required this.isActive,
    this.bold = false,
    required this.activeColor,
    required this.inactiveColor,
    required this.inactiveTextColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: isActive ? activeColor : inactiveColor,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isActive ? Colors.white : inactiveTextColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  height: 1.29,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: isActive ? activeColor : inactiveTextColor,
              fontSize: 10,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              height: 1.40,
              letterSpacing: 0.20,
            ),
          ),
        ],
      ),
    );
  }
}
