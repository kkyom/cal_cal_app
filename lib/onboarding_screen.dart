import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:keyboard_actions/keyboard_actions.dart';

import 'keyboard_actions_config.dart';
import 'nutrition_calculator.dart';
import 'responsive_content.dart';
import 'app_date_picker.dart';

enum OnboardingPurpose { diet, maintain, leanMass, bulk, ketogenic }

extension OnboardingPurposeX on OnboardingPurpose {
  String get label => switch (this) {
    OnboardingPurpose.diet => '다이어트',
    OnboardingPurpose.maintain => '체중 유지',
    OnboardingPurpose.leanMass => '린매스업',
    OnboardingPurpose.bulk => '벌크업',
    OnboardingPurpose.ketogenic => '키토제닉',
  };
}

enum OnboardingGender { female, male }

extension OnboardingGenderX on OnboardingGender {
  String get label => switch (this) {
    OnboardingGender.female => '여성',
    OnboardingGender.male => '남성',
  };
}

enum OnboardingActivity { veryLow, low, normal, high, veryHigh }

extension OnboardingActivityX on OnboardingActivity {
  String get label => switch (this) {
    OnboardingActivity.veryLow => '매우 적음',
    OnboardingActivity.low => '적음',
    OnboardingActivity.normal => '보통',
    OnboardingActivity.high => '많음',
    OnboardingActivity.veryHigh => '매우 많음',
  };
}

class OnboardingResult {
  final OnboardingPurpose purpose;
  final OnboardingGender gender;
  final int ageYears;
  final double heightCm;
  final OnboardingActivity activity;
  final double startWeightKg;
  final double goalWeightKg;

  /// 일일 목표 탄단지 계산에 사용한 목표 날짜(점검 화면에서 변경 가능).
  final DateTime goalDate;

  const OnboardingResult({
    required this.purpose,
    required this.gender,
    required this.ageYears,
    required this.heightCm,
    required this.activity,
    required this.startWeightKg,
    required this.goalWeightKg,
    required this.goalDate,
  });
}

class OnboardingScreen extends StatefulWidget {
  /// 완료 처리(저장)를 담당한다. 저장이 끝날 때까지 완료 버튼은 로딩 상태가
  /// 되고, 예외를 던지면 온보딩 화면에 머문 채 재시도 안내가 뜬다.
  final Future<void> Function(OnboardingResult result)? onFinished;

  const OnboardingScreen({super.key, this.onFinished});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const int _stepCount = 5;

  /// 입력 허용 상한(이 값 미만만 유효).
  static const int _maxAgeYears = 150;
  static const double _maxHeightCm = 300;
  static const double _maxWeightKg = 350;

  static const String _ageErrorText = '올바른 나이를 다시 입력해주세요';
  static const String _heightErrorText = '올바른 키를 다시 입력해주세요';
  static const String _weightErrorText = '올바른 체중을 다시 입력해주세요';
  static const String _genericErrorText = '올바른 값으로 다시 입력해주세요';

  final PageController _pageController = PageController(initialPage: 0);
  int _currentStep = 0;

  /// 마지막 단계에서 완료를 눌러 저장이 진행 중인 동안 true.
  bool _submitting = false;

  OnboardingPurpose? _purpose;
  OnboardingGender? _gender;
  OnboardingActivity? _activity;

  late final TextEditingController _ageCtrl;
  late final TextEditingController _heightCtrl;
  late final TextEditingController _startWeightCtrl;
  late final TextEditingController _goalWeightCtrl;

  final FocusNode _ageFocus = FocusNode();
  final FocusNode _heightFocus = FocusNode();
  final FocusNode _startWeightFocus = FocusNode();
  final FocusNode _goalWeightFocus = FocusNode();

  int? _ageYears;
  double? _heightCm;
  double? _startWeightKg;
  double? _goalWeightKg;

  /// 5단계 점검 화면용 목표 날짜(4단계에서 '다음' 시 권장일로 초기화).
  DateTime? _reviewGoalDate;

  @override
  void initState() {
    super.initState();
    _ageCtrl = TextEditingController();
    _heightCtrl = TextEditingController();
    _startWeightCtrl = TextEditingController();
    _goalWeightCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _ageCtrl.dispose();
    _heightCtrl.dispose();
    _startWeightCtrl.dispose();
    _goalWeightCtrl.dispose();
    _ageFocus.dispose();
    _heightFocus.dispose();
    _startWeightFocus.dispose();
    _goalWeightFocus.dispose();
    super.dispose();
  }

  bool get _isLastStep => _currentStep == _stepCount - 1;

  bool get _canGoBack => _currentStep > 0;

  bool get _isMaintain => _purpose == OnboardingPurpose.maintain;

  bool get _ageValid {
    final v = _parseAge();
    return v != null && v > 0 && v < _maxAgeYears;
  }

  bool get _heightValid {
    final v = _parseHeight();
    return v != null && v > 0 && v < _maxHeightCm;
  }

  bool get _startWeightValid {
    final v = _parseStartWeight();
    return v != null && v > 0 && v < _maxWeightKg;
  }

  bool get _goalWeightValid {
    final v = _parseGoalWeight();
    return v != null && v > 0 && v < _maxWeightKg;
  }

  bool get _canProceed {
    switch (_currentStep) {
      case 0:
        return _purpose != null;
      case 1:
        return _gender != null && _ageValid && _heightValid;
      case 2:
        return _activity != null;
      case 3:
        return _startWeightValid && _goalWeightValid;
      case 4:
        return _reviewGoalDate != null && _computeReviewTargets() != null;
      default:
        return false;
    }
  }

  void _goBack() {
    if (!_canGoBack) return;
    FocusScope.of(context).unfocus();
    _pageController.animateToPage(
      _currentStep - 1,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  int? _parseAge() => _ageYears ?? int.tryParse(_ageCtrl.text.trim());

  double? _parseHeight() =>
      _heightCm ??
      double.tryParse(_heightCtrl.text.trim().replaceAll(',', '.'));

  double? _parseStartWeight() =>
      _startWeightKg ??
      double.tryParse(_startWeightCtrl.text.trim().replaceAll(',', '.'));

  double? _parseGoalWeight() {
    // 체중 유지는 '현재 체중'만 입력받고 목표 체중을 동일하게 사용한다.
    if (_isMaintain) return _parseStartWeight();
    return _goalWeightKg ??
        double.tryParse(_goalWeightCtrl.text.trim().replaceAll(',', '.'));
  }

  NutritionTargets? _computeReviewTargets() {
    final purpose = _purpose;
    final gender = _gender;
    final activity = _activity;
    final gd = _reviewGoalDate;
    final age = _parseAge();
    final height = _parseHeight();
    final startW = _parseStartWeight();
    final goalW = _parseGoalWeight();
    if (purpose == null ||
        gender == null ||
        activity == null ||
        gd == null ||
        age == null ||
        height == null ||
        startW == null ||
        goalW == null) {
      return null;
    }
    return NutritionCalculator.calculate(
      gender: gender,
      ageYears: age,
      heightCm: height,
      currentWeightKg: startW,
      goalWeightKg: goalW,
      activityMultiplier: NutritionCalculator.activityMultiplierFrom(activity),
      purpose: purpose,
      goalDate: gd,
      today: DateTime.now(),
    );
  }

  Future<void> _pickReviewGoalDate() async {
    final now = DateTime.now();
    final first = NutritionCalculator.dateOnly(now);
    final picked = await showAppDatePicker(
      context: context,
      initialDate: NutritionCalculator.dateOnly(_reviewGoalDate ?? first),
      firstDate: first,
      lastDate: now.add(const Duration(days: 365 * 5)),
      helpText: '목표 날짜 선택',
    );
    if (picked == null) return;
    if (!context.mounted) return;
    setState(() => _reviewGoalDate = picked);
  }

  void _goNext() {
    FocusScope.of(context).unfocus();

    if (_isLastStep) {
      _finishOnboarding();
      return;
    }

    if (_currentStep == 3) {
      final startW = _parseStartWeight();
      final goalW = _parseGoalWeight();
      final purpose = _purpose;
      if (purpose == null ||
          startW == null ||
          goalW == null ||
          !_startWeightValid ||
          !_goalWeightValid) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text(_weightErrorText)));
        return;
      }
      setState(() {
        _reviewGoalDate = NutritionCalculator.recommendedGoalDate(
          today: DateTime.now(),
          currentWeightKg: startW,
          goalWeightKg: goalW,
          purpose: purpose,
        );
      });
    }

    _pageController.animateToPage(
      _currentStep + 1,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finishOnboarding() async {
    if (_submitting) return;

    final purpose = _purpose;
    final gender = _gender;
    final activity = _activity;
    final goalDate = _reviewGoalDate;

    final age = _parseAge();
    final height = _parseHeight();
    final startW = _parseStartWeight();
    final goalW = _parseGoalWeight();

    if (purpose == null ||
        gender == null ||
        activity == null ||
        goalDate == null ||
        age == null ||
        height == null ||
        startW == null ||
        goalW == null ||
        !_ageValid ||
        !_heightValid ||
        !_startWeightValid ||
        !_goalWeightValid) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text(_genericErrorText)));
      return;
    }

    final result = OnboardingResult(
      purpose: purpose,
      gender: gender,
      ageYears: age,
      heightCm: height,
      activity: activity,
      startWeightKg: startW,
      goalWeightKg: goalW,
      goalDate: goalDate,
    );

    final onFinished = widget.onFinished;
    if (onFinished == null) {
      Navigator.pop(context, result);
      return;
    }

    setState(() => _submitting = true);
    try {
      await onFinished(result);
      // 성공하면 상위(_SignedInGate)가 화면을 대시보드로 교체하므로
      // 여기서 _submitting 을 되돌릴 필요가 없다(위젯이 곧 dispose).
    } catch (e) {
      debugPrint('온보딩 저장 실패: $e');
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('저장에 실패했어요. 네트워크 상태를 확인하고 다시 시도해 주세요.'),
        ),
      );
    }
  }

  void _updateStartWeight(String raw) {
    final v = double.tryParse(raw.trim().replaceAll(',', '.'));
    setState(() => _startWeightKg = v);
  }

  void _updateGoalWeight(String raw) {
    final v = double.tryParse(raw.trim().replaceAll(',', '.'));
    setState(() => _goalWeightKg = v);
  }

  void _updateAge(String raw) {
    final v = int.tryParse(raw.trim());
    setState(() => _ageYears = v);
  }

  void _updateHeight(String raw) {
    final v = double.tryParse(raw.trim().replaceAll(',', '.'));
    setState(() => _heightCm = v);
  }

  Widget _buildProgress() {
    final List<int> activeSteps = List<int>.generate(_stepCount, (i) => i);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 16, 6),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: _canGoBack
                    ? IconButton(
                        padding: EdgeInsets.zero,
                        iconSize: 20,
                        splashRadius: 20,
                        onPressed: _goBack,
                        icon: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Color(0xFF3F5F8B),
                        ),
                        tooltip: '이전',
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '설정 ${_currentStep + 1} / $_stepCount',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF3F5F8B),
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
          child: Row(
            children: activeSteps.map((i) {
              final bool done = i < _currentStep;
              final bool current = i == _currentStep;
              Color color;
              if (done) {
                color = const Color(0xFF5FE0A6);
              } else if (current) {
                color = const Color(0xFF3F5F8B);
              } else {
                color = Colors.black.withValues(alpha: 0.12);
              }
              return Expanded(
                child: Container(
                  height: 10,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: color,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // 1단계: 목표 설정 화면
  Widget _buildStep1() {
    return _OnboardingStep(
      title: '목표 설정',
      description: '칼캘을 사용하는 목표를 선택해 주세요',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BigOption<OnboardingPurpose>(
            value: OnboardingPurpose.diet,
            selected: _purpose == OnboardingPurpose.diet,
            label: OnboardingPurpose.diet.label,
            subtitle: '체중 감량이 목표에요',
            onTap: (v) => setState(() => _purpose = v),
          ),
          const SizedBox(height: 14),
          _BigOption<OnboardingPurpose>(
            value: OnboardingPurpose.maintain,
            selected: _purpose == OnboardingPurpose.maintain,
            label: OnboardingPurpose.maintain.label,
            subtitle: '현재 체중과 컨디션 유지가 목표에요',
            onTap: (v) => setState(() => _purpose = v),
          ),
          const SizedBox(height: 14),
          _BigOption<OnboardingPurpose>(
            value: OnboardingPurpose.leanMass,
            selected: _purpose == OnboardingPurpose.leanMass,
            label: OnboardingPurpose.leanMass.label,
            subtitle: '체지방은 최소로, 근육도 천천히 증가시키고 싶어요',
            onTap: (v) => setState(() => _purpose = v),
          ),
          const SizedBox(height: 14),
          _BigOption<OnboardingPurpose>(
            value: OnboardingPurpose.bulk,
            selected: _purpose == OnboardingPurpose.bulk,
            label: OnboardingPurpose.bulk.label,
            subtitle: '근육 증가가 목표에요',
            onTap: (v) => setState(() => _purpose = v),
          ),
          const SizedBox(height: 14),
          _BigOption<OnboardingPurpose>(
            value: OnboardingPurpose.ketogenic,
            selected: _purpose == OnboardingPurpose.ketogenic,
            label: OnboardingPurpose.ketogenic.label,
            subtitle: '저탄수, 고지방 위주로 먹을 예정이에요',
            onTap: (v) => setState(() => _purpose = v),
          ),
        ],
      ),
    );
  }

// 2단계: 기초 정보 설정 화면
  Widget _buildStep2() {
    final bool showAgeError =
        _ageCtrl.text.trim().isNotEmpty && !_ageValid;
    final bool showHeightError =
        _heightCtrl.text.trim().isNotEmpty && !_heightValid;

    return _OnboardingStep(
      title: '기초 정보 설정',
      description: '성별, 나이, 키를 입력해 주세요',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BigOption<OnboardingGender>(
            value: OnboardingGender.female,
            selected: _gender == OnboardingGender.female,
            label: OnboardingGender.female.label,
            onTap: (v) => setState(() => _gender = v),
          ),
          const SizedBox(height: 14),
          _BigOption<OnboardingGender>(
            value: OnboardingGender.male,
            selected: _gender == OnboardingGender.male,
            label: OnboardingGender.male.label,
            onTap: (v) => setState(() => _gender = v),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ageCtrl,
                  focusNode: _ageFocus,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: '나이',
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF3F5F8B),
                    ),
                    hintText: '만 나이',
                    suffixText: '세',
                    suffixStyle: const TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w700,
                    ),
                    errorText: showAgeError ? _ageErrorText : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  onChanged: _updateAge,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _heightCtrl,
                  focusNode: _heightFocus,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  textInputAction: TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: '키',
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF3F5F8B),
                    ),
                    hintText: '',
                    suffixText: 'cm',
                    suffixStyle: const TextStyle(
                      color: Colors.black54,
                      fontWeight: FontWeight.w700,
                    ),
                    errorText: showHeightError ? _heightErrorText : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  onChanged: _updateHeight,
                  onSubmitted: (_) => _canProceed ? _goNext() : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 3단계: 평소 활동량 설정 화면
  Widget _buildStep3() {
    return _OnboardingStep(
      title: '평소 활동량',
      description: '일상에서의 활동량을 선택해 주세요',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BigOption<OnboardingActivity>(
            value: OnboardingActivity.veryLow,
            selected: _activity == OnboardingActivity.veryLow,
            label: OnboardingActivity.veryLow.label,
            subtitle: '집이 좋아! 활동이 거의 없어요',
            onTap: (v) => setState(() => _activity = v),
          ),
          const SizedBox(height: 14),
          _BigOption<OnboardingActivity>(
            value: OnboardingActivity.low,
            selected: _activity == OnboardingActivity.low,
            label: OnboardingActivity.low.label,
            subtitle: '주로 앉아있는 학생, 직장인이고 주 1회 운동해요',
            onTap: (v) => setState(() => _activity = v),
          ),
          const SizedBox(height: 14),
          _BigOption<OnboardingActivity>(
            value: OnboardingActivity.normal,
            selected: _activity == OnboardingActivity.normal,
            label: OnboardingActivity.normal.label,
            subtitle: '출퇴근, 주 2~3회 운동해요',
            onTap: (v) => setState(() => _activity = v),
          ),
          const SizedBox(height: 14),
          _BigOption<OnboardingActivity>(
            value: OnboardingActivity.high,
            selected: _activity == OnboardingActivity.high,
            label: OnboardingActivity.high.label,
            subtitle: '거의 매일 뛰거나 주 4~5회 운동해요',
            onTap: (v) => setState(() => _activity = v),
          ),
          const SizedBox(height: 14),
          _BigOption<OnboardingActivity>(
            value: OnboardingActivity.veryHigh,
            selected: _activity == OnboardingActivity.veryHigh,
            label: OnboardingActivity.veryHigh.label,
            subtitle: '운동 관련 직업, 매일 강도높게 운동해요',
            onTap: (v) => setState(() => _activity = v),
          ),
        ],
      ),
    );
  }

  // 4단계: 체중 입력 화면
  Widget _buildStep4() {
    final bool isMaintain = _isMaintain;
    final bool showStartError =
        _startWeightCtrl.text.trim().isNotEmpty && !_startWeightValid;
    final bool showGoalError =
        _goalWeightCtrl.text.trim().isNotEmpty && !_goalWeightValid;

    return _OnboardingStep(
      title: '체중 입력',
      description: isMaintain ? '현재 체중을 입력해 주세요' : '현재 체중과 목표 체중을 입력해 주세요',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _startWeightCtrl,
            focusNode: _startWeightFocus,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            textInputAction:
                isMaintain ? TextInputAction.done : TextInputAction.next,
            decoration: InputDecoration(
              labelText: isMaintain ? '현재 체중' : '시작 체중',
              labelStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF3F5F8B),
              ),
              hintText: '현재 체중을 입력해주세요',
              suffixText: 'kg',
              suffixStyle: const TextStyle(
                color: Colors.black54,
                fontWeight: FontWeight.w700,
              ),
              errorText: showStartError ? _weightErrorText : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
            onChanged: _updateStartWeight,
            onSubmitted: isMaintain
                ? (_) => _canProceed ? _goNext() : null
                : null,
          ),
          if (!isMaintain) ...[
            const SizedBox(height: 14),
            TextField(
              controller: _goalWeightCtrl,
              focusNode: _goalWeightFocus,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                labelText: '목표 체중',
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF3F5F8B),
                ),
                hintText: '목표 체중을 입력해주세요',
                suffixText: 'kg',
                suffixStyle: const TextStyle(
                  color: Colors.black54,
                  fontWeight: FontWeight.w700,
                ),
                errorText: showGoalError ? _weightErrorText : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                filled: true,
                fillColor: Colors.white,
              ),
              onChanged: _updateGoalWeight,
              onSubmitted: (_) => _canProceed ? _goNext() : null,
            ),
          ],
          const SizedBox(height: 22),
          _HintText('다음에서 목표를 확인하고 완료할 수 있어요'),
        ],
      ),
    );
  }

  // 5단계: 목표 점검 화면
  Widget _buildStep5() {
    final targets = _computeReviewTargets();
    final gd = _reviewGoalDate;
    final purpose = _purpose;
    final startW = _parseStartWeight();

    if (targets == null || gd == null || purpose == null || startW == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final isMaintain = purpose == OnboardingPurpose.maintain;
    final today = NutritionCalculator.dateOnly(DateTime.now());
    final goalDay = NutritionCalculator.dateOnly(gd);
    final rawDays = goalDay.difference(today).inDays;
    final totalDays = rawDays < 1 ? 1 : rawDays;

    final ratioLabel = NutritionCalculator.macroRatioLabel(purpose);
    final proteinPerKg = targets.proteinGrams / startW;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '목표 점검',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: Color(0xFF1F2D3D),
            ),
          ),
          if (!isMaintain) ...[
            const SizedBox(height: 8),
            Text(
              NutritionCalculator.recommendedPaceLabel(purpose),
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: Colors.black.withValues(alpha: 0.45),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    '총 $totalDays일 소요',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF3F5F8B),
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _pickReviewGoalDate,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF3F5F8B),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  child: const Text('기간 변경'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '목표일: ${gd.year}.${gd.month.toString().padLeft(2, '0')}.${gd.day.toString().padLeft(2, '0')}',
              style: TextStyle(
                fontSize: 16,
                color: Colors.black.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 10),
          ] else
            const SizedBox(height: 18),
          Text(
            '일일 목표 칼로리 ${targets.targetCalories.round()} kcal',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black.withValues(alpha: 0.62),
            ),
          ),
          const SizedBox(height: 20),
          _ReadOnlyMacroTile(
            label: '탄수화물',
            grams: targets.carbGrams,
            color: const Color(0xFFFFCE54),
          ),
          const SizedBox(height: 12),
          _ReadOnlyMacroTile(
            label: '단백질',
            grams: targets.proteinGrams,
            color: const Color(0xFFF6D55C),
          ),
          const SizedBox(height: 12),
          _ReadOnlyMacroTile(
            label: '지방',
            grams: targets.fatGrams,
            color: const Color(0xFF4B89DC),
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '탄:단:지 비율 $ratioLabel',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2D3D),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  targets.proteinCapped
                      ? '단백질은 체중 1kg 당 2.2g을 넘지 않도록 조정했고, 남은 칼로리는 탄수화물과 지방에 비율대로 나눴어요'
                      : '단백질은 체중 1kg 당 ${proteinPerKg.toStringAsFixed(1)} g으로 계산했어요',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: Colors.black.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '본 앱의 목표·칼로리 정보는 일반적인 참고용이며 의료 조언이 아닙니다.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              height: 1.35,
              color: Colors.black.withValues(alpha: 0.38),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final String buttonText = _isLastStep ? '완료' : '다음';

    return KeyboardActions(
      disableScroll: true,
      config: buildKeyboardActionsConfig([
        _ageFocus,
        _heightFocus,
        _startWeightFocus,
        _goalWeightFocus,
      ]),
      child: Scaffold(
        backgroundColor: const Color(0xFFF2F2F2),
        body: SafeArea(
          top: true,
          bottom: false,
          child: ResponsiveContent(
            child: Column(
              children: [
                _buildProgress(),
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    onPageChanged: (i) => setState(() => _currentStep = i),
                    children: [
                      _buildStep1(),
                      _buildStep2(),
                      _buildStep3(),
                      _buildStep4(),
                      _buildStep5(),
                    ],
                  ),
                ),
                SafeArea(
                  top: false,
                  minimum: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: (_canProceed && !_submitting) ? _goNext : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3F5F8B),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        disabledBackgroundColor: const Color(
                          0xFF3F5F8B,
                        ).withValues(alpha: 0.4),
                        elevation: 2,
                      ),
                      child: _submitting
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              buttonText,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReadOnlyMacroTile extends StatelessWidget {
  final String label;
  final double grams;
  final Color color;

  const _ReadOnlyMacroTile({
    required this.label,
    required this.grams,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
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
            width: 8,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1F2D3D),
              ),
            ),
          ),
          Text(
            '${grams.round()} g',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Color(0xFF3F5F8B),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingStep extends StatelessWidget {
  final String title;
  final String description;
  final Widget child;

  const _OnboardingStep({
    required this.title,
    required this.description,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: Color(0xFF1F2D3D),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            description,
            style: TextStyle(
              fontSize: 15,
              color: Colors.black.withValues(alpha: 0.62),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 22),
          child,
        ],
      ),
    );
  }
}

class _BigOption<T> extends StatelessWidget {
  final T value;
  final bool selected;
  final String label;
  final String? subtitle;
  final ValueChanged<T> onTap;

  const _BigOption({
    required this.value,
    required this.selected,
    required this.label,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color selectedBg = const Color(0xFF3F5F8B);
    final Color unselectedBg = Colors.white;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => onTap(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          constraints: const BoxConstraints(minHeight: 66),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? selectedBg : unselectedBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected
                  ? const Color(0xFF3F5F8B)
                  : Colors.black.withValues(alpha: 0.06),
              width: 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.14),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: selected ? Colors.white : Colors.black87,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.25,
                          color: selected
                              ? Colors.white.withValues(alpha: 0.78)
                              : Colors.black.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: selected
                    ? Colors.white
                    : Colors.black.withValues(alpha: 0.35),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HintText extends StatelessWidget {
  final String text;

  const _HintText(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.black.withValues(alpha: 0.55),
          fontSize: 13,
          height: 1.3,
        ),
      ),
    );
  }
}
