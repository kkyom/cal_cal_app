import 'package:flutter/material.dart';

/// 태블릿·와이드 화면에서 콘텐츠 최대 폭을 제한하고 가운데 정렬한다.
///
/// [Column] + [Expanded]처럼 높이가 필요한 화면에서는, 부모가 높이를
/// 주는 경우 그 높이를 그대로 유지한다. [SingleChildScrollView] 안처럼
/// 높이가 무한이면 폭만 제한한다.
class ResponsiveContent extends StatelessWidget {
  final double maxWidth;
  final Widget child;

  const ResponsiveContent({
    super.key,
    this.maxWidth = 560,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boundedHeight = constraints.hasBoundedHeight &&
            constraints.maxHeight.isFinite;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxWidth,
              minHeight: boundedHeight ? constraints.maxHeight : 0,
              maxHeight:
                  boundedHeight ? constraints.maxHeight : double.infinity,
            ),
            child: child,
          ),
        );
      },
    );
  }
}
