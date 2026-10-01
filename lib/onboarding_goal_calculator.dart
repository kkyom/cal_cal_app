import 'onboarding_screen.dart';
import 'goal_edit_screen.dart';
import 'nutrition_calculator.dart';

/// 순수 계산만 한다. 저장(목표일·목표 수치)은 호출부에서
/// [FirestoreService.completeOnboarding]로 한 번에 처리한다.
GoalData calculateGoalsFromOnboarding(OnboardingResult r) {
  final today = DateTime.now();
  final targets = NutritionCalculator.calculate(
    gender: r.gender,
    ageYears: r.ageYears,
    heightCm: r.heightCm,
    currentWeightKg: r.startWeightKg,
    goalWeightKg: r.goalWeightKg,
    activityMultiplier: NutritionCalculator.activityMultiplierFrom(r.activity),
    purpose: r.purpose,
    goalDate: r.goalDate,
    today: today,
  );

  return GoalData(
    carb: targets.carbGrams.roundToDouble(),
    protein: targets.proteinGrams.roundToDouble(),
    fat: targets.fatGrams.roundToDouble(),
  );
}
