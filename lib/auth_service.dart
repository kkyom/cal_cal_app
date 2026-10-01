import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' hide User;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import 'firestore_service.dart';
// import 'subscription_service.dart'; // 결제 비활성화

/// 게스트(익명) 계정을 소셜 계정에 연결하려 했으나, 이미 그 소셜 계정으로
/// 가입한 이력이 있어 연결할 수 없을 때 던져진다. [credential]로 기존 계정에
/// 로그인할 수 있지만, 게스트 기록은 새 계정으로 이어지지 않는다.
class GuestUpgradeConflictException implements Exception {
  final AuthCredential credential;

  GuestUpgradeConflictException(this.credential);
}

/// Google / Apple / Kakao 로그인을 Firebase Auth 세션으로 통합하는 서비스.
///
/// * Google, Apple은 Firebase Auth가 기본 지원하는 제공업체를 그대로 사용한다.
/// * Kakao는 Firebase Auth 기본 제공업체가 아니므로, Kakao 액세스 토큰을
///   Cloud Functions(`kakaoSignIn`)로 보내 서버에서 검증 후 발급받은
///   Firebase 커스텀 토큰으로 로그인한다.
class AuthService {
  AuthService._();

  /// Google Cloud Console에서 발급받은 "웹 클라이언트 ID"(OAuth 2.0 클라이언트 ID,
  /// 유형: 웹 애플리케이션). Firebase 콘솔에서 Google 로그인을 켜면 자동 생성되는
  /// 웹 클라이언트 ID를 그대로 넣으면 된다. (Android/iOS 네이티브 클라이언트 ID가 아님)
  static const String _googleServerClientId = '187584528817-4ldaevp02a8lbbkogct7rtabnpq9rat2.apps.googleusercontent.com';

  static bool _googleInitialized = false;

  static FirebaseAuth get _auth => FirebaseAuth.instance;

  /// 로그인 상태 변경 스트림. `AuthGate`에서 이 스트림을 구독해 화면을 전환한다.
  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  static User? get currentUser => _auth.currentUser;

  /// 현재 세션이 게스트(익명 로그인)인지 여부.
  static bool get isGuest => _auth.currentUser?.isAnonymous ?? false;

  /// 게스트(익명) 로그인. 로그인 없이 앱을 바로 체험할 수 있게 한다.
  /// 이후 [linkGuestWithGoogle]/[linkGuestWithApple]로 소셜 계정에 연결하면
  /// 그동안 쌓은 기록을 그대로 유지한 채 로그인 상태로 전환된다.
  static Future<UserCredential> signInAsGuest() {
    debugPrint('게스트: 익명 로그인 시작');
    return _auth.signInAnonymously();
  }

  static Future<void> _ensureGoogleInitialized() async {
    if (_googleInitialized) return;
    await GoogleSignIn.instance.initialize(
      serverClientId: _googleServerClientId,
    );
    _googleInitialized = true;
  }

  /// 사용자가 로그인 UI를 닫았거나 취소한 경우인지 판별한다.
  static bool isCanceled(Object error) {
    if (error is GoogleSignInException) {
      return error.code == GoogleSignInExceptionCode.canceled ||
          error.code == GoogleSignInExceptionCode.interrupted;
    }
    if (error is SignInWithAppleAuthorizationException) {
      return error.code == AuthorizationErrorCode.canceled;
    }
    if (error is KakaoClientException) {
      return error.reason == ClientErrorCause.cancelled;
    }
    return false;
  }

  /// Google 로그인 UI를 띄우고 Firebase 자격 증명을 만든다.
  static Future<AuthCredential> _obtainGoogleCredential() async {
    debugPrint('구글: 로그인 시작');
    await _ensureGoogleInitialized();
    final googleUser = await GoogleSignIn.instance.authenticate();
    debugPrint('구글: 계정 선택 완료 (${googleUser.email})');
    final idToken = googleUser.authentication.idToken;
    if (idToken == null) {
      throw StateError('Google 로그인에서 ID 토큰을 받지 못했습니다.');
    }
    return GoogleAuthProvider.credential(idToken: idToken);
  }

  /// Google 로그인.
  static Future<UserCredential> signInWithGoogle() async {
    final credential = await _obtainGoogleCredential();
    debugPrint('구글: Firebase credential 로그인');
    final result = await _auth.signInWithCredential(credential);
    debugPrint('구글: 로그인 성공 (uid: ${result.user?.uid})');
    return result;
  }

  /// 게스트 계정을 Google 계정에 연결한다(uid 유지 → 기록 보존).
  /// 이미 그 Google 계정으로 가입한 이력이 있으면
  /// [GuestUpgradeConflictException]을 던진다.
  static Future<UserCredential> linkGuestWithGoogle() async {
    final credential = await _obtainGoogleCredential();
    debugPrint('구글: 게스트 계정 연결');
    return _linkCurrentUser(credential);
  }

  /// 현재(게스트) 사용자에 [credential]을 연결한다. 세션이 없으면 그냥 로그인한다.
  static Future<UserCredential> _linkCurrentUser(
    AuthCredential credential,
  ) async {
    final user = _auth.currentUser;
    if (user == null) return _auth.signInWithCredential(credential);
    try {
      final result = await user.linkWithCredential(credential);
      debugPrint('게스트 연결 성공 (uid 유지: ${result.user?.uid})');
      return result;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'credential-already-in-use' ||
          e.code == 'email-already-in-use') {
        debugPrint('게스트 연결 충돌: ${e.code}');
        throw GuestUpgradeConflictException(e.credential ?? credential);
      }
      rethrow;
    }
  }

  /// 게스트 연결 충돌 시, 기존 계정으로 로그인한다.
  /// (게스트 기록은 새 계정으로 이어지지 않는다.)
  static Future<UserCredential> signInWithExistingCredential(
    AuthCredential credential,
  ) => _auth.signInWithCredential(credential);

  /// Apple 로그인 (iOS 필수 — 다른 소셜 로그인을 제공하면 애플 심사 정책상 필수)
  static Future<UserCredential> signInWithApple() async {
    final appleCredential = await _getAppleIDCredential();
    final oauthCredential = _appleOAuthCredential(appleCredential);
    final result = await _auth.signInWithCredential(oauthCredential);
    await _finishAppleAuth(result, appleCredential);
    return result;
  }

  /// 게스트 계정을 Apple 계정에 연결한다(uid 유지 → 기록 보존).
  /// 이미 그 Apple 계정으로 가입한 이력이 있으면
  /// [GuestUpgradeConflictException]을 던진다.
  static Future<UserCredential> linkGuestWithApple() async {
    final appleCredential = await _getAppleIDCredential();
    final oauthCredential = _appleOAuthCredential(appleCredential);
    debugPrint('애플: 게스트 계정 연결');
    final result = await _linkCurrentUser(oauthCredential);
    await _finishAppleAuth(result, appleCredential);
    return result;
  }

  static Future<AuthorizationCredentialAppleID> _getAppleIDCredential() =>
      SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

  static OAuthCredential _appleOAuthCredential(
    AuthorizationCredentialAppleID appleCredential,
  ) => OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );

  /// Apple 로그인/연결 성공 후 공통 마무리:
  /// 이름 시딩(최초 인증 시에만 내려옴) + 탈퇴용 refresh token 등록.
  static Future<void> _finishAppleAuth(
    UserCredential result,
    AuthorizationCredentialAppleID appleCredential,
  ) async {
    // Apple은 최초 인증 시에만 이름을 내려준다(재로그인부터는 안 옴).
    // 여기서 놓치면 다시는 못 받으므로 Auth 프로필과 Firestore 닉네임에 바로 채워둔다.
    final fullName =
        '${appleCredential.familyName?.trim() ?? ''}${appleCredential.givenName?.trim() ?? ''}'
            .trim();
    final user = result.user;
    if (fullName.isNotEmpty && user != null) {
      if ((user.displayName ?? '').trim().isEmpty) {
        await user.updateDisplayName(fullName);
      }
      await FirestoreService.seedNicknameIfMissing(user.uid, fullName);
    }

    // 탈퇴 시 Apple 토큰을 revoke할 수 있도록 refresh_token을 서버에 등록해둔다.
    // (Apple 심사 정책상 필수. 실패해도 로그인 자체는 막지 않는다.)
    await _registerAppleRefreshToken(appleCredential.authorizationCode);
  }

  static Future<void> _registerAppleRefreshToken(
    String authorizationCode,
  ) async {
    try {
      final callable = FirebaseFunctions.instanceFor(
        region: 'asia-northeast3',
      ).httpsCallable('registerAppleRefreshToken');
      await callable.call({'authorizationCode': authorizationCode});
    } catch (e) {
      debugPrint('Apple refresh token 등록 실패: $e');
    }
  }

  /// Kakao 로그인
  static Future<UserCredential> signInWithKakao() async {
    OAuthToken token;
    try {
      debugPrint('카카오: 카카오톡 로그인 시작');
      token = await UserApi.instance.loginWithKakaoTalk();
      debugPrint('카카오: 카카오톡 로그인 성공');
    } catch (error) {
      // 사용자가 취소한 경우 계정 로그인으로 넘기지 않는다.
      if (isCanceled(error)) {
        debugPrint('카카오: 사용자가 취소함');
        rethrow;
      }
      debugPrint('카카오톡 앱 로그인 실패, 카카오계정 로그인으로 대체: $error');
      token = await UserApi.instance.loginWithKakaoAccount();
      debugPrint('카카오: 카카오계정 로그인 성공');
    }

    debugPrint('카카오: Cloud Function kakaoSignIn 호출');
    final callable = FirebaseFunctions.instanceFor(
      region: 'asia-northeast3',
    ).httpsCallable('kakaoSignIn');
    final result = await callable.call({'accessToken': token.accessToken});
    final customToken = result.data['customToken'] as String?;
    if (customToken == null) {
      throw StateError('카카오 로그인 커스텀 토큰 발급에 실패했습니다.');
    }
    debugPrint('카카오: Firebase 커스텀 토큰 로그인');
    return _auth.signInWithCustomToken(customToken);
  }

  // 로그아웃
  static Future<void> signOut() async {
    final uid = _auth.currentUser?.uid;
    final providerIds =
        _auth.currentUser?.providerData.map((p) => p.providerId).toList() ??
        const [];
    debugPrint('로그아웃 시작 (uid: ${uid ?? '없음'}, providers: $providerIds)');
    // Auth가 끊기기 전에 Firestore 리스너를 먼저 해제한다.
    // (안 그러면 snapshots가 permission-denied를 낸다.)
    // SubscriptionService.stop(); // 결제 비활성화
    await FirestoreService.dispose();
    await _auth.signOut();
    await _clearProviderSessions(providerIds);
    debugPrint('로그아웃 완료');
  }

  /// 회원 탈퇴. Cloud Function이 Firestore 데이터 + Auth 사용자를 삭제한다.
  /// 이후 로컬 리스너·소셜 세션을 정리한다.
  static Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('로그인된 사용자가 없습니다.');
    }
    final uid = user.uid;
    final providerIds =
        user.providerData.map((p) => p.providerId).toList(growable: false);
    final isKakao = uid.startsWith('kakao:');
    debugPrint('회원 탈퇴 시작 (uid: $uid, providers: $providerIds)');

    // Auth/문서가 사라지기 전에 리스너를 끊는다.
    // SubscriptionService.stop(); // 결제 비활성화
    await FirestoreService.dispose();

    final callable = FirebaseFunctions.instanceFor(
      region: 'asia-northeast3',
    ).httpsCallable('deleteAccount');
    await callable.call();

    // Admin이 Auth 유저를 지운 뒤 로컬 세션·소셜 연결을 정리한다.
    try {
      await _auth.signOut();
    } catch (_) {
      // 이미 삭제된 계정이면 signOut이 실패할 수 있음
    }
    await _clearProviderSessions(providerIds, unlinkKakao: isKakao);
    debugPrint('회원 탈퇴 완료');
  }

  static Future<void> _clearProviderSessions(
    List<String> providerIds, {
    bool unlinkKakao = false,
  }) async {
    if (providerIds.contains('google.com')) {
      try {
        await _ensureGoogleInitialized();
        await GoogleSignIn.instance.signOut();
      } catch (_) {
        // Google 세션 해제 실패는 무시
      }
    }
    try {
      if (unlinkKakao) {
        await UserApi.instance.unlink();
      } else {
        await UserApi.instance.logout();
      }
    } catch (_) {
      // 카카오 미사용·세션 없음은 무시
    }
  }
}
