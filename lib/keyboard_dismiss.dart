import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'keyboard_actions_config.dart';

/// 앱 전체에 적용되는 키보드 관련 UX 보조 위젯.
///
/// 입력 필드·버튼 등이 아닌 빈 영역을 탭하면 포커스를 해제해 키보드를 닫는다.
/// [HitTestBehavior.opaque]는 TextField 탭과 경쟁해 입력이 안 되는 경우가 있어
/// 포인터 위치의 히트 테스트로 입력 위젯 여부를 판별한다.
class KeyboardDismissWrapper extends StatelessWidget {
  final Widget? child;

  const KeyboardDismissWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (_isOverEditableText(event.position)) return;
        // keyboard_actions 툴바(위/아래 화살표, 완료 버튼)를 탭한 경우 여기서
        // 바로 unfocus()하면 그 포커스 변경 알림을 keyboard_actions가 감지해
        // 오버레이(툴바)를 즉시 제거해버려, 버튼 자신의 onTap(다음/이전 필드로
        // 포커스 이동)이 실행되기도 전에 키보드만 사라지는 문제가 생긴다.
        // 키보드가 떠 있는 동안 키보드 바로 위 툴바 영역을 탭한 경우는
        // 무시해서 그 판단을 keyboard_actions 자신에게 맡긴다.
        if (_isOverKeyboardToolbar(context, event.position)) return;
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: child,
    );
  }

  /// 탭 지점이 키보드 위에 떠 있는 keyboard_actions 툴바 영역인지 확인한다.
  bool _isOverKeyboardToolbar(BuildContext context, Offset globalPosition) {
    final mediaQuery = MediaQuery.maybeOf(context);
    if (mediaQuery == null) return false;
    final keyboardHeight = mediaQuery.viewInsets.bottom;
    if (keyboardHeight <= 0) return false;
    final toolbarTop =
        mediaQuery.size.height - keyboardHeight - kKeyboardActionsBarHeight;
    return globalPosition.dy >= toolbarTop;
  }

  /// 탭 지점에 [EditableText]/TextField)가 있으면 true.
  bool _isOverEditableText(Offset globalPosition) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
      result,
      globalPosition,
      // 기본 뷰. 멀티 윈도우가 아니면 0.
      0,
    );
    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderEditable) return true;
      // 일부 플랫폼/버전에서 RenderEditable 상위 타입이 다를 수 있어
      // 런타임 타입 이름으로도 한 번 더 확인한다.
      final type = target.runtimeType.toString();
      if (type.contains('RenderEditable')) return true;
    }
    return false;
  }
}
