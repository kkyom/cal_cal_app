import 'dart:async';

import 'package:flutter/material.dart';
// import 'ad_banner_widget.dart'; // 광고 비활성화
import 'models.dart';
import 'goal_edit_screen.dart';
import 'food_search_screen.dart';
import 'nutrition_calculator.dart';
import 'firestore_service.dart';
import 'center_toast.dart';
import 'app_date_picker.dart';
import 'settings_screen.dart';
import 'notification_settings_screen.dart';
// import 'subscription_screen.dart'; // 결제 비활성화
import 'onboarding_screen.dart';
import 'responsive_content.dart';

// --- 색상 상수 ---
const Color _bgColor = Color(0xFFF2F2F2);
const Color _remainColor = Color(0xFF5FE0A6);
const Color _labelColor = Color(0xFFD9E2F2);
const Color _carbColor = Color(0xFF34C759);
const Color _proteinColor = Color(0xFF2196F3);
const Color _fatColor = Color(0xFFF5A623);
const Color _cardBgColor = Color(0xFF3F5F8B);
const Color _overGoalColor = Color(0xFFFF6B6B);

// --- 월별 캘린더 달성 여부 점 색상 ---
const Color _achievementGoodColor = Color.fromARGB(255, 6, 229, 99);
const Color _achievementWarnColor = Color.fromARGB(255, 255, 162, 0);
const Color _achievementBadColor = Color.fromARGB(255, 255, 23, 2);

// --- 목표일 캘린더 헤더 색상 ---
const Color _goalCalendarHeaderColor = Color(0xFF5B8DD6);

/// 날짜 네비 행에서 '캘린더' 슬롯과 동일 너비(왼쪽 여백) — 가운데 날짜가 화면 중앙에 맞도록 함
const double _monthlyNavSlotWidth = 84;

// --- 칼로리 환산 상수 ---
const double _carbKcal = 4;
const double _proteinKcal = 4;
const double _fatKcal = 9;

// --- 대시보드용 매크로 집계 모델 ---
class MacroData {
  final double carb;
  final double protein;
  final double fat;
  final int totalKcal;

  const MacroData({
    required this.carb,
    required this.protein,
    required this.fat,
    required this.totalKcal,
  });

  double get intakeKcal =>
      carb * _carbKcal + protein * _proteinKcal + fat * _fatKcal;

  double get remainKcal =>
      (totalKcal - intakeKcal).clamp(0.0, totalKcal.toDouble());

  bool get isOverGoal => intakeKcal > totalKcal;

  double get overKcal => (intakeKcal - totalKcal).clamp(0.0, double.infinity);
}

// --- 메인 대시보드 페이지 ---
class CalorieDashboardPage extends StatefulWidget {
  const CalorieDashboardPage({super.key});

  @override
  State<CalorieDashboardPage> createState() => _CalorieDashboardPageState();
}

class _CalorieDashboardPageState extends State<CalorieDashboardPage> {
  double carbGram = 0;
  double proteinGram = 0;
  double fatGram = 0;

  double _carbGoal = 410;
  double _proteinGoal = 140;
  double _fatGoal = 70;

  int get _totalKcal =>
      (_carbGoal * _carbKcal +
              _proteinGoal * _proteinKcal +
              _fatGoal * _fatKcal)
          .round();

  int _activeMacroIndex = 1;

  List<MealEntry> _meals = [];

  bool _reorderMode = false;

  DateTime? _goalDate;

  /// 기기 로컬 날짜 기준으로 보고 있는 날 (식단·매크로는 이 날짜에만 묶임)
  late DateTime _selectedDate;

  StreamSubscription<void>? _syncSub;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDate = DateTime(now.year, now.month, now.day);
    _reloadDashboardFromCache();
    // 다른 기기에서 데이터가 바뀌면 실시간으로 반영한다.
    _syncSub = FirestoreService.changes.listen((_) {
      if (mounted) _reloadDashboardFromCache();
    });
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    super.dispose();
  }

  void _openSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  void _openNotificationSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NotificationSettingsScreen()),
    );
  }

  // void _openSubscription() {
  //   Navigator.of(context).push(
  //     MaterialPageRoute(builder: (_) => const SubscriptionScreen()),
  //   );
  // } // 결제 비활성화

  /// Firestore 인메모리 캐시에서 대시보드 상태를 다시 읽는다.
  /// 자동 목표(`GoalsSource.auto`)일 때만 프로필 기반으로 매크로를 갱신한다.
  void _reloadDashboardFromCache() {
    setState(() {
      _meals = FirestoreService.loadMealsForDate(_selectedDate);
      _carbGoal = FirestoreService.loadCarbGoal();
      _proteinGoal = FirestoreService.loadProteinGoal();
      _fatGoal = FirestoreService.loadFatGoal();
      _goalDate = FirestoreService.loadGoalDate();
    });

    _refreshAutoMacroGoalsIfNeeded();
  }

  static const List<String> _weekdayShortKo = [
    '월',
    '화',
    '수',
    '목',
    '금',
    '토',
    '일',
  ];

  bool _isSameCalendarDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isSelectedToday() {
    final n = DateTime.now();
    return _isSameCalendarDay(_selectedDate, n);
  }

  void _goToDay(DateTime day) {
    final d = DateTime(day.year, day.month, day.day);
    setState(() {
      _selectedDate = d;
      _meals = FirestoreService.loadMealsForDate(d);
    });
  }

  void _goToPreviousDay() {
    _goToDay(_selectedDate.subtract(const Duration(days: 1)));
  }

  void _goToNextDay() {
    _goToDay(_selectedDate.add(const Duration(days: 1)));
  }

  static Color? _achievementDotColor(DateTime day) {
    switch (FirestoreService.achievementForDate(day)) {
      case GoalAchievement.good:
        return _achievementGoodColor;
      case GoalAchievement.warn:
        return _achievementWarnColor;
      case GoalAchievement.bad:
        return _achievementBadColor;
      case GoalAchievement.none:
        return null;
    }
  }

  Future<void> _pickDayFromCalendar() async {
    final now = DateTime.now();
    final picked = await showAppDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: '날짜 선택',
      helpSubtitle: '달성 여부를 한눈에 확인할 수 있어요',
      dayDotColorBuilder: _achievementDotColor,
      dotLegend: const [
        CalendarDotLegendItem(color: _achievementGoodColor, label: '목표 달성'),
        CalendarDotLegendItem(color: _achievementWarnColor, label: '목표 근접'),
        CalendarDotLegendItem(color: _achievementBadColor, label: '목표 벗어남'),
      ],
    );
    if (!mounted || picked == null) return;
    _goToDay(picked);
  }

  static const int _maxAddedMeals = 5;

  bool _isAddedMeal(MealEntry m) => !m.isFixed;

  int _countAddedMeals(List<MealEntry> meals) =>
      meals.where(_isAddedMeal).length;

  /// 이름을 직접 바꾸지 않은 추가 식사만 "간식 N"으로 순번을 다시 매긴다.
  List<MealEntry> _renumberAddedMeals(List<MealEntry> meals) {
    var n = 1;
    return meals.map((m) {
      if (!_isAddedMeal(m) || m.isCustomNamed) return m;
      final newName = '간식 $n';
      n++;
      if (m.name == newName) return m;
      return m.copyWith(name: newName);
    }).toList();
  }

  /// 프로필로 매크로 목표를 계산할 수 있으면 반환한다. 필수 값이 없으면 null.
  NutritionTargets? _macroGoalsFromProfile({required DateTime goalDate}) {
    final gender = FirestoreService.loadGender();
    final age = FirestoreService.loadAgeYears();
    final height = FirestoreService.loadHeightCm();
    final currentW = FirestoreService.loadCurrentWeightKg();
    final goalW = FirestoreService.loadGoalWeightKg();
    final activity = FirestoreService.loadActivity();
    final purpose = FirestoreService.loadPurpose();

    if (gender == null ||
        age == null ||
        height == null ||
        currentW == null ||
        goalW == null ||
        activity == null ||
        purpose == null) {
      return null;
    }

    return NutritionCalculator.calculate(
      gender: gender,
      ageYears: age,
      heightCm: height,
      currentWeightKg: currentW,
      goalWeightKg: goalW,
      activityMultiplier: NutritionCalculator.activityMultiplierFrom(activity),
      purpose: purpose,
      goalDate: goalDate,
      today: DateTime.now(),
    );
  }

  /// 목표가 자동 출처일 때만 프로필·목표일로 매크로를 다시 계산해 저장한다.
  /// 사용자가 목표 편집에서 직접 수정한 경우(`GoalsSource.manual`)는 건너뛴다.
  void _refreshAutoMacroGoalsIfNeeded() {
    if (FirestoreService.loadGoalsSource() == GoalsSource.manual) return;

    final currentW = FirestoreService.loadCurrentWeightKg();
    final goalW = FirestoreService.loadGoalWeightKg();
    final purpose = FirestoreService.loadPurpose();
    final today = DateTime.now();
    final goalDate =
        _goalDate ??
        (currentW != null && goalW != null && purpose != null
            ? NutritionCalculator.recommendedGoalDate(
                today: today,
                currentWeightKg: currentW,
                goalWeightKg: goalW,
                purpose: purpose,
              )
            : null);
    if (goalDate == null) return;

    if (_goalDate == null) {
      FirestoreService.saveGoalDate(goalDate);
      setState(() => _goalDate = goalDate);
    }

    final targets = _macroGoalsFromProfile(goalDate: goalDate);
    if (targets == null) return;

    final carb = targets.carbGrams.roundToDouble();
    final protein = targets.proteinGrams.roundToDouble();
    final fat = targets.fatGrams.roundToDouble();

    setState(() {
      _carbGoal = carb;
      _proteinGoal = protein;
      _fatGoal = fat;
    });

    FirestoreService.saveGoals(
      carb: carb,
      protein: protein,
      fat: fat,
      source: GoalsSource.auto,
    );
  }

  String _formatDate(DateTime d) =>
      '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickGoalDate() async {
    final currentW = FirestoreService.loadCurrentWeightKg();
    final goalW = FirestoreService.loadGoalWeightKg();
    final purpose = FirestoreService.loadPurpose();
    final now = DateTime.now();
    final firstDate = NutritionCalculator.dateOnly(now);
    final rawInitial =
        _goalDate ??
        (currentW != null && goalW != null && purpose != null
            ? NutritionCalculator.recommendedGoalDate(
                today: now,
                currentWeightKg: currentW,
                goalWeightKg: goalW,
                purpose: purpose,
              )
            : now.add(const Duration(days: 28)));
    final initial = rawInitial.isBefore(firstDate) ? firstDate : rawInitial;

    final picked = await showAppDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: now.add(const Duration(days: 365 * 5)),
      helpText: '목표 날짜 변경하기',
      helpSubtitle: '변경한 날짜에 맞게 칼로리가 조정돼요',
      headerColor: _goalCalendarHeaderColor,
    );

    if (!mounted || picked == null) return;
    FirestoreService.saveGoalDate(picked);
    setState(() => _goalDate = picked);
    // 자동 목표일 때만 남은 일수 변화에 맞춰 매크로를 갱신한다.
    _refreshAutoMacroGoalsIfNeeded();
  }

  static double _macroPercent(double value, double target) {
    if (target == 0) return 0;
    return (value / target).clamp(0.0, double.infinity) * 100;
  }

  void _addMeal() {
    if (_countAddedMeals(_meals) >= _maxAddedMeals) {
      _showCenterToast('간식 추가는 $_maxAddedMeals개까지 가능해요');
      return;
    }
    setState(() {
      _meals = _renumberAddedMeals(_meals);
      final next = _countAddedMeals(_meals) + 1;
      _meals.add(MealEntry(name: '간식 $next'));
      FirestoreService.saveMealsForDate(
        _selectedDate,
        _meals,
        goalKcal: _totalKcal.toDouble(),
      );
    });
    _showCenterToast('추가 완료!');
  }

  void _showCenterToast(String message) {
    showCenterToast(context, message);
  }

  Future<void> _openGoalEdit() async {
    final result = await Navigator.push<GoalData>(
      context,
      MaterialPageRoute(
        builder: (_) => GoalEditScreen(
          initial: GoalData(
            carb: _carbGoal,
            protein: _proteinGoal,
            fat: _fatGoal,
          ),
        ),
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      _carbGoal = result.carb;
      _proteinGoal = result.protein;
      _fatGoal = result.fat;
    });
    // 직접 수정한 값은 이후 동기화/로드에서 자동 재계산으로 덮지 않는다.
    FirestoreService.saveGoals(
      carb: result.carb,
      protein: result.protein,
      fat: result.fat,
      source: GoalsSource.manual,
    );
  }

  Future<void> _openFoodSearch(int index) async {
    final result = await Navigator.push<List<FoodRecord>>(
      context,
      MaterialPageRoute(
        builder: (_) => FoodSearchScreen(
          mealName: _meals[index].name,
          initialFoods: _meals[index].foods,
        ),
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      _meals[index] = _meals[index].copyWith(foods: result);
    });
    FirestoreService.saveMealsForDate(
      _selectedDate,
      _meals,
      goalKcal: _totalKcal.toDouble(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 모든 식사에서 합산한 매크로
    final totalCarb = _meals.fold<double>(
      0,
      (sum, m) => sum + m.foods.fold(0, (s, f) => s + f.carb),
    );
    final totalProtein = _meals.fold<double>(
      0,
      (sum, m) => sum + m.foods.fold(0, (s, f) => s + f.protein),
    );
    final totalFat = _meals.fold<double>(
      0,
      (sum, m) => sum + m.foods.fold(0, (s, f) => s + f.fat),
    );

    final data = MacroData(
      carb: totalCarb,
      protein: totalProtein,
      fat: totalFat,
      totalKcal: _totalKcal,
    );
    final isMaintain =
        FirestoreService.loadPurpose() == OnboardingPurpose.maintain;

    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            20 + MediaQuery.paddingOf(context).bottom,
          ),
          child: ResponsiveContent(
            maxWidth: 420,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                  Row(
                    children: [
                      SizedBox(
                        width: _monthlyNavSlotWidth,
                        child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: _openSettings,
                            icon: const Icon(
                              Icons.settings_outlined,
                              size: 20,
                            ),
                            color: Colors.black45,
                            tooltip: '설정',
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            onPressed: _openNotificationSettings,
                            icon: const Icon(
                              Icons.notifications_outlined,
                              size: 20,
                            ),
                            color: Colors.black45,
                            tooltip: '알림 설정',
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                          ),
                          // 결제 비활성화로 Pro 배지 버튼 임시 제거
                          // TextButton(
                          //   onPressed: _openSubscription,
                          //   style: TextButton.styleFrom(
                          //     foregroundColor: const Color(0xFF3F5F8B),
                          //     backgroundColor: const Color(
                          //       0xFF3F5F8B,
                          //     ).withValues(alpha: 0.10),
                          //     shape: const StadiumBorder(),
                          //     padding: const EdgeInsets.symmetric(
                          //       horizontal: 12,
                          //       vertical: 6,
                          //     ),
                          //     minimumSize: const Size(0, 32),
                          //     tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          //     textStyle: const TextStyle(
                          //       fontWeight: FontWeight.w700,
                          //       fontSize: 13,
                          //     ),
                          //   ),
                          //   child: const Text('Pro'),
                          // ),
                        ],
                        ),
                      ),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              onPressed: _goToPreviousDay,
                              icon: const Icon(Icons.chevron_left),
                              color: Colors.black87,
                              style: IconButton.styleFrom(
                                padding: const EdgeInsets.all(2),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${_selectedDate.month}.${_selectedDate.day}',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _isSelectedToday()
                                        ? Colors.black87
                                        : Colors.black26,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    _isSelectedToday()
                                        ? '오늘'
                                        : _weekdayShortKo[_selectedDate
                                                  .weekday -
                                              1],
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            IconButton(
                              onPressed: _goToNextDay,
                              icon: const Icon(Icons.chevron_right),
                              color: Colors.black87,
                              style: IconButton.styleFrom(
                                padding: const EdgeInsets.all(2),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: _monthlyNavSlotWidth,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: _pickDayFromCalendar,
                            icon: const Icon(
                              Icons.calendar_month_outlined,
                              size: 15,
                            ),
                            label: const Text('캘린더'),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFF3F5F8B),
                              backgroundColor: const Color(
                                0xFF3F5F8B,
                              ).withValues(alpha: 0.10),
                              shape: const StadiumBorder(),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              minimumSize: const Size(0, 32),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (isMaintain)
                    Text(
                      '체중 유지를 위해 힘내봐요!',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.black.withValues(alpha: 0.55),
                      ),
                    )
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            _goalDate == null
                                ? '목표 날짜를 설정해 주세요'
                                : '목표 날짜: ${_formatDate(_goalDate!)}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.black.withValues(alpha: 0.55),
                            ),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _pickGoalDate,
                          icon: const Icon(Icons.flag_outlined, size: 15),
                          label: const Text('목표일'),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF3F5F8B),
                            backgroundColor: const Color(
                              0xFF3F5F8B,
                            ).withValues(alpha: 0.10),
                            shape: const StadiumBorder(),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            textStyle: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 10),
                  _DashboardCard(
                    data: data,
                    totalKcal: _totalKcal,
                    carbGram: totalCarb,
                    proteinGram: totalProtein,
                    fatGram: totalFat,
                    carbGoal: _carbGoal,
                    proteinGoal: _proteinGoal,
                    fatGoal: _fatGoal,
                    activeMacroIndex: _activeMacroIndex,
                    onMacroTap: (i) => setState(() => _activeMacroIndex = i),
                    macroPercent: _macroPercent,
                    onEditGoal: _openGoalEdit,
                  ),

                  const SizedBox(height: 16),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '식단 기록',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.black,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton.icon(
                            onPressed: _reorderMode ? null : _addMeal,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('추가'),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red,
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () =>
                                setState(() => _reorderMode = !_reorderMode),
                            icon: Icon(
                              _reorderMode ? Icons.check : Icons.swap_vert,
                            ),
                            color: _cardBgColor,
                            tooltip: _reorderMode ? '완료' : '순서 변경',
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  ReorderableListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    buildDefaultDragHandles: false,
                    proxyDecorator: (child, index, animation) => Material(
                      type: MaterialType.transparency,
                      child: child,
                    ),
                    itemCount: _meals.length,
                    itemBuilder: (context, index) => Padding(
                      key: ValueKey(_meals[index].id),
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _MealItem(
                        meal: _meals[index],
                        reorderMode: _reorderMode,
                        dragHandle: _reorderMode
                            ? ReorderableDragStartListener(
                                index: index,
                                child: const Icon(
                                  Icons.drag_handle,
                                  color: Colors.black38,
                                ),
                              )
                            : null,
                        onTap: () => _openFoodSearch(index),
                        onRename: _meals[index].isFixed
                            ? null
                            : (newName) {
                                setState(() {
                                  _meals[index] = _meals[index].copyWith(
                                    name: newName,
                                    isCustomNamed: true,
                                  );
                                });
                                FirestoreService.saveMealsForDate(
                                  _selectedDate,
                                  _meals,
                                  goalKcal: _totalKcal.toDouble(),
                                );
                              },
                        onDelete: _meals[index].isFixed
                            ? null
                            : () {
                                final deletedName = _meals[index].name;
                                setState(() {
                                  _meals.removeAt(index);
                                  _meals = _renumberAddedMeals(_meals);
                                });
                                FirestoreService.saveMealsForDate(
                                  _selectedDate,
                                  _meals,
                                  goalKcal: _totalKcal.toDouble(),
                                );
                                _showCenterToast('$deletedName 삭제 완료!');
                              },
                      ),
                    ),
                    onReorderItem: (oldIndex, newIndex) {
                      setState(() {
                        final item = _meals.removeAt(oldIndex);
                        _meals.insert(newIndex, item);
                      });
                      FirestoreService.saveMealsForDate(
                        _selectedDate,
                        _meals,
                        goalKcal: _totalKcal.toDouble(),
                      );
                    },
                  ),

                  const SizedBox(height: 20),
                  // Center(child: AdBannerWidget(adUnitId: AdUnitIds.dashboard)), // 광고 비활성화
                ],
              ),
            ),
          ),
        ),
      );
  }
}


// --- 대시보드 카드 위젯 ---
class _DashboardCard extends StatelessWidget {
  final MacroData data;
  final int totalKcal;
  final double carbGram;
  final double proteinGram;
  final double fatGram;
  final double carbGoal;
  final double proteinGoal;
  final double fatGoal;
  final int activeMacroIndex;
  final ValueChanged<int> onMacroTap;
  final double Function(double, double) macroPercent;
  final VoidCallback onEditGoal;

  const _DashboardCard({
    required this.data,
    required this.totalKcal,
    required this.carbGram,
    required this.proteinGram,
    required this.fatGram,
    required this.carbGoal,
    required this.proteinGoal,
    required this.fatGoal,
    required this.activeMacroIndex,
    required this.onMacroTap,
    required this.macroPercent,
    required this.onEditGoal,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 16, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black12, width: 1.5),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x33FFFFFF), Color(0x26000000)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onEditGoal,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white70,
                textStyle: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.tune, size: 16),
                  SizedBox(width: 4),
                  Text('목표 수정'),
                ],
              ),
            ),
          ),

          const SizedBox(height: 4),

          RichText(
            text: TextSpan(
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
              children: [
                TextSpan(
                  text: data.intakeKcal.toStringAsFixed(0),
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const TextSpan(text: " / "),
                TextSpan(
                  text: "$totalKcal kcal",
                  style: const TextStyle(fontSize: 20, color: Colors.white70),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _MacroBadge(
                label: "탄",
                percent: macroPercent(carbGram, carbGoal),
                active: true,
              ),
              const SizedBox(width: 8),
              _MacroBadge(
                label: "단",
                percent: macroPercent(proteinGram, proteinGoal),
                active: true,
              ),
              const SizedBox(width: 8),
              _MacroBadge(
                label: "지",
                percent: macroPercent(fatGram, fatGoal),
                active: true,
              ),
            ],
          ),

          const SizedBox(height: 16),

          Center(
            child: Text(
              data.isOverGoal
                  ? "${data.overKcal.toStringAsFixed(0)}kcal 더 먹었어요"
                  : "${data.remainKcal.toStringAsFixed(0)}kcal 더 먹을 수 있어요",
              style: const TextStyle(
                color: _remainColor,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          const SizedBox(height: 16),

          _MacroRow(
            title: "탄수화물",
            value: carbGram,
            target: carbGoal,
            color: _carbColor,
          ),
          const SizedBox(height: 12),
          _MacroRow(
            title: "단백질",
            value: proteinGram,
            target: proteinGoal,
            color: _proteinColor,
          ),
          const SizedBox(height: 12),
          _MacroRow(
            title: "지방",
            value: fatGram,
            target: fatGoal,
            color: _fatColor,
          ),
        ],
      ),
    );
  }
}

// --- 식사 항목 위젯 ---
class _MealItem extends StatelessWidget {
  final MealEntry meal;
  final bool reorderMode;
  final Widget? dragHandle;
  final VoidCallback onTap;
  final ValueChanged<String>? onRename;
  final VoidCallback? onDelete;

  const _MealItem({
    required this.meal,
    this.reorderMode = false,
    this.dragHandle,
    required this.onTap,
    this.onRename,
    required this.onDelete,
  });

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '식사 삭제',
          style: TextStyle(
            color: Color(0xFF3F5F8B),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          '삭제하시겠습니까?',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF767474).withValues(alpha: 0.8),
              textStyle: const TextStyle(fontWeight: FontWeight.bold),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('아니오'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF3F5F8B).withValues(alpha: 0.8),
              textStyle: const TextStyle(fontWeight: FontWeight.bold),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('예'),
          ),
        ],
      ),
    );
    if (context.mounted && (confirmed ?? false)) onDelete?.call();
  }

  Future<void> _editName(BuildContext context) async {
    final newName = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _MealNameEditDialog(initialName: meal.name),
    );
    if (newName == null) return;
    onRename?.call(newName);
  }

  Future<void> _showMealActions(BuildContext context) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: Color(0xFF3F5F8B)),
              title: const Text(
                '이름 변경',
                style: TextStyle(
                  color: Color(0xFF3F5F8B),
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: _overGoalColor),
              title: const Text(
                '삭제',
                style: TextStyle(
                  color: _overGoalColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case 'rename':
        await _editName(context);
      case 'delete':
        await _confirmDelete(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = onRename != null || onDelete != null;
    return GestureDetector(
      onTap: reorderMode ? null : onTap,
      onLongPress:
          !reorderMode && canEdit ? () => _showMealActions(context) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE0E0E0), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4FA),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.restaurant_menu,
                size: 20,
                color: Colors.black,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                meal.name,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.black,
                ),
              ),
            ),
            Text(
              meal.kcal > 0 ? '${meal.kcal.toStringAsFixed(0)} kcal' : '- kcal',
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black45,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            if (dragHandle != null)
              dragHandle!
            else
              const Icon(Icons.chevron_right, color: Colors.black38, size: 20),
          ],
        ),
      ),
    );
  }
}

// --- 식사 이름 변경 다이얼로그 ---
class _MealNameEditDialog extends StatefulWidget {
  final String initialName;

  const _MealNameEditDialog({required this.initialName});

  @override
  State<_MealNameEditDialog> createState() => _MealNameEditDialogState();
}

class _MealNameEditDialogState extends State<_MealNameEditDialog> {
  static const int _maxNameLength = 10;

  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) return;
    Navigator.pop(context, trimmed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        '이름 변경',
        style: TextStyle(
          color: Color(0xFF3F5F8B),
          fontWeight: FontWeight.bold,
        ),
      ),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: _maxNameLength,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: const InputDecoration(counterText: ''),
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
          onPressed: _submit,
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF3F5F8B).withValues(alpha: 0.8),
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

class _MacroBadge extends StatelessWidget {
  final String label;
  final double percent;
  final bool active;

  const _MacroBadge({
    required this.label,
    required this.percent,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: active
            ? Colors.white.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            "${percent.toStringAsFixed(0)}%",
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _MacroRow extends StatelessWidget {
  final String title;
  final double value;
  final double target;
  final Color color;

  const _MacroRow({
    required this.title,
    required this.value,
    required this.target,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final double ratio = target == 0 ? 0 : (value / target).clamp(0.0, 1.0);
    final bool isOverGoal = target > 0 && value > target;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            RichText(
              text: TextSpan(
                style: const TextStyle(color: _labelColor, fontSize: 13),
                children: [
                  TextSpan(
                    text: value.toStringAsFixed(0),
                    style: TextStyle(
                      color: isOverGoal ? _overGoalColor : _labelColor,
                      fontWeight: isOverGoal
                          ? FontWeight.w700
                          : FontWeight.normal,
                    ),
                  ),
                  TextSpan(text: " / ${target.toStringAsFixed(0)}g"),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 8,
            backgroundColor: Colors.white.withValues(alpha: 0.1),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

// --- 화면 중앙에 잠시 표시되는 토스트 메시지 ---
