import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import 'center_toast.dart';
import 'firestore_service.dart';
import 'habit_reminder_list_screen.dart';
import 'push_notification_service.dart';
import 'responsive_content.dart';

const Color _bgColor = Color(0xFFF2F2F2);
const Color _primaryColor = Color(0xFF3F5F8B);

/// 설정 > 알림 설정. 매일 저녁 8시 고정 리마인더와, 사용자가 직접 여러 개
/// 추가하는 습관 알림 목록으로 진입하는 메뉴를 보여준다.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  bool _dailyEnabled = FirestoreService.loadDailyReminderEnabled();
  bool _dailyBusy = false;

  /// 하루 기록 리마인더(서버가 그날 기록 여부를 확인해 저녁 8시에 푸시) on/off.
  /// 켤 때 이 기기의 FCM 토큰을 등록하고, 권한이 거부되면 값을 되돌린다.
  Future<void> _toggleDailyReminder(bool value) async {
    if (_dailyBusy) return;
    setState(() {
      _dailyBusy = true;
      _dailyEnabled = value;
    });
    try {
      if (!value) {
        await PushNotificationService.unregister();
        FirestoreService.saveDailyReminderEnabled(false);
        return;
      }
      final granted =
          await PushNotificationService.requestPermissionAndRegister();
      if (!mounted) return;
      if (!granted) {
        setState(() => _dailyEnabled = false);
        FirestoreService.saveDailyReminderEnabled(false);
        showCenterToast(context, '알림 권한이 꺼져 있어요. 기기 설정에서 알림을 허용해 주세요.');
        return;
      }
      FirestoreService.saveDailyReminderEnabled(true);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('하루 기록 리마인더 토글 실패: $e\n$st');
      }
      if (!mounted) return;
      setState(() => _dailyEnabled = !value);
      showCenterToast(context, '알림 설정을 변경하지 못했어요. 잠시 후 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _dailyBusy = false);
    }
  }

  void _openHabitReminders() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const HabitReminderListScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text(
          '알림 설정',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: ResponsiveContent(
        child: ListView(
          children: [
            SwitchListTile(
              secondary: const Icon(
                Icons.notifications_outlined,
                color: _primaryColor,
              ),
              title: const Text(
                '하루 기록 리마인더',
                style: TextStyle(color: Colors.black),
              ),
              subtitle: const Text(
                '매일 저녁 8시, 식단 기록을 안 했으면 알려드려요',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              activeThumbColor: _primaryColor,
              value: _dailyEnabled,
              onChanged: _dailyBusy ? null : _toggleDailyReminder,
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(
                Icons.checklist_outlined,
                color: _primaryColor,
              ),
              title: const Text(
                '직접 알림 설정하기',
                style: TextStyle(color: Colors.black),
              ),
              subtitle: const Text(
                '식단 기록, 영양제 먹기, 운동 등 내 습관에 맞는 알림을 직접 설정해요',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _openHabitReminders,
            ),
            const Divider(height: 1),
          ],
        ),
      ),
    );
  }
}
