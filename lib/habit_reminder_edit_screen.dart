import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models.dart';
import 'responsive_content.dart';

const Color _bgColor = Color(0xFFF2F2F2);
const Color _primaryColor = Color(0xFF3F5F8B);
const Color _fieldBgColor = Color(0xFFEDEDED);

const List<String> _weekdayLabels = ['월', '화', '수', '목', '금', '토', '일'];

/// [HabitReminderEditScreen]이 반환하는 결과. 저장(추가/수정) 또는 삭제.
sealed class HabitReminderEditResult {
  const HabitReminderEditResult();
}

class HabitReminderSaved extends HabitReminderEditResult {
  final HabitReminder reminder;
  const HabitReminderSaved(this.reminder);
}

class HabitReminderDeleted extends HabitReminderEditResult {
  const HabitReminderDeleted();
}

/// 설정 > 알림 설정 > 나만의 습관 알림에서 알림을 추가/수정하는 화면.
/// [initial]이 없으면 추가, 있으면 수정(삭제 버튼도 함께 노출).
class HabitReminderEditScreen extends StatefulWidget {
  final HabitReminder? initial;

  const HabitReminderEditScreen({super.key, this.initial});

  @override
  State<HabitReminderEditScreen> createState() =>
      _HabitReminderEditScreenState();
}

class _HabitReminderEditScreenState extends State<HabitReminderEditScreen> {
  late final TextEditingController _nameController =
      TextEditingController(text: widget.initial?.name ?? '');
  late TimeOfDay? _time = widget.initial != null
      ? TimeOfDay(hour: widget.initial!.hour, minute: widget.initial!.minute)
      : null;
  late final Set<int> _weekdays = (widget.initial?.weekdays ?? const []).toSet();

  bool get _isEditing => widget.initial != null;

  bool get _isValid =>
      _nameController.text.trim().isNotEmpty &&
      _time != null &&
      _weekdays.isNotEmpty;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickTime() async {
    final picked = await showDialog<TimeOfDay>(
      context: context,
      builder: (_) => _TimeInputDialog(
        initial: _time ?? const TimeOfDay(hour: 9, minute: 0),
      ),
    );
    if (picked == null) return;
    setState(() => _time = picked);
  }

  void _toggleWeekday(int weekday) {
    setState(() {
      if (_weekdays.contains(weekday)) {
        _weekdays.remove(weekday);
      } else {
        _weekdays.add(weekday);
      }
    });
  }

  void _toggleEveryDay() {
    setState(() {
      if (_weekdays.length == 7) {
        _weekdays.clear();
      } else {
        _weekdays
          ..clear()
          ..addAll(const [1, 2, 3, 4, 5, 6, 7]);
      }
    });
  }

  void _submit() {
    if (!_isValid) return;
    final reminder = HabitReminder(
      id: widget.initial?.id ?? DateTime.now().millisecondsSinceEpoch,
      name: _nameController.text.trim(),
      hour: _time!.hour,
      minute: _time!.minute,
      weekdays: _weekdays.toList()..sort(),
      enabled: widget.initial?.enabled ?? true,
    );
    Navigator.of(context).pop(HabitReminderSaved(reminder));
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('알림 삭제'),
        content: const Text('이 알림을 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      Navigator.of(context).pop(const HabitReminderDeleted());
    }
  }

  String get _timeLabel {
    if (_time == null) return '알림 받을 시간';
    final period = _time!.hour < 12 ? '오전' : '오후';
    final hour12 = _time!.hourOfPeriod == 0 ? 12 : _time!.hourOfPeriod;
    final minute = _time!.minute.toString().padLeft(2, '0');
    return '$period $hour12:$minute';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Text(
          _isEditing ? '알림 수정' : '알림 추가',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        actions: [
          if (_isEditing)
            IconButton(
              onPressed: _confirmDelete,
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              tooltip: '삭제',
            ),
        ],
      ),
      body: SafeArea(
        child: ResponsiveContent(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 72, 20, 20),
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: _fieldBgColor,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.edit_note_outlined,
                            color: Colors.black45,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _nameController,
                              maxLength: 15,
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                hintText: '알림 이름 (최대 15자)',
                                counterText: '',
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Material(
                      color: _fieldBgColor,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: _pickTime,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 18,
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.access_time_outlined,
                                color: Colors.black45,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _timeLabel,
                                style: TextStyle(
                                  color: _time == null
                                      ? Colors.black45
                                      : Colors.black87,
                                  fontWeight: _time == null
                                      ? FontWeight.w400
                                      : FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    const Text(
                      '알림 받을 요일',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: List.generate(7, (i) {
                        final weekday = i + 1;
                        final selected = _weekdays.contains(weekday);
                        return GestureDetector(
                          onTap: () => _toggleWeekday(weekday),
                          child: CircleAvatar(
                            radius: 20,
                            backgroundColor:
                                selected ? _primaryColor : _fieldBgColor,
                            child: Text(
                              _weekdayLabels[i],
                              style: TextStyle(
                                color:
                                    selected ? Colors.white : Colors.black54,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: TextButton.icon(
                        onPressed: _toggleEveryDay,
                        icon: Icon(
                          _weekdays.length == 7
                              ? Icons.check_circle
                              : Icons.check_circle_outline,
                          size: 18,
                          color: _weekdays.length == 7
                              ? _primaryColor
                              : Colors.black38,
                        ),
                        label: Text(
                          '매일 받을래요',
                          style: TextStyle(
                            color: _weekdays.length == 7
                                ? _primaryColor
                                : Colors.black45,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isValid ? _submit : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryColor,
                      disabledBackgroundColor: _fieldBgColor,
                      foregroundColor: Colors.white,
                      disabledForegroundColor: Colors.black38,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                      elevation: 0,
                    ),
                    child: Text(_isEditing ? '수정 완료' : '추가 완료'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 시계 다이얼 없이 시·분을 바로 타이핑해 입력하는 시간 선택 다이얼로그.
/// 앱 전체 톤(흰 배경, 라운드, primary 색)에 맞춘 커스텀 UI.
class _TimeInputDialog extends StatefulWidget {
  final TimeOfDay initial;

  const _TimeInputDialog({required this.initial});

  @override
  State<_TimeInputDialog> createState() => _TimeInputDialogState();
}

class _TimeInputDialogState extends State<_TimeInputDialog> {
  late bool _isPm = widget.initial.period == DayPeriod.pm;
  late final TextEditingController _hourController = TextEditingController(
    text: '${widget.initial.hourOfPeriod == 0 ? 12 : widget.initial.hourOfPeriod}',
  );
  late final TextEditingController _minuteController = TextEditingController(
    text: widget.initial.minute.toString().padLeft(2, '0'),
  );

  @override
  void dispose() {
    _hourController.dispose();
    _minuteController.dispose();
    super.dispose();
  }

  TimeOfDay? get _parsed {
    final hour12 = int.tryParse(_hourController.text);
    final minute = int.tryParse(_minuteController.text);
    if (hour12 == null || minute == null) return null;
    if (hour12 < 1 || hour12 > 12 || minute < 0 || minute > 59) return null;
    final base = hour12 % 12;
    return TimeOfDay(hour: _isPm ? base + 12 : base, minute: minute);
  }

  void _confirm() {
    final value = _parsed;
    if (value == null) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final valid = _parsed != null;
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '알림 받을 시간',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
            ),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PeriodToggle(
                  isPm: _isPm,
                  onChanged: (v) => setState(() => _isPm = v),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _TimeField(
                    controller: _hourController,
                    label: '시',
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 14),
                  child: Text(
                    ':',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Colors.black38,
                    ),
                  ),
                ),
                Expanded(
                  child: _TimeField(
                    controller: _minuteController,
                    label: '분',
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(foregroundColor: Colors.black45),
                  child: const Text('취소'),
                ),
                TextButton(
                  onPressed: valid ? _confirm : null,
                  style: TextButton.styleFrom(foregroundColor: _primaryColor),
                  child: const Text('확인'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 오전/오후를 세로로 전환하는 작은 토글.
class _PeriodToggle extends StatelessWidget {
  final bool isPm;
  final ValueChanged<bool> onChanged;

  const _PeriodToggle({required this.isPm, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: _fieldBgColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          for (final pm in const [false, true])
            GestureDetector(
              onTap: () => onChanged(pm),
              child: Container(
                width: 52,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isPm == pm ? _primaryColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                alignment: Alignment.center,
                child: Text(
                  pm ? '오후' : '오전',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isPm == pm ? Colors.white : Colors.black45,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 시 또는 분을 입력하는 두 자리 숫자 필드 + 아래 라벨.
class _TimeField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final ValueChanged<String> onChanged;

  const _TimeField({
    required this.controller,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: controller,
          onChanged: onChanged,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          maxLength: 2,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: _fieldBgColor,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _primaryColor, width: 1.6),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.black45,
          ),
        ),
      ],
    );
  }
}
