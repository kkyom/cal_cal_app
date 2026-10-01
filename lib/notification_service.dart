import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';

/// 로컬 알림을 담당한다. 두 가지 용도로 쓴다.
/// - 나만의 습관 알림: 사용자가 이모지·이름·시간·요일을 정해 여러 개 추가(요일 반복 예약).
/// - 포그라운드에서 받은 FCM 푸시(하루 기록 리마인더 등)를 즉시 화면에 띄우는 용도.
///   ("하루 기록 리마인더" 자체는 서버 Cloud Function이 기록 여부를 확인해 FCM으로
///   보내므로 이 서비스가 직접 스케줄링하지 않는다.)
/// 시간대는 서비스 지역이 한국 단일이라 'Asia/Seoul'로 고정한다.
class NotificationService {
  NotificationService._();

  /// 포그라운드 수신 FCM 메시지를 즉시 보여줄 때 쓰는 알림 id.
  static const int _foregroundPushId = 9001;

  static const AndroidNotificationDetails _foregroundPushAndroidDetails =
      AndroidNotificationDetails(
    'foreground_push',
    '알림',
    channelDescription: '앱 사용 중 도착한 알림',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );

  static const NotificationDetails _foregroundPushDetails = NotificationDetails(
    android: _foregroundPushAndroidDetails,
    iOS: DarwinNotificationDetails(),
  );

  /// 습관 알림은 리마인더별로 요일마다 개별 예약이 필요해 id를
  /// `_habitReminderBaseId + reminder.id * 10 + weekday`로 계산한다.
  /// reminder.id는 생성 시각(ms) 기반이라 폭이 넓어 곱셈 오버플로를
  /// 피하려고 정수 범위를 좁혀서(마지막 6자리) 쓴다.
  static const int _habitReminderBaseId = 6000000;

  static const AndroidNotificationDetails _habitAndroidDetails =
      AndroidNotificationDetails(
    'habit_reminder',
    '나만의 습관 알림',
    channelDescription: '식단 기록, 물 마시기, 운동 등 사용자가 만든 습관 알림',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );

  static const NotificationDetails _habitDetails = NotificationDetails(
    android: _habitAndroidDetails,
    iOS: DarwinNotificationDetails(),
  );

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;

  /// 앱 시작 시 1회 호출. 플러그인 초기화 + 타임존 데이터 로드.
  static Future<void> init() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Seoul'));

    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );
    _initialized = true;
  }

  /// 알림 권한을 요청한다. 사용자가 거부하면 false.
  static Future<bool> requestPermission() async {
    final androidImpl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidImpl != null) {
      final granted = await androidImpl.requestNotificationsPermission();
      return granted ?? false;
    }

    final iosImpl = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (iosImpl != null) {
      final granted = await iosImpl.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return granted ?? false;
    }
    return true;
  }

  /// 포그라운드에서 도착한 FCM 메시지를 즉시 화면에 띄운다.
  /// (앱이 포그라운드일 땐 OS가 알림을 자동으로 보여주지 않는다.)
  static Future<void> showNow({required String title, required String body}) async {
    await _plugin.show(_foregroundPushId, title, body, _foregroundPushDetails);
  }

  /// [weekday] 이후로 가장 가까운 hour:minute 시각을 찾는다.
  /// DateTime.weekday 기준 (월=1 ... 일=7).
  static tz.TZDateTime _nextInstanceOfWeekdayTime(
    int weekday,
    int hour,
    int minute,
  ) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    while (scheduled.weekday != weekday || scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  static int _habitNotificationId(int reminderId, int weekday) =>
      _habitReminderBaseId + (reminderId % 1000000) * 10 + weekday;

  static Future<void> cancelHabitReminder(int reminderId) async {
    for (var weekday = 1; weekday <= 7; weekday++) {
      await _plugin.cancel(_habitNotificationId(reminderId, weekday));
    }
  }

  /// 하나의 습관 알림을 예약한다. 꺼져 있거나 요일이 없으면 취소만 한다.
  static Future<void> scheduleHabitReminder(HabitReminder reminder) async {
    await cancelHabitReminder(reminder.id);
    if (!reminder.enabled || reminder.weekdays.isEmpty) return;
    final title = reminder.name.isEmpty ? '칼캘' : reminder.name;
    for (final weekday in reminder.weekdays) {
      await _plugin.zonedSchedule(
        _habitNotificationId(reminder.id, weekday),
        title,
        '오늘도 습관 하나 챙겨볼까요?',
        _nextInstanceOfWeekdayTime(weekday, reminder.hour, reminder.minute),
        _habitDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      );
    }
  }

  /// 습관 알림 목록 전체를 저장된 값 기준으로 다시 예약한다.
  /// 하나라도 켜져 있으면 권한을 요청하고, 거부되면 모두 취소 후 false.
  static Future<bool> syncHabitReminders(List<HabitReminder> reminders) async {
    final anyEnabled =
        reminders.any((r) => r.enabled && r.weekdays.isNotEmpty);
    if (anyEnabled) {
      final granted = await requestPermission();
      if (!granted) {
        for (final r in reminders) {
          await cancelHabitReminder(r.id);
        }
        if (kDebugMode) {
          debugPrint('알림 권한이 거부되어 습관 알림을 예약하지 않음');
        }
        return false;
      }
    }
    for (final r in reminders) {
      await scheduleHabitReminder(r);
    }
    return true;
  }
}
