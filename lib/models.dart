// --- 음식 기록 모델 ---
class FoodRecord {
  final String name;
  final double carb;
  final double protein;
  final double fat;
  /// 탄수화물 중 식이섬유(g). 직접 기록 등 칼로리를 탄단지로 계산할 때,
  /// 탄수화물 칼로리에서 이 양만큼을 뺀다(순탄수화물 기준).
  final double fiber;
  /// API에서 열량만 제공될 때(탄단지 없음) 표시용. 없으면 탄단지로 계산.
  final double? kcalOverride;

  /// 검색/API 기반 항목일 때 [FoodItem] 복원용 JSON. 없으면 직접 입력 등.
  final Map<String, dynamic>? sourceFoodItemJson;

  /// 기록 시점의 섭취량(g 또는 ml). 상세 화면 초기값으로 사용.
  final double? sourceLoggedAmount;

  const FoodRecord({
    required this.name,
    required this.carb,
    required this.protein,
    required this.fat,
    this.fiber = 0,
    this.kcalOverride,
    this.sourceFoodItemJson,
    this.sourceLoggedAmount,
  });

  /// 식이섬유를 뺀 순탄수화물(g). 음수가 되지 않도록 0으로 clamp.
  double get netCarb => carb - fiber < 0 ? 0 : carb - fiber;

  double get kcal =>
      kcalOverride ?? (netCarb * 4 + protein * 4 + fat * 9);

  Map<String, dynamic> toMap() => {
        'name': name,
        'carb': carb,
        'protein': protein,
        'fat': fat,
        if (fiber != 0) 'fiber': fiber,
        if (kcalOverride != null) 'kcalOverride': kcalOverride,
        if (sourceFoodItemJson != null) 'sourceFoodItemJson': sourceFoodItemJson,
        if (sourceLoggedAmount != null) 'sourceLoggedAmount': sourceLoggedAmount,
      };

  factory FoodRecord.fromMap(Map map) => FoodRecord(
        name: map['name'] as String,
        carb: (map['carb'] as num).toDouble(),
        protein: (map['protein'] as num).toDouble(),
        fat: (map['fat'] as num).toDouble(),
        fiber: (map['fiber'] as num?)?.toDouble() ?? 0,
        kcalOverride: map['kcalOverride'] != null
            ? (map['kcalOverride'] as num).toDouble()
            : null,
        sourceFoodItemJson: map['sourceFoodItemJson'] is Map
            ? Map<String, dynamic>.from(map['sourceFoodItemJson'] as Map)
            : null,
        sourceLoggedAmount: map['sourceLoggedAmount'] != null
            ? (map['sourceLoggedAmount'] as num).toDouble()
            : null,
      );
}

int _mealIdCounter = 0;

/// 세션 내에서 고유한 식사 id를 생성한다. Reorderable 리스트의 안정적인
/// Key로 쓰인다(이름은 사용자가 자유롭게 바꿀 수 있어 더 이상 고유하지 않음).
String _generateMealId() =>
    '${DateTime.now().microsecondsSinceEpoch}_${_mealIdCounter++}';

// --- 식사 항목 모델 ---
class MealEntry {
  final String id;
  final String name;
  final bool isFixed;
  /// 사용자가 이름을 직접 바꾼 항목인지. true면 "간식 N" 자동 번호매기기 대상에서 제외된다.
  final bool isCustomNamed;
  final List<FoodRecord> foods;

  MealEntry({
    String? id,
    required this.name,
    this.isFixed = false,
    this.isCustomNamed = false,
    this.foods = const [],
  }) : id = id ?? _generateMealId();

  double get kcal => foods.fold(0, (sum, f) => sum + f.kcal);

  MealEntry copyWith({
    String? name,
    bool? isCustomNamed,
    List<FoodRecord>? foods,
  }) =>
      MealEntry(
        id: id,
        name: name ?? this.name,
        isFixed: isFixed,
        isCustomNamed: isCustomNamed ?? this.isCustomNamed,
        foods: foods ?? this.foods,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'isFixed': isFixed,
        'isCustomNamed': isCustomNamed,
        'foods': foods.map((f) => f.toMap()).toList(),
      };

  factory MealEntry.fromMap(Map map) => MealEntry(
        id: map['id'] as String?,
        name: map['name'] as String,
        isFixed: map['isFixed'] as bool? ?? false,
        isCustomNamed: map['isCustomNamed'] as bool? ?? false,
        foods: (map['foods'] as List?)
                ?.map((f) => FoodRecord.fromMap(f as Map))
                .toList() ??
            [],
      );
}

// --- 사용자 정의 습관 알림 모델 ---
class HabitReminder {
  /// 생성 시각(ms) 기반 고유 id. 알림 예약 id 계산에도 쓰인다.
  final int id;
  final String name;
  final int hour;
  final int minute;
  /// DateTime.weekday 기준 (월=1 ... 일=7).
  final List<int> weekdays;
  final bool enabled;

  const HabitReminder({
    required this.id,
    required this.name,
    required this.hour,
    required this.minute,
    required this.weekdays,
    required this.enabled,
  });

  HabitReminder copyWith({
    String? name,
    int? hour,
    int? minute,
    List<int>? weekdays,
    bool? enabled,
  }) =>
      HabitReminder(
        id: id,
        name: name ?? this.name,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        weekdays: weekdays ?? this.weekdays,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'hour': hour,
        'minute': minute,
        'weekdays': weekdays,
        'enabled': enabled,
      };

  factory HabitReminder.fromMap(Map map) => HabitReminder(
        id: (map['id'] as num).toInt(),
        name: map['name'] as String? ?? '',
        hour: (map['hour'] as num?)?.toInt() ?? 9,
        minute: (map['minute'] as num?)?.toInt() ?? 0,
        weekdays: (map['weekdays'] as List?)
                ?.map((e) => (e as num).toInt())
                .toList() ??
            const [],
        enabled: map['enabled'] as bool? ?? true,
      );
}
