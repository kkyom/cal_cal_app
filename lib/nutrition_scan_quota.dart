/// `parseNutritionLabel`(functions/index.js)의 무료 일일 한도를 클라이언트에서
/// 조회·표시하기 위한 공용 유틸. 스캔 화면(실시간 구독)과 검색 화면(진입 전
/// 1회 체크) 양쪽에서 같은 기준으로 써야 하므로 여기 하나로 모아둔다.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// functions/index.js의 FREE_DAILY_SCAN_LIMIT과 동일하게 맞춘다.
const int kFreeDailyScanLimit = 10;

/// Asia/Seoul 기준 오늘 날짜(YYYY-MM-DD). 서버의 `todayInSeoul()`과 동일한
/// 기준이어야 한다. 한국은 서머타임이 없어 UTC+9 고정 오프셋으로 충분하다.
String todayInSeoul() {
  final seoul = DateTime.now().toUtc().add(const Duration(hours: 9));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${seoul.year}-${two(seoul.month)}-${two(seoul.day)}';
}

/// `nutritionScanQuota/{uid}` 문서 하나를 화면에서 쓰기 좋게 요약한 것.
class NutritionScanQuotaStatus {
  const NutritionScanQuotaStatus({
    required this.isSubscribed,
    required this.remaining,
  });

  final bool isSubscribed;
  final int remaining;

  bool get isExhausted => !isSubscribed && remaining <= 0;

  factory NutritionScanQuotaStatus.fromDoc(Map<String, dynamic>? data) {
    if (data == null) {
      return const NutritionScanQuotaStatus(
        isSubscribed: false,
        remaining: kFreeDailyScanLimit,
      );
    }
    if (data['tier'] == 'subscribed') {
      return const NutritionScanQuotaStatus(
        isSubscribed: true,
        remaining: kFreeDailyScanLimit,
      );
    }
    // 날짜가 오늘이 아니면 서버가 아직 리셋 전이어도 이미 새 하루로 본다
    // (consumeNutritionScanQuota의 리셋 로직과 동일).
    final usedToday = data['scanDate'] == todayInSeoul()
        ? ((data['scanCount'] as num?)?.toInt() ?? 0)
        : 0;
    final remaining = kFreeDailyScanLimit - usedToday;
    return NutritionScanQuotaStatus(
      isSubscribed: false,
      remaining: remaining < 0 ? 0 : remaining,
    );
  }
}

DocumentReference<Map<String, dynamic>>? _quotaDocRef() {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return null;
  return FirebaseFirestore.instance.collection('nutritionScanQuota').doc(uid);
}

/// 로그인된 사용자의 quota 문서를 실시간 구독한다. 로그인 안 됐으면 null.
Stream<DocumentSnapshot<Map<String, dynamic>>>? nutritionScanQuotaStream() {
  return _quotaDocRef()?.snapshots();
}

/// 스트림 구독 없이 한 번만 조회한다. 스캔 화면 진입 전 즉시 체크할 때 쓴다.
Future<NutritionScanQuotaStatus> fetchNutritionScanQuotaStatus() async {
  final ref = _quotaDocRef();
  if (ref == null) {
    return const NutritionScanQuotaStatus(
      isSubscribed: false,
      remaining: kFreeDailyScanLimit,
    );
  }
  final snap = await ref.get();
  return NutritionScanQuotaStatus.fromDoc(snap.data());
}
