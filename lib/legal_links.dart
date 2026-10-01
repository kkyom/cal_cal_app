import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// 개인정보처리방침·이용약관 공개 문서 URL.
class LegalLinks {
  LegalLinks._();

  static const String termsOfService =
      'https://app.notion.com/p/3b6e02e0a2e180188abacdcc49bfc121?source=copy_link';

  static const String privacyPolicy =
      'https://app.notion.com/p/3b6e02e0a2e1809e98c8eb9753ee6b3a?source=copy_link';

  /// 외부 브라우저로 문서를 연다. 실패 시 false.
  static Future<bool> open(String url) async {
    final uri = Uri.parse(url);
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('문서 열기 실패: $e');
      return false;
    }
  }

  static Future<bool> openTermsOfService() => open(termsOfService);

  static Future<bool> openPrivacyPolicy() => open(privacyPolicy);
}
