// ---- 광고 배너 비활성화 (무료 출시, 추후 복구 시 이 블록 주석 해제) ----
// TODO: 광고 재도입 시 아래 주석 해제 + pubspec.yaml의 google_mobile_ads 의존성 복구
/*
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// 화면별 배너 광고 단위 ID.
///
/// Android는 아직 AdMob에 앱을 등록하지 않아 Google 공식 테스트용 ID를 쓰고,
/// 실제 발급받으면 각 getter의 Android 분기 값을 교체해야 함.
class AdUnitIds {
  AdUnitIds._();

  static const String _androidTestBanner =
      'ca-app-pub-3940256099942544/6300978111';

  static String get dashboard => Platform.isAndroid
      ? _androidTestBanner
      : 'ca-app-pub-9636739231879504/3739536624';

  static String get foodSearch => Platform.isAndroid
      ? _androidTestBanner
      : 'ca-app-pub-9636739231879504/9001220135';

  static String get settings => Platform.isAndroid
      ? _androidTestBanner
      : 'ca-app-pub-9636739231879504/5424937209';

  static String get goalEdit => Platform.isAndroid
      ? _androidTestBanner
      : 'ca-app-pub-9636739231879504/1225003590';
}

/// 실제 광고 SDK 없이 배치 위치만 확인하기 위한 회색 자리표시자.
/// 표준 배너 크기(320x50)와 동일하게 만들어 실제 배너로 교체해도 레이아웃이 안 흔들리게 함.
class AdBannerPlaceholder extends StatelessWidget {
  const AdBannerPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
      height: 50,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '광고 영역',
        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
      ),
    );
  }
}

class AdBannerWidget extends StatefulWidget {
  final String adUnitId;

  const AdBannerWidget({super.key, required this.adUnitId});

  @override
  State<AdBannerWidget> createState() => _AdBannerWidgetState();
}

class _AdBannerWidgetState extends State<AdBannerWidget> {
  BannerAd? _bannerAd;

  @override
  void initState() {
    super.initState();
    final bannerAd = BannerAd(
      adUnitId: widget.adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() => _bannerAd = ad as BannerAd);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
        },
      ),
    );
    bannerAd.load();
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bannerAd = _bannerAd;
    if (bannerAd == null) return const SizedBox.shrink();
    return Container(
      alignment: Alignment.center,
      width: bannerAd.size.width.toDouble(),
      height: bannerAd.size.height.toDouble(),
      child: AdWidget(ad: bannerAd),
    );
  }
}
*/
