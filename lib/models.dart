// --- 음식 기록 모델 ---
class FoodRecord {
  final String name;
  final double carb;
  final double protein;
  final double fat;

  const FoodRecord({
    required this.name,
    required this.carb,
    required this.protein,
    required this.fat,
  });

  double get kcal => carb * 4 + protein * 4 + fat * 9;

  Map<String, dynamic> toMap() => {
        'name': name,
        'carb': carb,
        'protein': protein,
        'fat': fat,
      };

  factory FoodRecord.fromMap(Map map) => FoodRecord(
        name: map['name'] as String,
        carb: (map['carb'] as num).toDouble(),
        protein: (map['protein'] as num).toDouble(),
        fat: (map['fat'] as num).toDouble(),
      );
}

// --- 식사 항목 모델 ---
class MealEntry {
  final String name;
  final bool isFixed;
  final List<FoodRecord> foods;

  const MealEntry({
    required this.name,
    this.isFixed = false,
    this.foods = const [],
  });

  double get kcal => foods.fold(0, (sum, f) => sum + f.kcal);

  MealEntry copyWith({List<FoodRecord>? foods}) => MealEntry(
        name: name,
        isFixed: isFixed,
        foods: foods ?? this.foods,
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'isFixed': isFixed,
        'foods': foods.map((f) => f.toMap()).toList(),
      };

  factory MealEntry.fromMap(Map map) => MealEntry(
        name: map['name'] as String,
        isFixed: map['isFixed'] as bool? ?? false,
        foods: (map['foods'] as List?)
                ?.map((f) => FoodRecord.fromMap(f as Map))
                .toList() ??
            [],
      );
}
