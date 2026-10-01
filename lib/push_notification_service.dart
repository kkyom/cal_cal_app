import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'firestore_service.dart';
import 'notification_service.dart';

/// FCM 기반 서버 푸시("하루 기록 리마인더")를 위한 토큰 등록·수신 처리.
/// 실제로 그날 기록했는지 확인하는 로직은 서버(Cloud Functions 예약 함수)에
/// 있고, 클라이언트는 토큰을 등록해두고 도착한 메시지를 표시하기만 한다.
class PushNotificationService {
  PushNotificationService._();

  static bool _initialized = false;
  static String? _lastToken;

  /// 앱 시작 시 1회 호출. 포그라운드 수신 시 로컬 알림으로 즉시 표시하고,
  /// 토큰이 갱신되면(로그인 상태일 때) 자동으로 다시 저장한다.
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    FirebaseMessaging.onMessage.listen((message) {
      final notification = message.notification;
      if (notification == null) return;
      NotificationService.showNow(
        title: notification.title ?? '칼캘',
        body: notification.body ?? '',
      );
    });

    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      _lastToken = token;
      if (FirestoreService.isReady) {
        FirestoreService.addFcmToken(token);
      }
    });
  }

  /// 알림 권한을 요청하고, 허용되면 토큰을 발급받아 Firestore에 저장한다.
  /// 거부되면 false.
  static Future<bool> requestPermissionAndRegister() async {
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    final granted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    if (!granted) {
      if (kDebugMode) {
        debugPrint('푸시 알림 권한이 거부됨: ${settings.authorizationStatus}');
      }
      return false;
    }
    // iOS는 권한 허용 직후 APNS 토큰이 OS로부터 비동기로 전달되는데, 그 전에
    // getToken()을 호출하면 apns-token-not-set 예외가 난다. 짧게 재시도하며 기다린다.
    if (!kIsWeb && Platform.isIOS) {
      String? apnsToken = await FirebaseMessaging.instance.getAPNSToken();
      var attempts = 0;
      while (apnsToken == null && attempts < 10) {
        await Future.delayed(const Duration(milliseconds: 500));
        apnsToken = await FirebaseMessaging.instance.getAPNSToken();
        attempts += 1;
      }
      if (apnsToken == null) {
        if (kDebugMode) {
          debugPrint('APNS 토큰을 받지 못해 FCM 토큰 등록을 포기함');
        }
        return false;
      }
    }
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return false;
    _lastToken = token;
    FirestoreService.addFcmToken(token);
    return true;
  }

  /// 이 기기의 토큰을 서버 목록에서 지운다(리마인더를 끌 때).
  static Future<void> unregister() async {
    final token =
        _lastToken ?? await FirebaseMessaging.instance.getToken();
    if (token != null) {
      FirestoreService.removeFcmToken(token);
    }
  }
}
