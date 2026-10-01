import 'package:flutter/material.dart';

import 'calorie_dashboard.dart';
import 'center_toast.dart';
import 'firestore_service.dart';
import 'push_notification_service.dart';

const _primary = Color(0xFF3F5F8B);

/// 온보딩·도움말 튜토리얼 직후 1회 노출. 대시보드를 배경으로 두고 그 위에
/// 하루 기록 리마인더 푸시를 받을지 묻는 다이얼로그를 띄운다. "예"를 선택하면
/// 그 자리에서 OS 알림 권한을 요청해 등록한다.
class ReminderPermissionScreen extends StatefulWidget {
  const ReminderPermissionScreen({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  State<ReminderPermissionScreen> createState() =>
      _ReminderPermissionScreenState();
}

class _ReminderPermissionScreenState extends State<ReminderPermissionScreen> {
  bool _dialogShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _showDialog());
  }

  Future<void> _showDialog() async {
    if (_dialogShown || !mounted) return;
    _dialogShown = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ReminderPermissionDialog(onAnswer: _answer),
    );
    widget.onDone();
  }

  /// 다이얼로그 버튼 선택에 따른 실제 처리. 팝업을 닫는 것과는 분리해,
  /// 권한 요청이 끝난 뒤에 다이얼로그가 닫히도록 한다.
  Future<void> _answer(bool yes) async {
    if (!yes) return;
    final granted =
        await PushNotificationService.requestPermissionAndRegister();
    FirestoreService.saveDailyReminderEnabled(granted);
    if (!granted && mounted) {
      showCenterToast(context, '알림 권한이 꺼져 있어요. 나중에 설정에서 켤 수 있어요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const CalorieDashboardPage();
  }
}

class _ReminderPermissionDialog extends StatefulWidget {
  const _ReminderPermissionDialog({required this.onAnswer});

  final Future<void> Function(bool yes) onAnswer;

  @override
  State<_ReminderPermissionDialog> createState() =>
      _ReminderPermissionDialogState();
}

class _ReminderPermissionDialogState
    extends State<_ReminderPermissionDialog> {
  bool _busy = false;

  Future<void> _tap(bool yes) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onAnswer(yes);
    } finally {
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.notifications_active_outlined,
              size: 48,
              color: _primary,
            ),
            const SizedBox(height: 16),
            const Text(
              '매일 저녁 식단 기록을\n리마인드 해드릴까요?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '그날 기록이 없으면 저녁에 알림으로 살짝 알려드려요\n설정에서 다른 알림을 추가하거나 끌 수 있어요',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.5),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _busy ? null : () => _tap(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        '예, 알림 받을게요',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: _busy ? null : () => _tap(false),
                child: const Text(
                  '아니요, 나중에 할게요',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.black54,
                    fontWeight: FontWeight.w600,
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
