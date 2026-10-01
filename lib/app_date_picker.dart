import 'package:flutter/material.dart';

const Color _accentColor = Color(0xFF3F5F8B);
const Color _sundayColor = Color(0xFFE0685C);
const Color _saturdayColor = Color(0xFF5C86C9);

/// [showAppDatePicker]의 `dotLegend`에 넘기는 범례 한 줄(점 색상 + 설명).
class CalendarDotLegendItem {
  const CalendarDotLegendItem({required this.color, required this.label});

  final Color color;
  final String label;
}

/// 세련된 커스텀 달력 다이얼로그. 우측 상단 X 버튼으로만 닫히고,
/// 날짜를 탭하면 바로 선택되어 닫힌다. 좌우 스와이프/화살표로 월 이동.
Future<DateTime?> showAppDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
  String? helpText,
  /// 제목 아래에 작게 들어가는 설명 한 문장.
  String? helpSubtitle,
  /// 날짜별로 숫자 아래에 표시할 작은 점 색상. null을 반환하면 점을 표시하지 않는다.
  Color? Function(DateTime day)? dayDotColorBuilder,
  /// 상단 헤더(제목·닫기 버튼) 배경색. 지정하지 않으면 기본 accent 색을 쓴다.
  Color? headerColor,
  /// 달력 아래에 표시할 점 색상 범례. dayDotColorBuilder를 쓸 때만 의미가 있다.
  List<CalendarDotLegendItem>? dotLegend,
}) {
  return showDialog<DateTime>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: (context) => _AppDatePickerDialog(
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: helpText,
      helpSubtitle: helpSubtitle,
      dayDotColorBuilder: dayDotColorBuilder,
      headerColor: headerColor,
      dotLegend: dotLegend,
    ),
  );
}

class _AppDatePickerDialog extends StatefulWidget {
  const _AppDatePickerDialog({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    this.helpText,
    this.helpSubtitle,
    this.dayDotColorBuilder,
    this.headerColor,
    this.dotLegend,
  });

  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final String? helpText;
  final String? helpSubtitle;
  final Color? Function(DateTime day)? dayDotColorBuilder;
  final Color? headerColor;
  final List<CalendarDotLegendItem>? dotLegend;

  @override
  State<_AppDatePickerDialog> createState() => _AppDatePickerDialogState();
}

class _AppDatePickerDialogState extends State<_AppDatePickerDialog> {
  static DateTime _monthOnly(DateTime d) => DateTime(d.year, d.month);

  late final DateTime _firstMonth = _monthOnly(widget.firstDate);
  late final int _pageCount =
      (_monthOnly(widget.lastDate).year - _firstMonth.year) * 12 +
      (_monthOnly(widget.lastDate).month - _firstMonth.month) +
      1;

  late int _page = _monthIndex(widget.initialDate);
  late final PageController _pageController = PageController(
    initialPage: _page,
  );

  int _monthIndex(DateTime d) =>
      (d.year - _firstMonth.year) * 12 + (d.month - _firstMonth.month);

  DateTime _monthForPage(int page) =>
      DateTime(_firstMonth.year, _firstMonth.month + page);

  void _changeMonth(int delta) {
    final target = (_page + delta).clamp(0, _pageCount - 1);
    _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
    );
  }

  void _selectDay(DateTime day) => Navigator.of(context).pop(day);

  @override
  Widget build(BuildContext context) {
    final displayedMonth = _monthForPage(_page);
    // 대시보드 콘텐츠 폭(좌우 패딩 20 + ResponsiveContent maxWidth: 420)과
    // 동일한 기준으로 계산해, 뒤에 보이는 화면과 좌우 폭이 정확히 맞도록 한다.
    final dialogWidth = (MediaQuery.sizeOf(context).width - 40).clamp(
      0.0,
      420.0,
    );
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Container(
        width: dialogWidth,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 32,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              color: widget.headerColor ?? _accentColor,
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (widget.helpText != null)
                        Expanded(
                          child: Text(
                            widget.helpText!,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                              color: Colors.white,
                            ),
                          ),
                        )
                      else
                        const Spacer(),
                      InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => Navigator.of(context).pop(),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            Icons.close_rounded,
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (widget.helpSubtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        widget.helpSubtitle!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        '${displayedMonth.year}년 ${displayedMonth.month}월',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Colors.black87,
                        ),
                      ),
                      const Spacer(),
                      _NavButton(
                        icon: Icons.chevron_left,
                        onTap: _page > 0 ? () => _changeMonth(-1) : null,
                      ),
                      const SizedBox(width: 4),
                      _NavButton(
                        icon: Icons.chevron_right,
                        onTap: _page < _pageCount - 1
                            ? () => _changeMonth(1)
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 320,
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: _pageCount,
                      onPageChanged: (page) => setState(() => _page = page),
                      itemBuilder: (context, page) => _MonthView(
                        month: _monthForPage(page),
                        selected: widget.initialDate,
                        today: DateTime.now(),
                        firstDate: widget.firstDate,
                        lastDate: widget.lastDate,
                        onSelect: _selectDay,
                        dotColorBuilder: widget.dayDotColorBuilder,
                      ),
                    ),
                  ),
                  if (widget.dotLegend != null && widget.dotLegend!.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 14,
                      runSpacing: 6,
                      children: [
                        for (final item in widget.dotLegend!)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: item.color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                item.label,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black45,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? _accentColor.withValues(alpha: 0.08) : null,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 20,
          color: enabled ? _accentColor : Colors.black26,
        ),
      ),
    );
  }
}

class _MonthView extends StatelessWidget {
  const _MonthView({
    required this.month,
    required this.selected,
    required this.today,
    required this.firstDate,
    required this.lastDate,
    required this.onSelect,
    this.dotColorBuilder,
  });

  final DateTime month;
  final DateTime selected;
  final DateTime today;
  final DateTime firstDate;
  final DateTime lastDate;
  final ValueChanged<DateTime> onSelect;
  final Color? Function(DateTime day)? dotColorBuilder;

  static const _weekdayLabels = ['일', '월', '화', '수', '목', '금', '토'];

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Color _weekdayColor(int columnIndex) {
    if (columnIndex == 0) return _sundayColor;
    if (columnIndex == 6) return _saturdayColor;
    return Colors.black38;
  }

  List<List<DateTime?>> _buildWeeks() {
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // 일요일을 첫 칸으로 두기 위해 weekday(월=1..일=7)를 0(일)~6(토)로 변환.
    final leading = DateTime(month.year, month.month, 1).weekday % 7;
    final cells = <DateTime?>[
      for (var i = 0; i < leading; i++) null,
      for (var d = 1; d <= daysInMonth; d++) DateTime(month.year, month.month, d),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }
    return [
      for (var i = 0; i < cells.length; i += 7) cells.sublist(i, i + 7),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final weeks = _buildWeeks();
    final firstAllowed = DateTime(firstDate.year, firstDate.month, firstDate.day);
    final lastAllowed = DateTime(lastDate.year, lastDate.month, lastDate.day);

    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Center(
                  child: Text(
                    _weekdayLabels[i],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _weekdayColor(i),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Expanded(
          child: Column(
            children: [
              for (final week in weeks)
                Expanded(
                  child: Row(
                    children: [
                      for (var i = 0; i < 7; i++)
                        Expanded(
                          child: _DayCell(
                            day: week[i],
                            columnIndex: i,
                            selected: week[i] != null && _sameDay(week[i]!, selected),
                            isToday: week[i] != null && _sameDay(week[i]!, today),
                            disabled: week[i] != null &&
                                (week[i]!.isBefore(firstAllowed) ||
                                    week[i]!.isAfter(lastAllowed)),
                            weekdayColor: _weekdayColor(i),
                            onSelect: onSelect,
                            dotColor: week[i] != null
                                ? dotColorBuilder?.call(week[i]!)
                                : null,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.columnIndex,
    required this.selected,
    required this.isToday,
    required this.disabled,
    required this.weekdayColor,
    required this.onSelect,
    this.dotColor,
  });

  final DateTime? day;
  final int columnIndex;
  final bool selected;
  final bool isToday;
  final bool disabled;
  final Color weekdayColor;
  final ValueChanged<DateTime> onSelect;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    final day = this.day;
    if (day == null) return const SizedBox.shrink();

    final Color textColor;
    if (selected) {
      textColor = Colors.white;
    } else if (disabled) {
      textColor = Colors.black26;
    } else if (columnIndex == 0 || columnIndex == 6) {
      textColor = weekdayColor;
    } else {
      textColor = Colors.black87;
    }

    return Center(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: disabled ? null : () => onSelect(day),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? _accentColor : Colors.transparent,
                shape: BoxShape.circle,
                border: (!selected && isToday)
                    ? Border.all(color: _accentColor, width: 1.4)
                    : null,
              ),
              child: Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: (selected || isToday)
                      ? FontWeight.w800
                      : FontWeight.w500,
                  color: textColor,
                ),
              ),
            ),
            const SizedBox(height: 3),
            SizedBox(
              width: 6,
              height: 6,
              child: dotColor == null
                  ? null
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        color: dotColor,
                        shape: BoxShape.circle,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
