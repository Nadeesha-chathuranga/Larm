import 'package:material_ui/material_ui.dart';

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

/// Number of full item cycles on each side of the center block. Large enough
/// that a user never reaches a physical end of a looping hour/minute wheel.
const int wheelLoopRepeats = 100;

/// Virtual child count for a looping wheel.
int wheelLoopCount(int itemCount) =>
    itemCount * (2 * wheelLoopRepeats + 1);

/// Scroll position that starts on the requested value in the center block.
int wheelLoopInitialIndex(int initialIndex, int itemCount) =>
    wheelLoopRepeats * itemCount + (initialIndex % itemCount);

/// Maps a virtual scroll position back to a real item index.
int wheelWrapIndex(int index, int itemCount) =>
    ((index % itemCount) + itemCount) % itemCount;

/// Scrollable wheel column with magnification and haptic ticks.
///
/// Generic over the item type; [label] formats the visible text. When [loop]
/// is true, scrolling past the last item wraps to the first (e.g. 23 → 00).
class WheelPicker<T> extends StatefulWidget {
  const WheelPicker({
    super.key,
    required this.items,
    required this.initialIndex,
    required this.onSelected,
    required this.label,
    this.width = 96,
    this.itemExtent = 72,
    this.loop = false,
  });

  final List<T> items;
  final int initialIndex;
  final ValueChanged<int> onSelected;
  final String Function(T value) label;
  final double width;
  final double itemExtent;
  final bool loop;

  @override
  State<WheelPicker<T>> createState() => _WheelPickerState<T>();
}

class _WheelPickerState<T> extends State<WheelPicker<T>> {
  late final FixedExtentScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = FixedExtentScrollController(
      initialItem: widget.loop
          ? wheelLoopInitialIndex(widget.initialIndex, widget.items.length)
          : widget.initialIndex,
    );
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
        magnification: 1.25,
        overAndUnderCenterOpacity: 0.5,
        physics: const FixedExtentScrollPhysics(),
        onSelectedItemChanged: (index) {
          _tickHaptic();
          widget.onSelected(
            widget.loop
                ? wheelWrapIndex(index, widget.items.length)
                : index,
          );
        },
        childDelegate: ListWheelChildBuilderDelegate(
          childCount: widget.loop
              ? wheelLoopCount(widget.items.length)
              : widget.items.length,
          builder: (context, index) {
            final itemIndex = widget.loop
                ? wheelWrapIndex(index, widget.items.length)
                : index;
            return Center(
              child: Text(
                widget.label(widget.items[itemIndex]),
                style: (Theme.of(context).textTheme.headlineLarge ??
                        const TextStyle(fontSize: 32))
                    .copyWith(
                  color: scheme.onSurface,
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Two-digit formatter for hour/minute wheels.
String twoDigits(int v) => v.toString().padLeft(2, '0');
