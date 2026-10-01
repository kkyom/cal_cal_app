import 'dart:io' show Platform;
import 'dart:ui' as ui;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'auth_service.dart';
import 'firestore_service.dart';

/// 문의 종류. 메일 제목 접두어로 쓰인다.
enum SupportTopic {
  inquiry('문의'),
  bug('오류 신고');

  const SupportTopic(this.label);

  final String label;
}

/// 설정 > 문의 및 피드백. `mailto:` 링크로 메일 앱을 열고, 앱 버전·기기 정보 등
/// 진단 정보를 본문에 미리 채워 왕복 문의를 줄인다.
class SupportService {
  SupportService._();

  /// 앱 내 문의·오류 신고 수신 주소.
  static const String supportEmail = 'kyomdev@gmail.com';

  /// 진단 정보 블록. 메일 본문 하단에 첨부된다.
  /// (앱 버전, 플랫폼, OS 버전, 기기 모델, 사용자 식별자, 로그인 수단, 언어)
  static Future<String> buildDiagnostics() async {
    final lines = <String>['앱 버전: ${await _appVersion()}'];

    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isIOS) {
        final ios = await deviceInfo.iosInfo;
        lines
          ..add('플랫폼: iOS ${ios.systemVersion}')
          ..add('기기: ${ios.utsname.machine}${ios.isPhysicalDevice ? '' : ' (시뮬레이터)'}');
      } else if (Platform.isAndroid) {
        final android = await deviceInfo.androidInfo;
        lines
          ..add('플랫폼: Android ${android.version.release} (SDK ${android.version.sdkInt})')
          ..add('기기: ${android.manufacturer} ${android.model}${android.isPhysicalDevice ? '' : ' (에뮬레이터)'}');
      } else {
        lines.add('플랫폼: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
      }
    } catch (e) {
      debugPrint('기기 정보 조회 실패: $e');
      lines.add('플랫폼: ${Platform.operatingSystem} (상세 조회 실패)');
    }

    final user = AuthService.currentUser;
    lines
      ..add('사용자: ${user == null ? '미로그인' : (AuthService.isGuest ? '게스트 ${user.uid}' : user.uid)}')
      ..add('로그인 수단: ${FirestoreService.resolveAuthProvider() ?? (AuthService.isGuest ? 'guest' : '알 수 없음')}')
      ..add('언어: ${ui.PlatformDispatcher.instance.locale.toLanguageTag()}');

    return lines.join('\n');
  }

  static Future<String> _appVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version} (${info.buildNumber})';
    } catch (e) {
      debugPrint('앱 버전 조회 실패: $e');
      return '알 수 없음';
    }
  }

  /// 진단 정보를 본문에 채운 메일 작성 화면을 연다.
  /// [contextLabel]은 오류가 발생한 화면 이름 등(예: '음식 검색') — 제목과
  /// 진단 정보에 함께 담겨 어디서 생긴 문제인지 바로 알 수 있게 한다.
  /// [extraContent]는 앱 안에서 이미 받은 내용(예: 문의 유형·메모)이 있을 때
  /// 그 자리에 채운다 — 없으면 사용자가 메일 앱에서 직접 타이핑하도록 빈 줄을 남긴다.
  /// 메일 앱을 열 수 없으면 false (호출부에서 이메일 주소 안내로 대체).
  static Future<bool> composeMail(
    SupportTopic topic, {
    String? contextLabel,
    String? extraContent,
  }) async {
    final diagnostics = await buildDiagnostics();
    final where = contextLabel == null ? '' : '발생 위치: $contextLabel\n';
    final leading = (extraContent != null && extraContent.trim().isNotEmpty)
        ? '${extraContent.trim()}\n\n'
        : '\n\n\n';
    final body =
        '$leading'
        '──────────\n'
        '아래 정보는 문제 확인에 사용돼요. 지워도 됩니다.\n'
        '$where$diagnostics';

    final subject = contextLabel == null
        ? '[칼캘 ${topic.label}] '
        : '[칼캘 ${topic.label}] $contextLabel - ';

    final uri = Uri(
      scheme: 'mailto',
      path: supportEmail,
      query: _encodeQuery({
        'subject': subject,
        'body': body,
      }),
    );

    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('메일 앱 열기 실패: $e');
      return false;
    }
  }

  /// `mailto` 쿼리는 공백을 `+`가 아닌 `%20`으로 인코딩해야 메일 앱이 제대로 해석한다.
  static String _encodeQuery(Map<String, String> params) => params.entries
      .map((e) =>
          '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
      .join('&');
}
