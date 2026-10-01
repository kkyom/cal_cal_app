import 'dart:async';

import 'package:flutter/material.dart';

import 'auth_service.dart';
import 'legal_links.dart';

const Color _primaryColor = Color(0xFF3F5F8B);

/// 앱 최초 진입 화면. Google / Apple / Kakao 로그인 중 하나로 시작한다.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _handle(Future<void> Function() signIn) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // 카카오톡처럼 앱 밖으로 나갔다 돌아오는 흐름을 끊지 않는다.
      // 취소 후 Future가 안 끝나는 경우에만 타임아웃으로 스피너를 해제한다.
      await signIn().timeout(const Duration(seconds: 90));
      // 성공 시 AuthGate가 authStateChanges를 통해 자동으로 다음 화면으로 전환한다.
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _error = '로그인 시간이 초과되었습니다. 다시 시도해 주세요.');
      debugPrint('로그인 타임아웃');
    } catch (e) {
      if (!mounted) return;
      if (!AuthService.isCanceled(e)) {
        setState(() => _error = '로그인에 실패했습니다. 다시 시도해 주세요.');
        debugPrint('로그인 실패: $e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openLegal(Future<bool> Function() open) async {
    final ok = await open();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('문서를 열 수 없어요. 잠시 후 다시 시도해 주세요.')),
      );
    }
  }

  /// 로그인 직전에 이용약관·개인정보 처리방침 동의를 명시적으로 받는다.
  /// "동의하고 계속하기"를 눌러야만 true를 반환하고, 취소/바깥 탭은 false.
  Future<bool> _showConsentDialog() async {
    final agreed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('서비스 이용 동의'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '칼캘을 이용하려면 아래 약관 및 방침에 동의해야 해요.',
                style: TextStyle(fontSize: 14, color: Colors.black87),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => _openLegal(LegalLinks.openTermsOfService),
                child: const Text(
                  '이용약관 보기',
                  style: TextStyle(
                    fontSize: 14,
                    color: _primaryColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => _openLegal(LegalLinks.openPrivacyPolicy),
                child: const Text(
                  '개인정보 처리방침 보기',
                  style: TextStyle(
                    fontSize: 14,
                    color: _primaryColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('동의하고 계속하기'),
            ),
          ],
        );
      },
    );
    return agreed ?? false;
  }

  Future<void> _handleWithConsent(Future<void> Function() signIn) async {
    if (_loading) return;
    final agreed = await _showConsentDialog();
    if (!agreed || !mounted) return;
    await _handle(signIn);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(
                          Icons.local_fire_department_rounded,
                          size: 64,
                          color: _primaryColor,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          '칼캘\n칼로리 캘린더',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '로그인하고 여러 기기에서\n식단 기록을 동기화하세요',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: Colors.black54),
                        ),
                        const SizedBox(height: 40),
                        if (_error != null) ...[
                          Text(
                            _error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        _LoginButton(
                          label: 'Google로 시작하기',
                          icon: Icons.g_mobiledata_rounded,
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black87,
                          borderColor: const Color(0xFFDDDDDD),
                          loading: _loading,
                          onPressed: () =>
                              _handleWithConsent(AuthService.signInWithGoogle),
                        ),
                        const SizedBox(height: 12),
                        _LoginButton(
                          label: 'Apple로 시작하기',
                          icon: Icons.apple,
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          loading: _loading,
                          onPressed: () =>
                              _handleWithConsent(AuthService.signInWithApple),
                        ),
                        const SizedBox(height: 12),
                        _LoginButton(
                          label: '카카오로 시작하기',
                          icon: Icons.chat_bubble_rounded,
                          backgroundColor: const Color(0xFFFEE500),
                          foregroundColor: Colors.black87,
                          loading: _loading,
                          onPressed: () =>
                              _handleWithConsent(AuthService.signInWithKakao),
                        ),
                        const SizedBox(height: 20),
                        TextButton(
                          onPressed: _loading
                              ? null
                              : () => _handleWithConsent(
                                  () => AuthService.signInAsGuest(),
                                ),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.black54,
                          ),
                          child: const Text(
                            '로그인 없이 시작하기',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Text(
                          '나중에 Google · Apple 로그인으로\n기록을 백업할 수 있어요',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Colors.black38),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16, top: 12),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        const Text(
                          '로그인 전 ',
                          style: TextStyle(fontSize: 12, color: Colors.black45),
                        ),
                        GestureDetector(
                          onTap: () =>
                              _openLegal(LegalLinks.openTermsOfService),
                          child: const Text(
                            '이용약관',
                            style: TextStyle(
                              fontSize: 12,
                              color: _primaryColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Text(
                          ' 및 ',
                          style: TextStyle(fontSize: 12, color: Colors.black45),
                        ),
                        GestureDetector(
                          onTap: () =>
                              _openLegal(LegalLinks.openPrivacyPolicy),
                          child: const Text(
                            '개인정보 처리방침',
                            style: TextStyle(
                              fontSize: 12,
                              color: _primaryColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Text(
                          '을 미리 확인할 수 있어요.',
                          style: TextStyle(fontSize: 12, color: Colors.black45),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color? borderColor;
  final bool loading;
  final VoidCallback onPressed;

  const _LoginButton({
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
    this.borderColor,
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          elevation: 0,
          disabledBackgroundColor: backgroundColor.withValues(alpha: 0.6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
            side: borderColor != null
                ? BorderSide(color: borderColor!)
                : BorderSide.none,
          ),
        ),
        child: loading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(foregroundColor),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 22),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
