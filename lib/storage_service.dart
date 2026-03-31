import 'package:hive_flutter/hive_flutter.dart';
import 'models.dart';

class StorageService {
  static const _mealsBoxName = 'meals';
  static const _settingsBoxName = 'settings';

  static const _defaultMealNames = ['아침', '점심', '저녁'];

  // --- 초기화 ---
  static Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(_mealsBoxName);
    await Hive.openBox(_settingsBoxName);
  }

  // --- 식사 목록 ---
  static List<MealEntry> loadMeals() {
    final box = Hive.box(_mealsBoxName);

    if (box.isEmpty) {
      // 처음 실행 시 기본값 저장
      final defaults = _defaultMealNames
          .map((n) => MealEntry(name: n, isFixed: true))
          .toList();
      _saveMealsToBox(box, defaults);
      return defaults;
    }

    final raw = box.get('list') as List?;
    if (raw == null) return [];
    return raw.map((e) => MealEntry.fromMap(e as Map)).toList();
  }

  static void saveMeals(List<MealEntry> meals) {
    final box = Hive.box(_mealsBoxName);
    _saveMealsToBox(box, meals);
  }

  static void _saveMealsToBox(Box box, List<MealEntry> meals) {
    box.put('list', meals.map((m) => m.toMap()).toList());
  }

  // --- 목표 수치 ---
  static double loadCarbGoal() =>
      (Hive.box(_settingsBoxName).get('carbGoal', defaultValue: 410.0) as num)
          .toDouble();

  static double loadProteinGoal() =>
      (Hive.box(_settingsBoxName)
              .get('proteinGoal', defaultValue: 140.0) as num)
          .toDouble();

  static double loadFatGoal() =>
      (Hive.box(_settingsBoxName).get('fatGoal', defaultValue: 70.0) as num)
          .toDouble();

  static void saveGoals({
    required double carb,
    required double protein,
    required double fat,
  }) {
    final box = Hive.box(_settingsBoxName);
    box.put('carbGoal', carb);
    box.put('proteinGoal', protein);
    box.put('fatGoal', fat);
  }

  // --- 추가 식사 카운터 ---
  static int loadAddedMealCount() =>
      Hive.box(_settingsBoxName).get('addedMealCount', defaultValue: 0) as int;

  static void saveAddedMealCount(int count) =>
      Hive.box(_settingsBoxName).put('addedMealCount', count);
}
