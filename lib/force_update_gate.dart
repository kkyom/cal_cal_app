import 'dart:async';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'center_toast.dart';

const Color _primaryColor = Color(0xFF3F5F8B);

/// 강제 업데이트에 쓰는 Remote Config 키.
///
/// 콘솔에 값을 넣기 전에는 기본값이 빈 문자열이라 강제 업데이트가 꺼져 있다.
/// - `min_version_ios` / `min_version_android`: 이 버전보다 낮으면 앱을 막는다
///   (예: `1.1.1`). pubspec 의 `version:` 에서 `+` 앞부분과 비교한다.
/// - `store_url_ios` / `store_url_android`: 업데이트 버튼이 여는 스토어 주소.
/// - `force_update_message`: 안내 문구(선택). 비우면 기본 문구를 쓴다.
class ForceUpdateKeys {
  ForceUpdateKeys._();

  static const String minVersionIos = 'min_version_ios';
  static const String minVersionAndroid = 'min_version_android';
  static const String storeUrlIos = 'store_url_ios';
  static const String storeUrlAndroid = 'store_url_android';
  static const String message = 'force_update_message';
}

/// 업데이트가 필요할 때 화면에 보여 줄 정보.
class ForceUpdateInfo {
  const ForceUpdateInfo({required this.storeUrl, required this.message});

  final String storeUrl;
  final String message;
}

/// Remote Config 의 최소 버전과 현재 앱 버전을 비교한다.
///
/// Remote Config 는 Firestore 와 달리 OS 인증서 저장소를 쓰는 일반 HTTPS 라서,
/// Firestore 보안 이슈가 있는 예전 빌드에서도 이 확인은 정상 동작한다.
class ForceUpdateService {
  ForceUpdateService._();

  static Future<void>? _setup;

  static Future<void> _ensureSetup(FirebaseRemoteConfig rc) {
    return _setup ??= () async {
      await rc.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 5),
          minimumFetchInterval: kDebugMode
              ? Duration.zero
              : const Duration(minutes: 30),
        ),
      );
      await rc.setDefaults(const {
        ForceUpdateKeys.minVersionIos: '',
        ForceUpdateKeys.minVersionAndroid: '',
        ForceUpdateKeys.storeUrlIos: '',
        ForceUpdateKeys.storeUrlAndroid: '',
        ForceUpdateKeys.message: '',
      });
    }();
  }

  /// 업데이트가 필요하면 정보를, 아니면 null 을 돌려준다.
  ///
  /// 가져오기에 실패하면 마지막으로 받아 둔 값으로 판단하고, 그것도 없으면
  /// 앱을 막지 않는다(Remote Config 장애로 모든 사용자가 갇히지 않게).
  static Future<ForceUpdateInfo?> check() async {
    if (kIsWeb) return null;
    final String minKey;
    final String urlKey;
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        minKey = ForceUpdateKeys.minVersionIos;
        urlKey = ForceUpdateKeys.storeUrlIos;
      case TargetPlatform.android:
        minKey = ForceUpdateKeys.minVersionAndroid;
        urlKey = ForceUpdateKeys.storeUrlAndroid;
      default:
        return null;
    }

    try {
      final rc = FirebaseRemoteConfig.instance;
      try {
        await _ensureSetup(rc);
        await rc.fetchAndActivate().timeout(const Duration(seconds: 6));
      } catch (e) {
        _setup = null;
        debugPrint('강제 업데이트: Remote Config 가져오기 실패(저장된 값 사용): $e');
      }

      final minVersion = rc.getString(minKey).trim();
      if (minVersion.isEmpty) return null;

      final current = (await PackageInfo.fromPlatform()).version;
      if (!isVersionLower(current, minVersion)) return null;

      return ForceUpdateInfo(
        storeUrl: rc.getString(urlKey).trim(),
        message: rc.getString(ForceUpdateKeys.message).trim(),
      );
    } catch (e) {
      debugPrint('강제 업데이트: 확인 실패(통과): $e');
      return null;
    }
  }
}

/// [current] 가 [minimum] 보다 낮은 버전이면 true.
///
/// `1.2.3`, `1.2.3+7` 같은 형식을 숫자 단위로 비교한다. 읽을 수 없는 조각은
/// 0 으로 본다.
@visibleForTesting
bool isVersionLower(String current, String minimum) {
  List<int> parse(String v) => v
      .split('+')
      .first
      .split('-')
      .first
      .split('.')
      .map((p) => int.tryParse(p.trim()) ?? 0)
      .toList();

  final a = parse(current);
  final b = parse(minimum);
  final length = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < length; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x < y;
  }
  return false;
}

/// 최소 버전보다 낮은 앱이면 본문 대신 업데이트 화면을 보여 준다.
///
/// 앱을 켤 때와 백그라운드에서 돌아올 때마다 확인한다.
class ForceUpdateGate extends StatefulWidget {
  const ForceUpdateGate({super.key, required this.child});

  final Widget child;

  @override
  State<ForceUpdateGate> createState() => _ForceUpdateGateState();
}

class _ForceUpdateGateState extends State<ForceUpdateGate>
    with WidgetsBindingObserver {
  bool _checking = true;
  bool _inFlight = false;
  ForceUpdateInfo? _update;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      final update = await ForceUpdateService.check();
      if (!mounted) return;
      setState(() {
        _update = update;
        _checking = false;
      });
    } finally {
      _inFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: Color(0xFFF2F2F2),
        body: Center(child: CircularProgressIndicator(color: _primaryColor)),
      );
    }
    final update = _update;
    if (update != null) return ForceUpdateScreen(info: update);
    return widget.child;
  }
}

/// 업데이트 전에는 앱을 쓸 수 없게 막는 전체 화면.
class ForceUpdateScreen extends StatelessWidget {
  const ForceUpdateScreen({super.key, required this.info});

  final ForceUpdateInfo info;

  static const String _defaultMessage =
      '더 안전하게 쓰실 수 있도록 새 버전이 나왔어요.\n업데이트 후 계속 이용해 주세요.';

  Future<void> _openStore(BuildContext context) async {
    var opened = false;
    final uri = Uri.tryParse(info.storeUrl);
    if (info.storeUrl.isNotEmpty && uri != null) {
      try {
        opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (e) {
        debugPrint('강제 업데이트: 스토어 열기 실패: $e');
      }
    }
    if (!opened && context.mounted) {
      showCenterToast(context, '스토어에서 \'칼캘\'을 검색해 업데이트해 주세요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    // 콘솔 입력칸은 한 줄이라 줄바꿈을 `\n` 글자로 적을 수 있게 한다.
    final message = info.message.isEmpty
        ? _defaultMessage
        : info.message.replaceAll(r'\n', '\n');

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFFF2F2F2),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.system_update_rounded,
                      size: 64,
                      color: _primaryColor.withValues(alpha: 0.85),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      '업데이트가 필요해요',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1F2D3D),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: Colors.black.withValues(alpha: 0.55),
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: _primaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: () => _openStore(context),
                        child: const Text(
                          '업데이트하기',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
