// ---- 구독 화면 비활성화 (무료 출시, 추후 복구 시 이 블록 주석 해제) ----
// TODO: 결제 재도입 시 아래 주석 해제 + pubspec.yaml의 in_app_purchase 의존성 복구
// + 이 화면으로 이동하던 진입점(calorie_dashboard.dart의 Pro 배지, food_search_screen.dart의
//   무료 인식 소진 안내) 주석도 함께 복구할 것.
/*
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'center_toast.dart';
import 'firestore_service.dart';
import 'legal_links.dart';
import 'responsive_content.dart';
import 'subscription_service.dart';

const Color _bgColor = Color(0xFFD9D9DF);
const Color _primaryColor = Color(0xFF3F5F8B);
const Color _ctaColor = Color(0xFF3B82F6);

class _Feature {
  final IconData icon;
  final Color color;
  final String title;
  final String description;

  const _Feature({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
  });
}

const List<_Feature> _features = [
  _Feature(
    icon: Icons.block_outlined,
    color: Color(0xFF4B89DC),
    title: '광고 배너 제거',
    description: '광고 배너 없이 앱을 깔끔하게 이용할 수 있어요',
  ),
  _Feature(
    icon: Icons.camera_alt_outlined,
    color: Color(0xFFFFCE54),
    title: '이미지 기록 무제한',
    description: '횟수 제한 없는 이미지 기록으로 간편하게 기록하세요',
  ),
  _Feature(
    icon: Icons.bar_chart_rounded,
    color: Color(0xFF5FE0A6),
    title: '주간 / 월간 통계',
    description: '섭취 패턴을 주 단위, 월 단위로 한눈에 확인할 수 있어요',
  ),
  _Feature(
    icon: Icons.rocket_launch_outlined,
    color: Color(0xFFF6845C),
    title: '신규 기능 우선 이용',
    description: '앞으로 출시될 새로운 기능을 가장 먼저 만나보세요',
  ),
];

const List<String> _legalNotices = [
  '구독 결제는 구입을 확정하면 이용 중인 기기의 앱마켓(App Store 또는 Google Play) 계정으로 청구됩니다.',
  '구독 취소는 현재 이용 기간이 끝나기 24시간 전까지 가능합니다. 취소하지 않으면 이용 기간 종료 시 자동으로 갱신됩니다.',
  '구독 후에는 App Store 또는 Google Play의 구독 관리 메뉴에서 언제든 확인하고 해지할 수 있습니다.',
  '미성년자가 구독을 신청하는 경우, 법정대리인의 구독 및 결제 동의가 있었음을 전제로 합니다.',
];

Future<void> _openLegal(
  BuildContext context,
  Future<bool> Function() open,
) async {
  final ok = await open();
  if (!ok && context.mounted) {
    showCenterToast(context, '문서를 열 수 없어요. 잠시 후 다시 시도해 주세요.');
  }
}

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  ProductDetails? _product;
  bool _loadingProduct = true;
  bool _purchasing = false;
  bool _restoring = false;
  bool _isPro = FirestoreService.loadIsPro();
  StreamSubscription<void>? _changesSub;

  @override
  void initState() {
    super.initState();
    _loadProduct();
    _changesSub = FirestoreService.changes.listen((_) {
      if (!mounted) return;
      setState(() => _isPro = FirestoreService.loadIsPro());
    });
  }

  @override
  void dispose() {
    _changesSub?.cancel();
    super.dispose();
  }

  Future<void> _loadProduct() async {
    final product = await SubscriptionService.queryProMonthly();
    if (!mounted) return;
    setState(() {
      _product = product;
      _loadingProduct = false;
    });
  }

  Future<void> _handleSubscribe() async {
    final product = _product;
    if (product == null || _purchasing) return;
    setState(() => _purchasing = true);
    try {
      await SubscriptionService.buyProMonthly(product);
    } catch (e) {
      if (mounted) {
        showCenterToast(context, '결제를 시작할 수 없어요. 잠시 후 다시 시도해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  Future<void> _handleRestore() async {
    if (_restoring) return;
    setState(() => _restoring = true);
    try {
      await SubscriptionService.restorePurchases();
      if (mounted) showCenterToast(context, '구매 내역을 확인하고 있어요');
    } catch (e) {
      if (mounted) showCenterToast(context, '구매 복원에 실패했어요. 잠시 후 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text(
          '구독',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: ResponsiveContent(
            maxWidth: 420,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 28,
                    horizontal: 24,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF3F5F8B), Color(0xFF2C4870)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _primaryColor.withValues(alpha: 0.25),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.workspace_premium_rounded,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '칼캘: 칼로리 캘린더 Pro',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '광고 없이, 더 똑똑하게 기록하세요',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 22,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                const Text(
                  '구독하면 이런 기능들이 달라져요',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),

                const SizedBox(height: 12),

                for (final feature in _features) ...[
                  _FeatureCard(feature: feature),
                  const SizedBox(height: 10),
                ],

                const SizedBox(height: 12),

                ElevatedButton(
                  onPressed: _isPro || _purchasing || _product == null
                      ? null
                      : _handleSubscribe,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _ctaColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 2,
                  ),
                  child: _purchasing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          _isPro
                              ? '이미 구독 중이에요'
                              : _loadingProduct
                              ? '불러오는 중...'
                              : _product == null
                              ? '지금은 구독할 수 없어요'
                              : '구독하기 · ${_product!.price}/월',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),

                const SizedBox(height: 48),

                for (final notice in _legalNotices) ...[
                  _LegalBullet(text: notice),
                  const SizedBox(height: 8),
                ],

                const SizedBox(height: 8),

                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    GestureDetector(
                      onTap: _restoring ? null : _handleRestore,
                      child: Text(
                        _restoring ? '복원 중...' : '구매복원',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black45,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _openLegal(
                        context,
                        LegalLinks.openTermsOfService,
                      ),
                      child: const Text(
                        '이용약관',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.black45,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _openLegal(
                        context,
                        LegalLinks.openPrivacyPolicy,
                      ),
                      child: const Text(
                        '개인정보방침',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.black45,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final _Feature feature;

  const _FeatureCard({required this.feature});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: feature.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(feature.icon, color: feature.color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  feature.title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  feature.description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalBullet extends StatelessWidget {
  final String text;

  const _LegalBullet({required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 5),
          child: Icon(Icons.circle, size: 4, color: Colors.black38),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black45,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }
}
*/
