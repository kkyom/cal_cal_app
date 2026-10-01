import 'dart:async';

import 'package:flutter/material.dart';

// import 'ad_banner_widget.dart'; // 광고 비활성화
import 'app_info_screen.dart';
import 'auth_service.dart';
import 'firestore_service.dart';
import 'goal_edit_screen.dart';
import 'help_tutorial_screen.dart';
import 'legal_policy_screen.dart';
import 'notification_settings_screen.dart';
import 'responsive_content.dart';
import 'support_screen.dart';

const Color _bgColor = Color(0xFFF2F2F2);
const Color _primaryColor = Color(0xFF3F5F8B);
const Color _mutedTextColor = Color(0xFFB0B0B0);
const Color _fieldBgColor = Color(0xFFEDEDED);

/// 대시보드에서 진입하는 설정 화면. 로그아웃 / 회원 탈퇴를 제공한다.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _busy = false;

  bool get _isGuest => AuthService.isGuest;

  String get _nickname {
    final name = FirestoreService.loadNickname();
    if (name != null && name.isNotEmpty) return name;
    if (_isGuest) return '게스트';
    return '닉네임 없음';
  }

  String get _email {
    if (_isGuest) return '로그인하고 기록을 백업하세요';
    final user = AuthService.currentUser;
    if (user == null) return '이메일 없음';
    var email = user.email?.trim();
    if (email == null || email.isEmpty) {
      for (final p in user.providerData) {
        final providerEmail = p.email?.trim();
        if (providerEmail != null && providerEmail.isNotEmpty) {
          email = providerEmail;
          break;
        }
      }
    }
    if (email == null || email.isEmpty) return '이메일 없음';
    // Apple이 발급하는 임의 문자열 릴레이 주소(예: c6t2kwm2jc@privaterelay.appleid.com)는
    // 사용자에게 의미가 없으니 원문 대신 안내 문구로 보여준다.
    if (email.toLowerCase().endsWith('@privaterelay.appleid.com')) {
      return 'Apple 비공개 이메일 사용 중';
    }
    return email;
  }

  String? get _authProvider => FirestoreService.resolveAuthProvider();

  /// 닉네임 수정 다이얼로그: 확인 시 중복확인 후 Auth displayName + Firestore
  /// nickname을 원자적으로 갱신한다(Cloud Function `updateNickname`).
  Future<void> _editNickname() async {
    if (_busy) return;
    final current = FirestoreService.loadNickname() ?? '';
    final saved = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _NicknameEditDialog(initialNickname: current),
    );
    if (saved == null || !mounted) return;
    if (saved.isEmpty || saved == current) return;

    setState(() => _busy = true);
    try {
      await FirestoreService.updateNickname(saved);
      if (mounted) setState(() {});
    } on NicknameTakenException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이미 사용 중인 닉네임이에요.')),
      );
    } catch (e) {
      debugPrint('닉네임 수정 실패: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('닉네임 수정에 실패했어요. 잠시 후 다시 시도해 주세요.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 로그아웃 확인 다이얼로그: 확인 시 세션을 종료하고 루트 화면으로 돌아간다.
  Future<void> _confirmSignOut() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('로그아웃'),
        content: const Text('로그아웃 하시겠어요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('로그아웃'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AuthService.signOut();
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  /// 게스트 → 소셜 전환 진입점. 어떤 제공자로 로그인할지 고른다.
  Future<void> _startGuestUpgrade() async {
    if (_busy) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => const _GuestUpgradeSheet(),
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'google':
        await _upgradeGuest(AuthService.linkGuestWithGoogle);
      case 'apple':
        await _upgradeGuest(AuthService.linkGuestWithApple);
      case 'kakao':
        await _upgradeGuestWithKakao();
    }
  }

  /// Google/Apple 연결 실행. 성공 시 uid가 유지되어 기존 기록이 그대로 남는다.
  Future<void> _upgradeGuest(
    Future<Object?> Function() link, {
    String successMessage = '로그인되었어요. 이제 기록이 백업됩니다.',
  }) async {
    setState(() => _busy = true);
    try {
      await link();
      final uid = AuthService.currentUser?.uid;
      if (uid != null) await FirestoreService.init(uid);
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage)),
      );
    } on GuestUpgradeConflictException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      await _resolveUpgradeConflict(e);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (AuthService.isCanceled(e)) return;
      debugPrint('게스트 전환 실패: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인에 실패했어요. 잠시 후 다시 시도해 주세요.')),
      );
    }
  }

  /// 연결하려는 소셜 계정으로 이미 가입한 이력이 있는 경우.
  /// 기존 계정으로 로그인할지 물어본다(게스트 기록은 이어지지 않음).
  Future<void> _resolveUpgradeConflict(
    GuestUpgradeConflictException e,
  ) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('이미 가입된 계정이에요'),
        content: const Text(
          '이 계정으로 예전에 가입한 이력이 있어요.\n'
          '기존 계정으로 로그인하면 지금 게스트로 쌓은 기록은 옮겨지지 않아요.\n\n'
          '기존 계정으로 로그인할까요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('기존 계정으로 로그인'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await AuthService.signInWithExistingCredential(e.credential);
      // authStateChanges(uid 변경)로 AuthGate가 다시 분기한다.
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (err) {
      debugPrint('기존 계정 로그인 실패: $err');
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인에 실패했어요. 잠시 후 다시 시도해 주세요.')),
      );
    }
  }

  /// 카카오는 커스텀 토큰 방식이라 게스트 계정 연결이 불가능하다.
  /// 새 계정으로 시작되며 게스트 기록이 이어지지 않음을 알리고 진행 여부를 묻는다.
  Future<void> _upgradeGuestWithKakao() async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('카카오 로그인 안내'),
        content: const Text(
          '카카오 로그인은 게스트 기록 이전을 지원하지 않아요.\n\n'
          'Google 또는 Apple로 로그인하면 지금까지의 기록이 그대로 유지됩니다.\n'
          '카카오로 계속하면 새 계정으로 시작되고 게스트 기록은 옮겨지지 않아요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('카카오로 계속'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await AuthService.signInWithKakao();
      // 커스텀 토큰 로그인으로 세션이 교체되며 authStateChanges가 발생한다.
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (AuthService.isCanceled(e)) return;
      debugPrint('카카오 전환 실패: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그인에 실패했어요. 잠시 후 다시 시도해 주세요.')),
      );
    }
  }

  void _openLegalPolicy() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LegalPolicyScreen()),
    );
  }

  /// 목표 설정: 대시보드와 동일한 GoalEditScreen을 재사용해 탄단지 목표를 수정한다.
  Future<void> _openGoalEdit() async {
    if (_busy) return;
    final result = await Navigator.of(context).push<GoalData>(
      MaterialPageRoute(
        builder: (_) => GoalEditScreen(
          initial: GoalData(
            carb: FirestoreService.loadCarbGoal(),
            protein: FirestoreService.loadProteinGoal(),
            fat: FirestoreService.loadFatGoal(),
          ),
        ),
      ),
    );
    if (result == null) return;
    FirestoreService.saveGoals(
      carb: result.carb,
      protein: result.protein,
      fat: result.fat,
      source: GoalsSource.manual,
    );
  }

  void _openNotificationSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NotificationSettingsScreen()),
    );
  }

  void _openAppInfo() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AppInfoScreen()),
    );
  }

  void _openSupport() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SupportScreen()),
    );
  }

  void _openHelpTutorial() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Center(
        child: HelpTutorialScreen(onFinish: () => Navigator.of(ctx).pop()),
      ),
    );
  }

  /// 회원 탈퇴 확인 다이얼로그: 확인 시 계정·데이터를 삭제한다.
  Future<void> _confirmDeleteAccount() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_isGuest ? '기록 삭제' : '회원 탈퇴'),
        content: Text(
          _isGuest
              ? '지금까지의 식단·목표 기록이 모두 삭제되며 되돌릴 수 없어요.\n정말 삭제하시겠어요?'
              : '탈퇴하면 계정과 식단·목표 데이터가 모두 삭제되며 되돌릴 수 없어요.\n정말 탈퇴하시겠어요?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: Text(_isGuest ? '삭제' : '탈퇴'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;

    setState(() => _busy = true);
    try {
      await AuthService.deleteAccount();
      if (!mounted) return;
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      debugPrint('회원 탈퇴 실패: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('회원 탈퇴에 실패했어요. 잠시 후 다시 시도해 주세요.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 설정 메뉴, 탈퇴 중 로딩 오버레이
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: _bgColor,
          appBar: AppBar(
            backgroundColor: _bgColor,
            elevation: 0,
            foregroundColor: Colors.black87,
            title: const Text(
              '설정',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
            ),
          ),
          // 광고 비활성화로 배너 바 임시 제거
          // bottomNavigationBar: SafeArea(
          //   top: false,
          //   child: Padding(
          //     padding: const EdgeInsets.symmetric(vertical: 8),
          //     child: SizedBox(
          //       height: 50,
          //       child: Center(child: AdBannerWidget(adUnitId: AdUnitIds.settings)),
          //     ),
          //   ),
          // ),
          body: ResponsiveContent(
            child: ListView(
              // 닉네임 · 연동 이메일 · 소셜 로그인 제공자 아이콘.
              children: [
                _ProfileHeader(
                  nickname: _nickname,
                  email: _email,
                  authProvider: _authProvider,
                  isGuest: _isGuest,
                  onEditNickname: (_busy || _isGuest) ? null : _editNickname,
                ),
                const Divider(height: 1),
                if (_isGuest) ...[
                  ListTile(
                    leading: const Icon(Icons.cloud_upload_outlined,
                        color: _primaryColor),
                    title: const Text(
                      '로그인하고 기록 백업하기',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: const Text(
                      'Google · Apple로 로그인하면 지금 기록이 유지돼요',
                      style: TextStyle(fontSize: 12),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _busy ? null : _startGuestUpgrade,
                  ),
                  const Divider(height: 1),
                ],
                ListTile(
                  leading: const Icon(
                    Icons.flag_outlined,
                    color: _primaryColor,
                  ),
                  title: const Text(
                    '목표 설정',
                    style: TextStyle(color: Colors.black),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy ? null : _openGoalEdit,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.notifications_outlined,
                    color: _primaryColor,
                  ),
                  title: const Text(
                    '알림 설정',
                    style: TextStyle(color: Colors.black),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy ? null : _openNotificationSettings,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.school_outlined,
                    color: _primaryColor,
                  ),
                  title: const Text(
                    '사용법 다시 보기',
                    style: TextStyle(color: Colors.black),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy ? null : _openHelpTutorial,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.help_outline,
                    color: _primaryColor,
                  ),
                  title: const Text(
                    '문의 및 피드백',
                    style: TextStyle(color: Colors.black),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy ? null : _openSupport,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.info_outline,
                    color: _primaryColor,
                  ),
                  title: const Text(
                    '앱 정보',
                    style: TextStyle(color: Colors.black),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy ? null : _openAppInfo,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    Icons.gavel_outlined,
                    color: _primaryColor,
                  ),
                  title: const Text(
                    '이용 약관 및 정책',
                    style: TextStyle(color: Colors.black),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _busy ? null : _openLegalPolicy,
                ),
                const Divider(height: 1),
                if (!_isGuest) ...[
                  ListTile(
                    leading: const Icon(Icons.logout, color: _primaryColor),
                    title: const Text(
                      '로그아웃',
                      style: TextStyle(color: Colors.black),
                    ),
                    onTap: _busy ? null : _confirmSignOut,
                  ),
                  const Divider(height: 1),
                ],
                ListTile(
                  title: Text(
                    _isGuest ? '기록 삭제' : '회원 탈퇴',
                    style: const TextStyle(
                      color: _mutedTextColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  onTap: _busy ? null : _confirmDeleteAccount,
                ),
              ],
            ),
          ),
        ),
        if (_busy)
          const ModalBarrier(dismissible: false, color: Color(0x33000000)),
        if (_busy)
          const Center(
            child: CircularProgressIndicator(color: _primaryColor),
          ),
      ],
    );
  }
}

enum _NicknameCheckStatus { idle, checking, available, taken }

/// 닉네임 입력 다이얼로그. TextEditingController는 이 State에서 소유·해제하고,
/// 입력이 바뀔 때마다 디바운스 후 `nicknames/{normalized}` 인덱스를 읽어
/// 가벼운 실시간 중복 힌트를 보여준다. 최종 중복확인은 저장 시 Cloud Function이 한다.
class _NicknameEditDialog extends StatefulWidget {
  final String initialNickname;

  const _NicknameEditDialog({required this.initialNickname});

  @override
  State<_NicknameEditDialog> createState() => _NicknameEditDialogState();
}

class _NicknameEditDialogState extends State<_NicknameEditDialog> {
  late final TextEditingController _controller;
  Timer? _debounce;
  _NicknameCheckStatus _status = _NicknameCheckStatus.idle;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialNickname);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _controller.text.trim().isNotEmpty &&
      _status != _NicknameCheckStatus.checking &&
      _status != _NicknameCheckStatus.taken;

  void _onChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == widget.initialNickname.trim()) {
      setState(() => _status = _NicknameCheckStatus.idle);
      return;
    }
    setState(() => _status = _NicknameCheckStatus.checking);
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      bool available;
      try {
        available = await FirestoreService.isNicknameAvailable(trimmed);
      } catch (_) {
        // 힌트 조회 실패는 무시한다. 실제 저장 시 서버가 다시 확인한다.
        if (mounted && _controller.text.trim() == trimmed) {
          setState(() => _status = _NicknameCheckStatus.idle);
        }
        return;
      }
      if (!mounted || _controller.text.trim() != trimmed) return;
      setState(() {
        _status = available
            ? _NicknameCheckStatus.available
            : _NicknameCheckStatus.taken;
      });
    });
  }

  void _submit() {
    if (!_canSubmit) return;
    Navigator.pop(context, _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      contentPadding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
      actionsPadding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      title: const Text(
        '닉네임 수정',
        style: TextStyle(color: _primaryColor, fontWeight: FontWeight.bold),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: _fieldBgColor,
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.person_outline, color: Colors.black45),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    autofocus: true,
                    maxLength: 20,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      hintText: '닉네임을 입력하세요',
                      counterText: '',
                      border: InputBorder.none,
                    ),
                    onChanged: _onChanged,
                    onSubmitted: (_) => _submit(),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 28,
            child: Align(
              alignment: Alignment.centerLeft,
              child: _NicknameStatusLabel(status: _status),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF767474).withValues(alpha: 0.8),
            textStyle: const TextStyle(fontWeight: FontWeight.bold),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: _canSubmit ? _submit : null,
          style: TextButton.styleFrom(
            foregroundColor: _primaryColor.withValues(alpha: 0.8),
            disabledForegroundColor: Colors.black26,
            textStyle: const TextStyle(fontWeight: FontWeight.bold),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: const Text('저장'),
        ),
      ],
    );
  }
}

/// 닉네임 필드 아래 표시되는 실시간 중복확인 힌트.
class _NicknameStatusLabel extends StatelessWidget {
  final _NicknameCheckStatus status;

  const _NicknameStatusLabel({required this.status});

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case _NicknameCheckStatus.idle:
        return const SizedBox.shrink();
      case _NicknameCheckStatus.checking:
        return const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Row(
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.black38,
                ),
              ),
              SizedBox(width: 6),
              Text(
                '중복 확인 중...',
                style: TextStyle(fontSize: 12, color: Colors.black45),
              ),
            ],
          ),
        );
      case _NicknameCheckStatus.available:
        return const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Row(
            children: [
              Icon(Icons.check_circle, size: 14, color: Colors.green),
              SizedBox(width: 6),
              Text(
                '사용할 수 있는 닉네임이에요',
                style: TextStyle(fontSize: 12, color: Colors.green),
              ),
            ],
          ),
        );
      case _NicknameCheckStatus.taken:
        return const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Row(
            children: [
              Icon(Icons.cancel, size: 14, color: Colors.redAccent),
              SizedBox(width: 6),
              Text(
                '이미 사용 중인 닉네임이에요',
                style: TextStyle(fontSize: 12, color: Colors.redAccent),
              ),
            ],
          ),
        );
    }
  }
}

/// 설정 상단: 닉네임 · 연동 이메일 · 소셜 로그인 제공자 아이콘.
class _ProfileHeader extends StatelessWidget {
  final String nickname;
  final String email;
  final String? authProvider;
  final bool isGuest;
  final VoidCallback? onEditNickname;

  const _ProfileHeader({
    required this.nickname,
    required this.email,
    required this.authProvider,
    this.isGuest = false,
    this.onEditNickname,
  });

  @override
  Widget build(BuildContext context) {
    final initial = !isGuest && nickname.isNotEmpty && nickname != '닉네임 없음'
        ? nickname.substring(0, 1)
        : '?';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: _primaryColor.withValues(alpha: 0.12),
            foregroundColor: _primaryColor,
            child: Text(
              initial,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        nickname,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!isGuest)
                      IconButton(
                        onPressed: onEditNickname,
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        color: _primaryColor,
                        tooltip: '닉네임 수정',
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                      ),
                  ],
                ),
                Row(
                  children: [
                    _AuthProviderIcon(provider: authProvider),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        email,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black54,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// google / apple / kakao 브랜드 아이콘.
class _AuthProviderIcon extends StatelessWidget {
  final String? provider;

  const _AuthProviderIcon({required this.provider});

  @override
  Widget build(BuildContext context) {
    switch (provider) {
      case 'google':
        return const _ProviderBadge(
          backgroundColor: Colors.white,
          borderColor: Color(0xFFDDDDDD),
          child: Text(
            'G',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Color(0xFF4285F4),
              height: 1,
            ),
          ),
        );
      case 'apple':
        return const _ProviderBadge(
          backgroundColor: Colors.black,
          child: Icon(Icons.apple, size: 14, color: Colors.white),
        );
      case 'kakao':
        return const _ProviderBadge(
          backgroundColor: Color(0xFFFEE500),
          child: Icon(
            Icons.chat_bubble_rounded,
            size: 12,
            color: Colors.black87,
          ),
        );
      default:
        return const _ProviderBadge(
          backgroundColor: Color(0xFFE8E8E8),
          child: Icon(Icons.person_outline, size: 14, color: Colors.black45),
        );
    }
  }
}

class _ProviderBadge extends StatelessWidget {
  final Color backgroundColor;
  final Color? borderColor;
  final Widget child;

  const _ProviderBadge({
    required this.backgroundColor,
    required this.child,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
        border: borderColor != null
            ? Border.all(color: borderColor!, width: 1)
            : null,
      ),
      child: child,
    );
  }
}

/// 게스트 → 소셜 전환 시 제공자를 고르는 바텀시트.
/// 선택 결과를 `google` / `apple` / `kakao` 문자열로 pop 한다.
class _GuestUpgradeSheet extends StatelessWidget {
  const _GuestUpgradeSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFDDDDDD),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              '로그인하고 기록 백업하기',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Google · Apple로 로그인하면 지금까지 쌓은 기록이 그대로 유지돼요. '
              '카카오는 기록 이전이 지원되지 않아요.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 20),
            _UpgradeButton(
              label: 'Google로 로그인',
              icon: Icons.g_mobiledata_rounded,
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
              borderColor: const Color(0xFFDDDDDD),
              onPressed: () => Navigator.pop(context, 'google'),
            ),
            const SizedBox(height: 10),
            _UpgradeButton(
              label: 'Apple로 로그인',
              icon: Icons.apple,
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              onPressed: () => Navigator.pop(context, 'apple'),
            ),
            const SizedBox(height: 10),
            _UpgradeButton(
              label: '카카오로 로그인',
              icon: Icons.chat_bubble_rounded,
              backgroundColor: const Color(0xFFFEE500),
              foregroundColor: Colors.black87,
              onPressed: () => Navigator.pop(context, 'kakao'),
            ),
          ],
        ),
      ),
    );
  }
}

class _UpgradeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color? borderColor;
  final VoidCallback onPressed;

  const _UpgradeButton({
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onPressed,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
            side: borderColor != null
                ? BorderSide(color: borderColor!)
                : BorderSide.none,
          ),
        ),
        child: Row(
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
