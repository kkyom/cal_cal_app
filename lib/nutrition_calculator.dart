import 'onboarding_screen.dart';

class NutritionTargets {
  final DateTime today;
  final DateTime goalDate;

  final double bmr;
  final double tdee;
  final double targetCalories;

  final double carbGrams;
  final double proteinGrams;
  final double fatGrams;

  /// 단백질 상한(체중 1kg당 2.2g)이 적용되어 잉여 칼로리를
  /// 탄수/지방으로 재배분했는지 여부.
  final bool proteinCapped;

  const NutritionTargets({
    required this.today,
    required this.goalDate,
    required this.bmr,
    required this.tdee,
    required this.targetCalories,
    required this.carbGrams,
    required this.proteinGrams,
    required this.fatGrams,
    this.proteinCapped = false,
  });
}

class NutritionCalculator {
  static const double kcalPerKg = 7700;
  static const double carbKcalPerG = 4;
  static const double proteinKcalPerG = 4;
  static const double fatKcalPerG = 9;

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// 목적별 권장 주간 체중 변화량(kg/주).
  /// 감량(다이어트·키토)은 0.5, 증량은 목적에 따라 더 완만하게 잡는다.
  static double recommendedWeeklyRateKg(OnboardingPurpose purpose) =>
      switch (purpose) {
        OnboardingPurpose.diet => 0.3,
        OnboardingPurpose.ketogenic => 0.3,
        OnboardingPurpose.maintain => 0.5,
        OnboardingPurpose.leanMass => 0.3,
        OnboardingPurpose.bulk => 0.4,
      };

  /// Spec 2) 권장 목표 날짜 기본값
  /// 권장 소요 일수 = (|현재-목표| / 목적별 주간율) * 7
  static DateTime recommendedGoalDate({
    required DateTime today,
    required double currentWeightKg,
    required double goalWeightKg,
    required OnboardingPurpose purpose,
  }) {
    final t = dateOnly(today);
    final diffKg = (currentWeightKg - goalWeightKg).abs();
    final weeklyRate = recommendedWeeklyRateKg(purpose);
    final recommendedDays = ((diffKg / weeklyRate) * 7).round();
    return t.add(Duration(days: recommendedDays));
  }

  /// Spec 3) BMR 및 TDEE (Mifflin-St Jeor)
  static double bmrMifflinStJeor({
    required OnboardingGender gender,
    required int ageYears,
    required double heightCm,
    required double weightKg,
  }) {
    final sexConstant = switch (gender) {
      OnboardingGender.male => 5,
      OnboardingGender.female => -161,
    };
    return (10 * weightKg) + (6.25 * heightCm) - (5 * ageYears) + sexConstant;
  }

  /// Spec 4) 일일 목표 칼로리 (Dynamic Calculation)
  static NutritionTargets calculate({
    required OnboardingGender gender,
    required int ageYears,
    required double heightCm,
    required double currentWeightKg,
    required double goalWeightKg,
    required double activityMultiplier,
    required OnboardingPurpose purpose,
    required DateTime goalDate,
    DateTime? today,
  }) {
    final now = dateOnly(today ?? DateTime.now());
    final goal = dateOnly(goalDate);

    final bmr = bmrMifflinStJeor(
      gender: gender,
      ageYears: ageYears,
      heightCm: heightCm,
      weightKg: currentWeightKg,
    );
    final tdee = bmr * activityMultiplier;

    // 남은 일수 = 목표 날짜 - 오늘 날짜
    final remainingDays = goal.difference(now).inDays;
    final safeRemainingDays = remainingDays <= 0 ? 1 : remainingDays;

    // 일일 조절 칼로리 = (|현재-목표| * 7700) / 남은 일수
    final diffKg = (currentWeightKg - goalWeightKg).abs();
    final dailyAdjustCalories = (diffKg * kcalPerKg) / safeRemainingDays;

    double targetCalories = switch (purpose) {
      OnboardingPurpose.maintain => tdee,
      OnboardingPurpose.diet || OnboardingPurpose.ketogenic =>
        tdee - dailyAdjustCalories,
      OnboardingPurpose.leanMass || OnboardingPurpose.bulk =>
        tdee + dailyAdjustCalories,
    };

    // [안전장치] 다이어트/키토제닉은 BMR 하한
    if ((purpose == OnboardingPurpose.diet ||
            purpose == OnboardingPurpose.ketogenic) &&
        targetCalories < bmr) {
      targetCalories = bmr;
    }

    // Spec 5) Macro Split (ratio) -> grams
    // UI 라벨과 동일 소스(`macroRatioParts`)를 쓴다. 린매스업은 4:4:2.
    final (cRatio, pRatio, fRatio) = macroRatioParts(purpose);
    final ratioSum = cRatio + pRatio + fRatio;

    double carbCalories = targetCalories * (cRatio / ratioSum);
    double proteinCalories = targetCalories * (pRatio / ratioSum);
    double fatCalories = targetCalories * (fRatio / ratioSum);

    double carbGrams = carbCalories / carbKcalPerG;
    double proteinGrams = proteinCalories / proteinKcalPerG;
    double fatGrams = fatCalories / fatKcalPerG;

    // Protein Max Cap: 최대 현재체중(kg) * 2.2g
    // 상한으로 깎인 잉여 칼로리는 탄수/지방에 원래 비율(cRatio:fRatio)대로 분배한다.
    final double proteinMaxGrams = currentWeightKg * 2.2;
    bool proteinCapped = false;
    if (proteinGrams > proteinMaxGrams) {
      proteinCapped = true;
      final double originalProteinCalories = proteinCalories;
      proteinGrams = proteinMaxGrams;
      proteinCalories = proteinGrams * proteinKcalPerG;

      final double surplusCalories = originalProteinCalories - proteinCalories;
      final double carbFatRatioSum = cRatio + fRatio;
      if (carbFatRatioSum > 0) {
        carbCalories += surplusCalories * (cRatio / carbFatRatioSum);
        fatCalories += surplusCalories * (fRatio / carbFatRatioSum);
      } else {
        carbCalories += surplusCalories;
      }
      carbGrams = carbCalories / carbKcalPerG;
      fatGrams = fatCalories / fatKcalPerG;
    }

    return NutritionTargets(
      today: now,
      goalDate: goal,
      bmr: bmr,
      tdee: tdee,
      targetCalories: targetCalories,
      carbGrams: carbGrams,
      proteinGrams: proteinGrams,
      fatGrams: fatGrams,
      proteinCapped: proteinCapped,
    );
  }

  static double activityMultiplierFrom(OnboardingActivity activity) =>
      switch (activity) {
        OnboardingActivity.veryLow => 1.2,
        OnboardingActivity.low => 1.375,
        OnboardingActivity.normal => 1.55,
        OnboardingActivity.high => 1.725,
        OnboardingActivity.veryHigh => 1.9,
      };

  /// `calculate`와 동일한 탄:단:지 비율(가중치). UI 표시용
  static (double c, double p, double f) macroRatioParts(
    OnboardingPurpose purpose,
  ) {
    return switch (purpose) {
      OnboardingPurpose.diet => (4.0, 4.0, 2.0),
      OnboardingPurpose.maintain => (5.0, 3.0, 2.0),
      OnboardingPurpose.leanMass => (4.0, 4.0, 2.0),
      OnboardingPurpose.bulk => (5.0, 3.0, 2.0),
      OnboardingPurpose.ketogenic => (0.5, 2.5, 7.0),
    };
  }

  /// 점검 화면용 권장 페이스 안내 문구.
  static String recommendedPaceLabel(OnboardingPurpose purpose) {
    final rate = recommendedWeeklyRateKg(purpose);
    final direction = switch (purpose) {
      OnboardingPurpose.leanMass || OnboardingPurpose.bulk => '증량',
      OnboardingPurpose.diet || OnboardingPurpose.ketogenic => '감량',
      OnboardingPurpose.maintain => '변화',
    };
    return '일주일에 ${rate}kg $direction을 기준으로 잡았어요';
  }

  static String macroRatioLabel(OnboardingPurpose purpose) {
    final (c, p, f) = macroRatioParts(purpose);
    String fmt(double x) =>
        x == x.roundToDouble() ? x.toInt().toString() : x.toString();
    return '${fmt(c)}:${fmt(p)}:${fmt(f)}';
  }
}

