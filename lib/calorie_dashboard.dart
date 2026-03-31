import 'package:flutter/material.dart';
import 'models.dart';
import 'goal_edit_page.dart';
import 'food_search_page.dart';
import 'storage_service.dart';

// --- 색상 상수 ---
const Color _bgColor = Color(0xFFF2F2F2);
const Color _remainColor = Color(0xFF5FE0A6);
const Color _labelColor = Color(0xFFD9E2F2);
const Color _carbColor = Color(0xFFFFCE54);
const Color _proteinColor = Color(0xFFF6D55C);
const Color _fatColor = Color(0xFF4B89DC);
const Color _cardBgColor = Color(0xFF3F5F8B);

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
  final double burnedKcal;

  const MacroData({
    required this.carb,
    required this.protein,
    required this.fat,
    required this.totalKcal,
    this.burnedKcal = 0,
  });

  double get intakeKcal =>
      carb * _carbKcal + protein * _proteinKcal + fat * _fatKcal;

  double get remainKcal =>
      (totalKcal - intakeKcal + burnedKcal).clamp(0.0, totalKcal.toDouble());
}

// --- 대시보드 페이지 ---
class CalorieDashboardPage extends StatefulWidget {
  const CalorieDashboardPage({super.key});

  @override
  State<CalorieDashboardPage> createState() => _CalorieDashboardPageState();
}

class _CalorieDashboardPageState extends State<CalorieDashboardPage> {
  double carbGram = 0;
  double proteinGram = 0;
  double fatGram = 0;
  double burnedKcal = 0;

  double _carbGoal = 410;
  double _proteinGoal = 140;
  double _fatGoal = 70;

  int get _totalKcal =>
      (_carbGoal * _carbKcal + _proteinGoal * _proteinKcal + _fatGoal * _fatKcal)
          .round();

  int _activeMacroIndex = 1;
  int _addedMealCount = 0;

  List<MealEntry> _meals = [];

  @override
  void initState() {
    super.initState();
    _loadFromStorage();
  }

  void _loadFromStorage() {
    setState(() {
      _meals = StorageService.loadMeals();
      _carbGoal = StorageService.loadCarbGoal();
      _proteinGoal = StorageService.loadProteinGoal();
      _fatGoal = StorageService.loadFatGoal();
      _addedMealCount = StorageService.loadAddedMealCount();
    });
  }

  static double _macroPercent(double value, double target) {
    if (target == 0) return 0;
    return (value / target).clamp(0.0, 1.0) * 100;
  }

  void _addMeal() {
    setState(() {
      _addedMealCount++;
      _meals.add(MealEntry(name: '추가 식사 $_addedMealCount'));
      StorageService.saveMeals(_meals);
      StorageService.saveAddedMealCount(_addedMealCount);
    });
  }

  Future<void> _openGoalEdit() async {
    final result = await Navigator.push<GoalData>(
      context,
      MaterialPageRoute(
        builder: (_) => GoalEditPage(
          initial: GoalData(
            carb: _carbGoal,
            protein: _proteinGoal,
            fat: _fatGoal,
          ),
        ),
      ),
    );
    if (result != null) {
      setState(() {
        _carbGoal = result.carb;
        _proteinGoal = result.protein;
        _fatGoal = result.fat;
      });
      StorageService.saveGoals(
        carb: result.carb,
        protein: result.protein,
        fat: result.fat,
      );
    }
  }

  Future<void> _openFoodSearch(int index) async {
    final result = await Navigator.push<List<FoodRecord>>(
      context,
      MaterialPageRoute(
        builder: (_) => FoodSearchPage(
          mealName: _meals[index].name,
          initialFoods: _meals[index].foods,
        ),
      ),
    );
    if (result != null) {
      setState(() {
        _meals[index] = _meals[index].copyWith(foods: result);
      });
      StorageService.saveMeals(_meals);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 모든 식사에서 합산한 매크로
    final totalCarb = _meals.fold<double>(
        0, (sum, m) => sum + m.foods.fold(0, (s, f) => s + f.carb));
    final totalProtein = _meals.fold<double>(
        0, (sum, m) => sum + m.foods.fold(0, (s, f) => s + f.protein));
    final totalFat = _meals.fold<double>(
        0, (sum, m) => sum + m.foods.fold(0, (s, f) => s + f.fat));

    final data = MacroData(
      carb: totalCarb,
      protein: totalProtein,
      fat: totalFat,
      totalKcal: _totalKcal,
      burnedKcal: burnedKcal,
    );

    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DashboardCard(
                    data: data,
                    totalKcal: _totalKcal,
                    carbGram: totalCarb,
                    proteinGram: totalProtein,
                    fatGram: totalFat,
                    burnedKcal: burnedKcal,
                    carbGoal: _carbGoal,
                    proteinGoal: _proteinGoal,
                    fatGoal: _fatGoal,
                    activeMacroIndex: _activeMacroIndex,
                    onMacroTap: (i) =>
                        setState(() => _activeMacroIndex = i),
                    macroPercent: _macroPercent,
                    onEditGoal: _openGoalEdit,
                  ),

                  const SizedBox(height: 28),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        '식사 기록',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.black,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _addMeal,
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
                    ],
                  ),

                  const SizedBox(height: 8),

                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _meals.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) => _MealItem(
                      meal: _meals[index],
                      onTap: () => _openFoodSearch(index),
                      onDelete: _meals[index].isFixed
                          ? null
                          : () {
                              setState(() => _meals.removeAt(index));
                              StorageService.saveMeals(_meals);
                            },
                    ),
                  ),

                  const SizedBox(height: 20),
                ],
              ),
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
  final double burnedKcal;
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
    required this.burnedKcal,
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
      padding: const EdgeInsets.fromLTRB(24, 16, 16, 24),
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
            blurRadius: 30,
            offset: Offset(0, 18),
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
                textStyle: const TextStyle(fontSize: 12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.tune, size: 14),
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

          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () => onMacroTap(0),
                child: _MacroBadge(
                  label: "탄",
                  percent: macroPercent(carbGram, carbGoal),
                  active: activeMacroIndex == 0,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => onMacroTap(1),
                child: _MacroBadge(
                  label: "단",
                  percent: macroPercent(proteinGram, proteinGoal),
                  active: activeMacroIndex == 1,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => onMacroTap(2),
                child: _MacroBadge(
                  label: "지",
                  percent: macroPercent(fatGram, fatGoal),
                  active: activeMacroIndex == 2,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                "${burnedKcal.toStringAsFixed(0)}kcal 소모",
                style: const TextStyle(color: _labelColor, fontSize: 13),
              ),
              const SizedBox(width: 8),
              Container(width: 1, height: 12, color: Colors.white30),
              const SizedBox(width: 8),
              Text(
                "${data.remainKcal.toStringAsFixed(0)}kcal 더 먹을 수 있어요",
                style: const TextStyle(
                  color: _remainColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),

          _MacroRow(
            title: "탄수화물",
            value: carbGram,
            target: carbGoal,
            color: _carbColor,
          ),
          const SizedBox(height: 16),
          _MacroRow(
            title: "단백질",
            value: proteinGram,
            target: proteinGoal,
            color: _proteinColor,
          ),
          const SizedBox(height: 16),
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
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _MealItem({
    required this.meal,
    required this.onTap,
    required this.onDelete,
  });

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('식사 삭제'),
        content: const Text('삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('아니오'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('예'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) onDelete?.call();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onDelete != null ? () => _confirmDelete(context) : null,
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
              meal.kcal > 0
                  ? '${meal.kcal.toStringAsFixed(0)} kcal'
                  : '- kcal',
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black45,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: Colors.black38, size: 20),
          ],
        ),
      ),
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
    final double ratio =
        target == 0 ? 0 : (value / target).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title,
                style: const TextStyle(color: Colors.white, fontSize: 13)),
            Text(
              "${value.toStringAsFixed(0)} / ${target.toStringAsFixed(0)}g",
              style: const TextStyle(color: _labelColor, fontSize: 13),
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
