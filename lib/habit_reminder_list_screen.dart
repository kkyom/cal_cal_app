import 'package:flutter/material.dart';

import 'center_toast.dart';
import 'firestore_service.dart';
import 'habit_reminder_edit_screen.dart';
import 'models.dart';
import 'notification_service.dart';
import 'responsive_content.dart';

const Color _bgColor = Color(0xFFF2F2F2);
const Color _primaryColor = Color(0xFF3F5F8B);
const Color _cardBgColor = Color(0xFFEDEDED);

const List<String> _weekdayLabels = ['월', '화', '수', '목', '금', '토', '일'];

String _formatSchedule(HabitReminder r) {
  final period = r.hour < 12 ? '오전' : '오후';
  final hourOfPeriod = r.hour % 12 == 0 ? 12 : r.hour % 12;
  final minute = r.minute.toString().padLeft(2, '0');
  final time = '$period $hourOfPeriod:$minute';
  if (r.weekdays.length == 7) return '매일 $time';
  final sorted = [...r.weekdays]..sort();
  final days = sorted.map((w) => _weekdayLabels[w - 1]).join(',');
  return '$days $time';
}

/// 설정 > 알림 설정 > 나만의 습관 알림. 사용자가 직접 추가한 리마인더 목록을
/// 보여주고 켜고 끄거나, 눌러서 수정/삭제할 수 있다.
class HabitReminderListScreen extends StatefulWidget {
  const HabitReminderListScreen({super.key});

  @override
  State<HabitReminderListScreen> createState() =>
      _HabitReminderListScreenState();
}

class _HabitReminderListScreenState extends State<HabitReminderListScreen> {
  List<HabitReminder> _reminders = FirestoreService.loadHabitReminders();
  bool _busy = false;

  /// 실제 OS 알림 예약을 현재 [_reminders] 상태에 맞추고 Firestore에 저장한다.
  /// 권한이 거부되면 모든 항목을 꺼진 상태로 되돌린다(실제로 예약이 안 되므로).
  Future<void> _applyAndPersist() async {
    setState(() => _busy = true);
    final applied = await NotificationService.syncHabitReminders(_reminders);
    if (!mounted) return;
    if (!applied) {
      setState(() {
        _reminders = [for (final r in _reminders) r.copyWith(enabled: false)];
      });
      showCenterToast(context, '알림 권한이 꺼져 있어요. 기기 설정에서 알림을 허용해 주세요.');
    }
    FirestoreService.saveHabitReminders(_reminders);
    setState(() => _busy = false);
  }

  Future<void> _toggleReminder(int index, bool value) async {
    if (_busy) return;
    setState(() {
      _reminders[index] = _reminders[index].copyWith(enabled: value);
    });
    await _applyAndPersist();
  }

  Future<void> _addReminder() async {
    if (_busy) return;
    final result = await Navigator.of(context).push<HabitReminderEditResult>(
      MaterialPageRoute(builder: (_) => const HabitReminderEditScreen()),
    );
    if (result is! HabitReminderSaved) return;
    setState(() => _reminders = [..._reminders, result.reminder]);
    await _applyAndPersist();
  }

  Future<void> _editReminder(int index) async {
    if (_busy) return;
    final result = await Navigator.of(context).push<HabitReminderEditResult>(
      MaterialPageRoute(
        builder: (_) => HabitReminderEditScreen(initial: _reminders[index]),
      ),
    );
    if (result == null) return;
    if (result is HabitReminderSaved) {
      setState(() => _reminders[index] = result.reminder);
    } else if (result is HabitReminderDeleted) {
      setState(() => _reminders.removeAt(index));
    }
    await _applyAndPersist();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        elevation: 0,
        foregroundColor: Colors.black87,
      ),
      body: ResponsiveContent(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          children: [
            const Text(
              '직접 알림 설정하기',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22),
            ),
            const SizedBox(height: 8),
            const Text(
              '식단 기록, 영양제 먹기, 운동 등\n내 습관에 맞는 알림을 직접 설정해요',
              style: TextStyle(
                fontSize: 13,
                color: Colors.black45,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            for (var i = 0; i < _reminders.length; i++) ...[
              _HabitReminderCard(
                reminder: _reminders[i],
                busy: _busy,
                onTap: () => _editReminder(i),
                onToggle: (v) => _toggleReminder(i, v),
              ),
              const SizedBox(height: 12),
            ],
            Center(
              child: TextButton.icon(
                onPressed: _busy ? null : _addReminder,
                icon: const Icon(Icons.add, color: _primaryColor),
                label: const Text(
                  '알림 추가',
                  style: TextStyle(
                    color: _primaryColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HabitReminderCard extends StatelessWidget {
  final HabitReminder reminder;
  final bool busy;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;

  const _HabitReminderCard({
    required this.reminder,
    required this.busy,
    required this.onTap,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _cardBgColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: busy ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 22,
                backgroundColor: Colors.white,
                child: Icon(
                  Icons.notifications_outlined,
                  color: _primaryColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reminder.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatSchedule(reminder),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black45,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: reminder.enabled,
                activeThumbColor: Colors.white,
                activeTrackColor: Colors.black87,
                onChanged: busy ? null : onToggle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
