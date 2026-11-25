import 'package:flutter_test/flutter_test.dart';
import 'package:larm/src/features/editor/widgets/wheel_picker.dart';

void main() {
  group('looping wheel helpers', () {
    test('hours wrap 23 → 00 and can wrap backwards', () {
      expect(wheelWrapIndex(23, 24), 23);
      expect(wheelWrapIndex(24, 24), 0);
      expect(wheelWrapIndex(-1, 24), 23);
    });

    test('minutes wrap 59 → 00', () {
      expect(wheelWrapIndex(59, 60), 59);
      expect(wheelWrapIndex(60, 60), 0);
      expect(wheelWrapIndex(121, 60), 1);
    });

    test('starts in the center block with enough room both ways', () {
      expect(wheelLoopInitialIndex(23, 24), 100 * 24 + 23);
      expect(wheelLoopCount(24), 201 * 24);
      expect(
        wheelWrapIndex(wheelLoopInitialIndex(23, 24), 24),
        23,
      );
    });
  });
}
