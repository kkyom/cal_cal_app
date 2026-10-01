import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
// import 'package:google_mobile_ads/google_mobile_ads.dart'; // 광고 비활성화
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' hide User;
import 'calorie_dashboard.dart';
import 'connectivity_gate.dart';
import 'firebase_options.dart';
import 'firestore_service.dart';
import 'help_tutorial_screen.dart';
import 'keyboard_dismiss.dart';
import 'login_screen.dart';
import 'notification_service.dart';
import 'onboarding_goal_calculator.dart';
import 'onboarding_screen.dart';
import 'push_notification_service.dart';
import 'reminder_permission_screen.dart';
// import 'subscription_service.dart'; // 결제 비활성화

/// Kakao Developers 콘솔에서 발급받은 Native App Key
const String _kakaoNativeAppKey = '17063e7f664a6383c35a1430254f91e2';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // 디버그 빌드는 debug provider(콘솔에 디버그 토큰 등록 필요)를 쓰고,
  // 릴리즈 빌드는 기기 증명(Play Integrity / App Attest)을 쓴다.
  await FirebaseAppCheck.instance.activate(
    providerAndroid: kDebugMode
        ? AndroidDebugProvider()
        : AndroidPlayIntegrityProvider(),
    providerApple:
        kDebugMode ? AppleDebugProvider() : AppleAppAttestProvider(),
  );
  KakaoSdk.init(nativeAppKey: _kakaoNativeAppKey);
  // await MobileAds.instance.initialize(); // 광고 비활성화
  await NotificationService.init();
  await PushNotificationService.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      builder: (context, child) => KeyboardDismissWrapper(child: child),
      locale: const Locale('ko'),
      supportedLocales: const [Locale('ko')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3F5F8B)),
      ),
      home: const ConnectivityGate(child: AuthGate()),
    );
  }
}

/// 로그인 상태에 따라 로그인 화면 / 온보딩 / 대시보드로 분기하는 앱 최상위 게이트.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScreen();
        }
        final user = snapshot.data;
        if (user == null) {
          return const LoginScreen();
        }
        return _SignedInGate(uid: user.uid);
      },
    );
  }
}

/// 로그인된 사용자의 Firestore 데이터를 초기화한 뒤 온보딩/대시보드로 분기.
class _SignedInGate extends StatefulWidget {
  final String uid;

  const _SignedInGate({required this.uid});

  @override
  State<_SignedInGate> createState() => _SignedInGateState();
}

class _SignedInGateState extends State<_SignedInGate> {
  late Future<void> _initFuture;
  bool _onboardingCompleted = false;
  bool _helpTutorialSeen = false;
  bool _reminderPromptSeen = false;

  Future<void> _bootstrap(String uid) async {
    // init() 이 실패한 채로 넘어가면 _onboardingCompleted 가 false 로 남아
    // 이미 온보딩을 마친 사용자가 온보딩 화면으로 되돌아간다. 콜드 스타트
    // 직후 App Check 토큰이 준비되기 전이면 첫 시도가 실패할 수 있으므로
    // 짧게 재시도하고, 끝내 실패하면 예외를 던져(build 에서 재시도 화면) 온보딩으로
    // 흘러가지 않게 한다.
    Object? lastErr;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        await FirestoreService.init(uid);
        lastErr = null;
        break;
      } catch (e) {
        lastErr = e;
        debugPrint('부트스트랩: Firestore init 실패 ($attempt/3): $e');
        await Future<void>.delayed(Duration(milliseconds: 500 * attempt));
      }
    }
    if (lastErr != null) throw lastErr;

    // SubscriptionService.start(); // 결제 비활성화
    _onboardingCompleted = FirestoreService.loadOnboardingCompleted();
    _helpTutorialSeen = FirestoreService.loadHelpTutorialSeen();
    _reminderPromptSeen = FirestoreService.loadReminderPromptSeen();

    // 알림 재등록은 실패해도 앱 진입을 막지 않는다.
    try {
      // 하루 기록 리마인더가 켜져 있으면, 재설치 등으로 토큰이 비어 있을 수 있으니
      // 이 기기의 FCM 토큰을 다시 등록해둔다(서버가 그날 기록 여부를 판단해 발송).
      if (FirestoreService.loadDailyReminderEnabled()) {
        await PushNotificationService.requestPermissionAndRegister();
      }
      // 습관 알림은 기기 로컬 예약이라, 재설치 등으로 비어 있을 수 있는 경우를
      // 대비해 저장된 값 기준으로 실제 예약 상태를 다시 맞춘다.
      final habitReminders = FirestoreService.loadHabitReminders();
      if (habitReminders.isNotEmpty) {
        await NotificationService.syncHabitReminders(habitReminders);
      }
    } catch (e) {
      debugPrint('부트스트랩: 알림 재등록 실패(무시): $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _initFuture = _bootstrap(widget.uid);
  }

  @override
  void didUpdateWidget(covariant _SignedInGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) {
      _onboardingCompleted = false;
      _helpTutorialSeen = false;
      _reminderPromptSeen = false;
      _initFuture = _bootstrap(widget.uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _LoadingScreen();
        }
        // 초기화가 끝내 실패했으면 온보딩으로 흘려보내지 말고 재시도 화면을 띄운다.
        if (snapshot.hasError) {
          return _BootstrapErrorScreen(
            onRetry: () => setState(() {
              _initFuture = _bootstrap(widget.uid);
            }),
          );
        }
        // AuthGate를 Navigator 스택에서 제거하지 않는다.
        // (제거하면 로그아웃 시 로그인 화면으로 전환되지 않는다.)
        if (_onboardingCompleted) {
          // 도움말 튜토리얼은 화면 전체를 덮지 않고, 아래 화면(대시보드/리마인더
          // 동의 화면) 위에 떠 있는 창(다이얼로그)으로 보여준다.
          final Widget base = (_helpTutorialSeen && !_reminderPromptSeen)
              ? ReminderPermissionScreen(
                  onDone: () {
                    // 대시보드로 먼저 넘기고, 완료 플래그 저장은 best-effort로 처리한다.
                    if (mounted) setState(() => _reminderPromptSeen = true);
                    FirestoreService.markReminderPromptSeen().catchError((
                      Object e,
                    ) {
                      debugPrint('리마인더 동의 화면 완료 저장 실패(무시): $e');
                    });
                  },
                )
              : const CalorieDashboardPage();
          return Stack(
            children: [
              base,
              if (!_helpTutorialSeen)
                HelpTutorialOverlay(
                  onFinish: () {
                    // 먼저 다음 화면으로 넘기고, 완료 플래그 저장은 best-effort로
                    // 처리한다. (저장이 실패해도 튜토리얼에 갇히지 않게 한다.
                    // 최악의 경우 다음 콜드 스타트에서 한 번 더 보일 뿐이다.)
                    if (mounted) setState(() => _helpTutorialSeen = true);
                    FirestoreService.markHelpTutorialSeen().catchError((
                      Object e,
                    ) {
                      debugPrint('도움말 튜토리얼 완료 저장 실패(무시): $e');
                    });
                  },
                ),
            ],
          );
        }
        return OnboardingScreen(
          onFinished: (result) async {
            final goal = calculateGoalsFromOnboarding(result);
            // 프로필·목표·목표일·완료 플래그를 한 번의 쓰기로 저장하고 서버
            // 반영까지 기다린다. 실패하면 예외가 OnboardingScreen 으로
            // 전파돼 재시도 안내가 뜨고, 온보딩 화면에 머문다.
            await FirestoreService.completeOnboarding(
              profile: result,
              carbGoal: goal.carb,
              proteinGoal: goal.protein,
              fatGoal: goal.fat,
              goalDate: result.goalDate,
            );
            if (!mounted) return;
            setState(() => _onboardingCompleted = true);
          },
        );
      },
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFF2F2F2),
      body: Center(child: CircularProgressIndicator(color: Color(0xFF3F5F8B))),
    );
  }
}

/// 로그인은 됐지만 사용자 데이터 초기화에 실패했을 때. 온보딩으로 되돌리지
/// 않고 재시도만 제공한다(네트워크·App Check 일시 오류가 대부분).
class _BootstrapErrorScreen extends StatelessWidget {
  const _BootstrapErrorScreen({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '내 정보를 불러오지 못했어요.\n네트워크 상태를 확인하고 다시 시도해 주세요.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, height: 1.5, color: Colors.black54),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: onRetry,
                child: const Text('다시 시도'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
