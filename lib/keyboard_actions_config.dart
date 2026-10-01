import 'package:flutter/material.dart';
import 'package:keyboard_actions/keyboard_actions.dart';

/// [KeyboardActions] 기본 툴바 높이 (`keyboard_actions` 패키지의 `_kBarSize`).
const double kKeyboardActionsBarHeight = 45.0;

/// 앱 공통 스타일의 [KeyboardActionsConfig]를 만든다.
///
/// [focusNodes] 순서대로 위/아래 화살표로 필드 간 이동이 가능하고,
/// 마지막에는 "완료" 버튼으로 키보드를 닫을 수 있다.
KeyboardActionsConfig buildKeyboardActionsConfig(List<FocusNode> focusNodes) {
  return KeyboardActionsConfig(
    keyboardActionsPlatform: KeyboardActionsPlatform.ALL,
    keyboardBarColor: const Color(0xFFE7ECF3),
    nextFocus: true,
    defaultDoneWidget: const Text(
      '완료',
      style: TextStyle(
        color: Color(0xFF3F5F8B),
        fontWeight: FontWeight.bold,
        fontSize: 15,
      ),
    ),
    actions: focusNodes
        .map((node) => KeyboardActionsItem(focusNode: node))
        .toList(),
  );
}
