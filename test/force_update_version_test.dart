import 'package:cal_cal_app/force_update_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isVersionLower', () {
    test('낮은 버전이면 true', () {
      expect(isVersionLower('1.1.0', '1.1.1'), isTrue);
      expect(isVersionLower('1.1.9', '1.2.0'), isTrue);
      expect(isVersionLower('1.9.0', '2.0'), isTrue);
    });

    test('같거나 높은 버전이면 false', () {
      expect(isVersionLower('1.1.1', '1.1.1'), isFalse);
      expect(isVersionLower('1.1.1', '1.1'), isFalse);
      expect(isVersionLower('1.10.0', '1.9.0'), isFalse);
    });

    test('빌드 번호(+)는 무시한다', () {
      expect(isVersionLower('1.1.0+6', '1.1.0+9'), isFalse);
    });

    test('읽을 수 없는 최소 버전으로는 막지 않는다', () {
      expect(isVersionLower('1.1.0', 'abc'), isFalse);
    });
  });
}
