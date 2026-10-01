import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:keyboard_actions/keyboard_actions.dart';

// import 'ad_banner_widget.dart'; // 광고 비활성화
import 'keyboard_actions_config.dart';
import 'onboarding_goal_calculator.dart';
import 'onboarding_screen.dart';
import 'firestore_service.dart';

// --- 목표 데이터 모델 ---
class GoalData {
  final double carb;
  final double protein;
  final double fat;

  const GoalData({
    required this.carb,
    required this.protein,
    required this.fat,
  });

  int get totalKcal => (carb * 4 + protein * 4 + fat * 9).round();
}

// --- 목표 수정 화면 ---
class GoalEditScreen extends StatefulWidget {
  final GoalData initial;

  const GoalEditScreen({super.key, required this.initial});

  @override
  State<GoalEditScreen> createState() => _GoalEditScreenState();
}

class _GoalEditScreenState extends State<GoalEditScreen> {
  late final TextEditingController _carbCtrl;
  late final TextEditingController _proteinCtrl;
  late final TextEditingController _fatCtrl;

  final FocusNode _carbFocus = FocusNode();
  final FocusNode _proteinFocus = FocusNode();
  final FocusNode _fatFocus = FocusNode();

  double _carb = 0;
  double _protein = 0;
  double _fat = 0;

  @override
  void initState() {
    super.initState();
    _carb = widget.initial.carb;
    _protein = widget.initial.protein;
    _fat = widget.initial.fat;
    _carbCtrl = TextEditingController(text: _carb.toStringAsFixed(0));
    _proteinCtrl = TextEditingController(text: _protein.toStringAsFixed(0));
    _fatCtrl = TextEditingController(text: _fat.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _carbCtrl.dispose();
    _proteinCtrl.dispose();
    _fatCtrl.dispose();
    _carbFocus.dispose();
    _proteinFocus.dispose();
    _fatFocus.dispose();
    super.dispose();
  }

  int get _totalKcal => (_carb * 4 + _protein * 4 + _fat * 9).round();

  void _onChanged() {
    setState(() {
      _carb = double.tryParse(_carbCtrl.text) ?? 0;
      _protein = double.tryParse(_proteinCtrl.text) ?? 0;
      _fat = double.tryParse(_fatCtrl.text) ?? 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardActions(
      disableScroll: true,
      config: buildKeyboardActionsConfig([
        _carbFocus,
        _proteinFocus,
        _fatFocus,
      ]),
      child: Scaffold(
        backgroundColor: const Color(0xFFF2F2F2),
        appBar: AppBar(
          title: const Text(
            '목표 수정',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          backgroundColor: const Color(0xFF3F5F8B),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        // 광고 비활성화로 배너 바 임시 제거
        // bottomNavigationBar: SafeArea(
        //   top: false,
        //   child: Padding(
        //     padding: const EdgeInsets.symmetric(vertical: 8),
        //     child: SizedBox(
        //       height: 50,
        //       child: Center(child: AdBannerWidget(adUnitId: AdUnitIds.goalEdit)),
        //     ),
        //   ),
        // ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 24,
                  horizontal: 20,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF3F5F8B),
                  borderRadius: BorderRadius.circular(20),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0x33FFFFFF), Color(0x26000000)],
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 16,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const Text(
                      '총 목표 칼로리',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$_totalKcal kcal',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    // const SizedBox(height: 6),
                    // const Text(
                    //   '탄수화물(g) x 4 + 단백질(g) x 4 + 지방(g) x 9',
                    //   style: TextStyle(color: Colors.white, fontSize: 13),
                    // ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              _MacroField(
                label: '탄수화물',
                kcalPerGram: 4,
                controller: _carbCtrl,
                focusNode: _carbFocus,
                onChanged: (_) => _onChanged(),
                color: const Color(0xFFFFCE54),
              ),
              const SizedBox(height: 12),
              _MacroField(
                label: '단백질',
                kcalPerGram: 4,
                controller: _proteinCtrl,
                focusNode: _proteinFocus,
                onChanged: (_) => _onChanged(),
                color: const Color(0xFFF6D55C),
              ),
              const SizedBox(height: 12),
              _MacroField(
                label: '지방',
                kcalPerGram: 9,
                controller: _fatCtrl,
                focusNode: _fatFocus,
                onChanged: (_) => _onChanged(),
                color: const Color(0xFF4B89DC),
              ),

              const SizedBox(height: 32),

              ElevatedButton(
                onPressed: () {
                  Navigator.pop(
                    context,
                    GoalData(carb: _carb, protein: _protein, fat: _fat),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3F5F8B),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 2,
                ),
                child: const Text(
                  '저장',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),

              const SizedBox(height: 12),

              OutlinedButton(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    barrierDismissible: false,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      title: const Text(
                        '목표 재설정',
                        style: TextStyle(
                          color: Color(0xFF3F5F8B),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      content: const Text(
                        '목표 설정을 처음부터 다시 해볼까요?',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(
                              0xFF767474,
                            ).withValues(alpha: 0.8),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text('아니오'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(
                              0xFF3F5F8B,
                            ).withValues(alpha: 0.8),
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text('예'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed != true) return;
                  if (!context.mounted) return;

                  // GoalEdit만 온보딩으로 교체한다. AuthGate(루트)는 유지해야
                  // 이후 로그아웃 시 로그인 화면으로 돌아갈 수 있다.
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (onboardingContext) => OnboardingScreen(
                        onFinished: (result) async {
                          final goal = calculateGoalsFromOnboarding(result);
                          // 프로필·목표(자동 계산)·목표일·완료 플래그를 한 번의
                          // 쓰기로 저장하고 서버 반영까지 기다린다. 실패하면
                          // 예외가 OnboardingScreen 으로 전파돼 재시도 안내가 뜬다.
                          await FirestoreService.completeOnboarding(
                            profile: result,
                            carbGoal: goal.carb,
                            proteinGoal: goal.protein,
                            fatGoal: goal.fat,
                            goalDate: result.goalDate,
                          );

                          // 새 대시보드를 push하지 않고, AuthGate 아래 기존
                          // 대시보드까지 pop한다. 목표 변경은 Firestore 리스너로 반영된다.
                          if (!onboardingContext.mounted) return;
                          Navigator.of(onboardingContext)
                              .popUntil((route) => route.isFirst);
                        },
                      ),
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF3F5F8B),
                  side: BorderSide(
                    color: const Color(0xFF3F5F8B).withValues(alpha: 0.45),
                    width: 1.4,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  '처음부터 목표 다시 설정하기',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MacroField extends StatelessWidget {
  final String label;
  final int kcalPerGram;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final Color color;

  const _MacroField({
    required this.label,
    required this.kcalPerGram,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
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
            width: 10,
            height: 44,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  '1g당 ${kcalPerGram}kcal',
                  style: const TextStyle(fontSize: 11, color: Colors.black38),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 100,
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              onChanged: onChanged,
              textAlign: TextAlign.right,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
              ],
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                suffixText: 'g',
                suffixStyle: const TextStyle(
                  color: Colors.black54,
                  fontSize: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: Color(0xFF3F5F8B),
                    width: 2,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
