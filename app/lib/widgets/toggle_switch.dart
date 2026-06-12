import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A polished, animated toggle switch designed for the restaurant owner
/// dashboard. Matches the app's red (#BB0018) brand colour scheme.
///
/// Unlike Material's built-in Switch, this one is compact, uses the
/// brand colour, and has a subtle shadow & press-ripple for feedback.
class ToggleSwitch extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const ToggleSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  State<ToggleSwitch> createState() => _ToggleSwitchState();
}

class _ToggleSwitchState extends State<ToggleSwitch>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _position;

  static const double _trackWidth = 48;
  static const double _trackHeight = 28;
  static const double _knobSize = 22;
  static const double _knobInset = (_trackHeight - _knobSize) / 2; // 3px

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
      value: widget.value ? 1.0 : 0.0,
    );
    _position = Tween<double>(begin: _knobInset, end: _trackWidth - _knobSize - _knobInset)
        .animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(ToggleSwitch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      if (widget.value) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        widget.onChanged(!widget.value);
      },
      child: AnimatedBuilder(
        animation: _position,
        builder: (context, child) {
          final isOn = _controller.value > 0.5;
          return Container(
            width: _trackWidth,
            height: _trackHeight,
            decoration: BoxDecoration(
              color: isOn ? const Color(0xFFBB0018) : const Color(0xFFE3E2E2),
              borderRadius: BorderRadius.circular(_trackHeight / 2),
              boxShadow: isOn
                  ? [
                      BoxShadow(
                        color: const Color(0xFFBB0018).withValues(alpha: 0.3),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Stack(
              children: [
                Positioned(
                  left: _position.value,
                  top: _knobInset,
                  child: Container(
                    width: _knobSize,
                    height: _knobSize,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ],
                      border: isOn
                          ? null
                          : Border.all(
                              color: const Color(0xFFC4C4C4),
                              width: 1.5,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
