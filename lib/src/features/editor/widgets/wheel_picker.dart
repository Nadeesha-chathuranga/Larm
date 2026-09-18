import 'package:flutter/material.dart';

import '../../../core/haptics.dart';

/// Minimum gap between scroll-tick haptics so fast flings don't buzz-storm.
const _hapticGap = Duration(milliseconds: 80);
DateTime _lastHaptic = DateTime.fromMillisecondsSinceEpoch(0);

Future<void> _tickHaptic() async {
  final now = DateTime.now();
  if (now.difference(_lastHaptic) < _hapticGap) return;
  _lastHaptic = now;
  await hapticTap();
}

/// Scrollable wheel column with magnification and haptic ticks.
///
/// Generic over the item type; [label] formats the visible text.
class WheelPicker<T> extends StatefulWidget {
  const WheelPicker({
    super.key,
    required this.items,
    required this.initialIndex,
    required this.onSelected,
    required this.label,
    this.width = 96,
    this.itemExtent = 56,
  });

  final List<T> items;
  final int initialIndex;
  final ValueChanged<int> onSelected;
  final String Function(T value) label;
  final double width;
  final double itemExtent;

  @override
  State<WheelPicker<T>> createState() => _WheelPickerState<T>();
}

class _WheelPickerState<T> extends State<WheelPicker<T>> {
  late final FixedExtentScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        FixedExtentScrollController(initialItem: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: widget.width,
      height: widget.itemExtent * 3,
      child: ListWheelScrollView.useDelegate(
        controller: _controller,
        itemExtent: widget.itemExtent,
        perspective: 0.008,
        diameterRatio: 1.6,
        useMagnifier: true,
        magnification: 1.15,
        overAndUnderCenterOpacity: 0.45,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: (index) {
          _tickHaptic();
          widget.onSelected(index);
        },
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: widget.items.length,
          builder: (context, index) => Center(
            child: Text(
              widget.label(widget.items[index]),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: scheme.onSurface,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Two-digit formatter for hour/minute wheels.
String twoDigits(int v) => v.toString().padLeft(2, '0');
