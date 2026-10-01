// ---- 인앱결제/구독 비활성화 (무료 출시, 추후 복구 시 이 블록 주석 해제) ----
// TODO: 결제 재도입 시 아래 주석 해제 + pubspec.yaml의 in_app_purchase 의존성 복구
/*
import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'firestore_service.dart';

/// StoreKit2 결제 흐름을 다루고, 결제 결과를 [FirestoreService]가 신뢰할 수
/// 있도록 서버(Cloud Function `verifyPurchase`)에 검증을 맡긴다.
///
/// 실제 구독 여부(`isPro`)는 여기서 판단하지 않는다 — 이 클래스는 결제를
/// "시작"하고 그 결과를 서버로 넘기는 역할만 하고, 최종 상태는 항상
/// `subscriptions/{uid}`(서버가 쓰는 문서)를 통해 [FirestoreService.loadIsPro]로
/// 읽는다.
class SubscriptionService {
  SubscriptionService._();

  // TODO: App Store Connect > Subscriptions에서 실제 등록한 productId로 교체.
  static const String proMonthlyProductId = 'com.kyom.calCalApp.pro_monthly';

  static final InAppPurchase _iap = InAppPurchase.instance;
  static StreamSubscription<List<PurchaseDetails>>? _sub;

  /// 로그인 직후 한 번 호출. 앱이 살아있는 동안 계속 구매 스트림을 리슨해서,
  /// 화면을 벗어난 뒤 결제가 완료되거나(비동기 승인 대기 등) 이전 세션의
  /// 미완료 트랜잭션이 재전달되는 경우까지 놓치지 않고 서버 검증까지 진행한다.
  static void start() {
    _sub?.cancel();
    _sub = _iap.purchaseStream.listen(
      _handlePurchaseUpdates,
      onError: (Object e) {
        debugPrint('SubscriptionService: purchaseStream 오류: $e');
      },
    );
  }

  /// 로그아웃/탈퇴 시 호출.
  static void stop() {
    _sub?.cancel();
    _sub = null;
  }

  static Future<void> _handlePurchaseUpdates(
    List<PurchaseDetails> purchases,
  ) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.pending) continue;

      if (purchase.status == PurchaseStatus.error) {
        debugPrint('SubscriptionService: 구매 오류: ${purchase.error}');
      } else if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        await _verifyWithServer(purchase);
      }

      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }

  /// transactionId를 Cloud Function(`verifyPurchase`)에 넘겨 서버가
  /// App Store Server API로 재검증하게 한다. subscriptions/{uid}는 그 안에서
  /// 갱신되고, 클라이언트는 FirestoreService의 실시간 리스너로 결과를 받는다.
  static Future<void> _verifyWithServer(PurchaseDetails purchase) async {
    final transactionId = purchase.purchaseID;
    if (transactionId == null) {
      debugPrint('SubscriptionService: purchaseID(transactionId) 없음');
      return;
    }
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-northeast3',
      ).httpsCallable('verifyPurchase');
      await callable.call<Map<String, dynamic>>({
        'transactionId': transactionId,
      });
    } catch (e) {
      debugPrint('SubscriptionService: 구매 검증 요청 실패: $e');
    }
  }

  /// 구독 상품 정보 조회. 스토어 연결 불가 또는 상품 미등록(ASC 설정 전)이면 null.
  static Future<ProductDetails?> queryProMonthly() async {
    final available = await _iap.isAvailable();
    if (!available) return null;
    final response = await _iap.queryProductDetails({proMonthlyProductId});
    if (response.productDetails.isEmpty) return null;
    return response.productDetails.first;
  }

  /// 구독하기 버튼에서 호출. appAccountToken을 먼저 준비해 결제 요청에
  /// 실어 보낸다 — 이 토큰이 있어야 App Store Server Notifications 웹훅이
  /// 나중에 어떤 uid의 구독인지 찾을 수 있다([FirestoreService.ensureAppAccountToken]).
  /// 실제 성공/실패는 여기서 반환하지 않고 [start]의 purchaseStream 리스너가 비동기로 처리한다.
  static Future<void> buyProMonthly(ProductDetails product) async {
    final token = await FirestoreService.ensureAppAccountToken();
    final purchaseParam = PurchaseParam(
      productDetails: product,
      applicationUserName: token,
    );
    await _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  static Future<void> restorePurchases() => _iap.restorePurchases();
}
*/
