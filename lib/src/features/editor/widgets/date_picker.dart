import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/haptics.dart';
import '../../../core/theme/tokens.dart';

/// Compact in-page UTC calendar used by the new-alarm editor.
///
/// The selected value is always a UTC midnight. Past days cannot be picked,
/// and the month cannot be navigated before the current UTC month.
class UtcDatePicker extends StatefulWidget {
  const UtcDatePicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final DateTime selected;
  final ValueChanged<DateTime> onChanged;

  @override
  State<UtcDatePicker> createState() => _UtcDatePickerState();
}

class _UtcDatePickerState extends State<UtcDatePicker> {
  static const _weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  late DateTime _month = DateTime.utc(
    widget.selected.year,
    widget.selected.month,
    1,
  );

  DateTime get _todayUtc {
    final now = DateTime.now().toUtc();
    return DateTime.utc(now.year, now.month, now.day);
  }

  bool get _canGoBack {
    final today = _todayUtc;
    return _month.isAfter(DateTime.utc(today.year, today.month, 1));
  }

  Future<void> _shiftMonth(int delta) async {
    await hapticTap();
    setState(() {
      _month = DateTime.utc(_month.year, _month.month + delta, 1);
    });
  }

  Future<void> _pick(DateTime date) async {
    await hapticTap();
    widget.onChanged(date);
  }

  Future<void> _pickToday() async {
    final today = _todayUtc;
    await hapticTap();
    setState(() {
      _month = DateTime.utc(today.year, today.month, 1);
    });
    widget.onChanged(today);
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final today = _todayUtc;
    final leadingBlank = _month.weekday - 1; // Mon = 1
    final daysInMonth = DateTime.utc(_month.year, _month.month + 1, 0).day;

    Widget dayCell(int index) {
      final day = index - leadingBlank + 1;
      if (day < 1 || day > daysInMonth) return const SizedBox.shrink();

      final date = DateTime.utc(_month.year, _month.month, day);
      final isPast = date.isBefore(today);
      final isSelected =
          date.year == widget.selected.year &&
          date.month == widget.selected.month &&
          date.day == widget.selected.day;
      final isToday = date == today;

      final decoration = BoxDecoration(
        shape: BoxShape.circle,
        gradient: isSelected ? LarmPalette.brandGradient : null,
        color: isSelected ? null : const Color(0x08FFFFFF),
        border: isSelected
            ? null
            : Border.all(
                color: isToday ? LarmPalette.cyan : Colors.transparent,
              ),
      );

      return Semantics(
        button: true,
        enabled: !isPast,
        label: DateFormat('EEEE, MMMM d, y').format(date),
        child: InkWell(
          key: ValueKey('date-picker-day-$day'),
          onTap: isPast ? null : () => _pick(date),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            alignment: Alignment.center,
            decoration: decoration,
            child: Text(
              '$day',
              style: textTheme.bodyMedium?.copyWith(
                color: isSelected
                    ? LarmPalette.backgroundDeep
                    : (isPast
                          ? LarmPalette.muted.withValues(alpha: 0.35)
                          : LarmPalette.text),
                fontWeight: isSelected || isToday
                    ? FontWeight.w800
                    : FontWeight.w500,
              ),
            ),
          ),
        ),
      );
    }

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      accent: LarmPalette.cyan,
      glow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                key: const ValueKey('date-picker-prev-month'),
                tooltip: 'Previous month',
                icon: const Icon(LucideIcons.chevronLeft),
                onPressed: _canGoBack ? () => _shiftMonth(-1) : null,
              ),
              Expanded(
                child: Text(
                  DateFormat('MMMM y').format(_month),
                  textAlign: TextAlign.center,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('date-picker-next-month'),
                tooltip: 'Next month',
                icon: const Icon(LucideIcons.chevronRight),
                onPressed: () => _shiftMonth(1),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const ValueKey('date-picker-today'),
              onPressed: _pickToday,
              child: const Text('Today'),
            ),
          ),
          Row(
            children: [
              for (final label in _weekdays)
                Expanded(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: textTheme.labelSmall?.copyWith(
                      color: LarmPalette.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          GridView.count(
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 2,
            crossAxisSpacing: 2,
            children: List<Widget>.generate(42, dayCell),
          ),
        ],
      ),
    );
  }
}
