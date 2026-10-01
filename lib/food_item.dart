import 'models.dart';

// 공공데이터 식품영양성분DB 매핑 (출력메세지 엑셀 기준):
// AMT_NUM1=에너지(kcal), AMT_NUM3=단백질(g), AMT_NUM4=지방(g),
// AMT_NUM6=탄수화물(g), AMT_NUM8=식이섬유(g)
// SERVING_SIZE=영양성분함량기준량(보통 100g/100ml), Z10500=식품중량(상품 1개)

/// 공공데이터 API 응답 한 건을 나타내는 검색용 모델.
class FoodItem {
  final String name;

  /// 브랜드/제조사 표시명 (없으면 빈 문자열)
  final String brand;

  /// 상품 1개 용량 라벨 (예: "130g", "354ml") — 식품중량 우선
  final String rawServingSize;

  /// 기본 섭취량 숫자 (상품 1개 용량)
  final double servingAmount;

  /// 파싱된 단위 문자열 ("g" 또는 "ml")
  final String servingUnit;

  /// [servingAmount] 기준 영양소 값
  final double kcal;
  final double carb;
  final double protein;
  final double fat;
  final double fiber;

  /// 1단위(1g 또는 1ml)당 영양소 — 비례식 계산용
  final double kcalPerUnit;
  final double carbPerUnit;
  final double proteinPerUnit;
  final double fatPerUnit;
  final double fiberPerUnit;

  FoodItem._({
    required this.name,
    this.brand = '',
    required this.rawServingSize,
    required this.servingAmount,
    required this.servingUnit,
    required this.kcal,
    required this.carb,
    required this.protein,
    required this.fat,
    required this.fiber,
    required this.kcalPerUnit,
    required this.carbPerUnit,
    required this.proteinPerUnit,
    required this.fatPerUnit,
    required this.fiberPerUnit,
  });

  // ── 비례 계산 ──────────────────────────────────────────────
  double kcalFor(double amount) => kcalPerUnit * amount;
  double carbFor(double amount) => carbPerUnit * amount;
  double proteinFor(double amount) => proteinPerUnit * amount;
  double fatFor(double amount) => fatPerUnit * amount;
  double fiberFor(double amount) => fiberPerUnit * amount;

  /// 입력 섭취량을 기반으로 기록용 [FoodRecord]를 생성
  FoodRecord toRecord(double amount) => FoodRecord(
        name: name,
        carb: carbFor(amount),
        protein: proteinFor(amount),
        fat: fatFor(amount),
        kcalOverride: kcalFor(amount),
        sourceFoodItemJson: toJson(),
        sourceLoggedAmount: amount,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'brand': brand,
        'rawServingSize': rawServingSize,
        'servingAmount': servingAmount,
        'servingUnit': servingUnit,
        'kcal': kcal,
        'carb': carb,
        'protein': protein,
        'fat': fat,
        'fiber': fiber,
        'kcalPerUnit': kcalPerUnit,
        'carbPerUnit': carbPerUnit,
        'proteinPerUnit': proteinPerUnit,
        'fatPerUnit': fatPerUnit,
        'fiberPerUnit': fiberPerUnit,
      };

  factory FoodItem.fromJson(Map<String, dynamic> m) {
    double d(String k) => _toDouble(m[k]);
    return FoodItem._(
      name: (m['name'] ?? '').toString(),
      brand: (m['brand'] ?? '').toString(),
      rawServingSize: (m['rawServingSize'] ?? '').toString(),
      servingAmount: d('servingAmount'),
      servingUnit: (m['servingUnit'] ?? 'g').toString(),
      kcal: d('kcal'),
      carb: d('carb'),
      protein: d('protein'),
      fat: d('fat'),
      fiber: d('fiber'),
      kcalPerUnit: d('kcalPerUnit'),
      carbPerUnit: d('carbPerUnit'),
      proteinPerUnit: d('proteinPerUnit'),
      fatPerUnit: d('fatPerUnit'),
      fiberPerUnit: d('fiberPerUnit'),
    );
  }

  /// 기록된 [FoodRecord]로부터 상세 화면용 [FoodItem]을 만든다.
  /// API 스냅샷이 있으면 그대로 복원한다. 없으면(직접 기록 등) 실제 섭취량
  /// ([FoodRecord.sourceLoggedAmount])을 기준으로 역산하고, 섭취량을 모르는
  /// 옛 기록은 100g 가상 모델로 대체한다.
  factory FoodItem.fromFoodRecord(FoodRecord r) {
    if (r.sourceFoodItemJson != null && r.sourceFoodItemJson!.isNotEmpty) {
      return FoodItem.fromJson(r.sourceFoodItemJson!);
    }
    final base = (r.sourceLoggedAmount != null && r.sourceLoggedAmount! > 0)
        ? r.sourceLoggedAmount!
        : 100.0;
    final k = r.kcal;
    final c = r.carb;
    final p = r.protein;
    final f = r.fat;
    final fb = r.fiber;
    return FoodItem._(
      name: r.name,
      rawServingSize: formatServingLabel(base, 'g'),
      servingAmount: base,
      servingUnit: 'g',
      kcal: k,
      carb: c,
      protein: p,
      fat: f,
      fiber: fb,
      kcalPerUnit: k / base,
      carbPerUnit: c / base,
      proteinPerUnit: p / base,
      fatPerUnit: f / base,
      fiberPerUnit: fb / base,
    );
  }

  /// [FoodItem.fromFoodRecord]와 같지만, 기록 당시 실제 섭취량
  /// ([FoodRecord.sourceLoggedAmount])을 "1단위" 기준으로 삼는다.
  /// "마이 식단"에 저장할 때, 나중에 다시 열었을 때 기본값이 실제 먹은 양과
  /// 같도록 하기 위해 쓴다.
  factory FoodItem.fromFoodRecordAtLoggedAmount(FoodRecord r) {
    final base = FoodItem.fromFoodRecord(r);
    final amount = r.sourceLoggedAmount;
    if (amount == null || amount <= 0 || amount == base.servingAmount) {
      return base;
    }
    return FoodItem._(
      name: base.name,
      brand: base.brand,
      rawServingSize: formatServingLabel(amount, base.servingUnit),
      servingAmount: amount,
      servingUnit: base.servingUnit,
      kcal: base.kcalPerUnit * amount,
      carb: base.carbPerUnit * amount,
      protein: base.proteinPerUnit * amount,
      fat: base.fatPerUnit * amount,
      fiber: base.fiberPerUnit * amount,
      kcalPerUnit: base.kcalPerUnit,
      carbPerUnit: base.carbPerUnit,
      proteinPerUnit: base.proteinPerUnit,
      fatPerUnit: base.fatPerUnit,
      fiberPerUnit: base.fiberPerUnit,
    );
  }

  // ── SERVING_SIZE / 식품중량 파싱 ───────────────────────────
  /// "100g", "100 G", "200ml", "100mL", "130.000g", "100" 형태 처리.
  /// 단위가 없으면 기본 "g", 숫자가 없거나 0이면 기본 100g.
  static ({double amount, String unit}) parseServingSize(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return (amount: 100, unit: 'g');

    final match = RegExp(
      r'([0-9]+(?:[.,][0-9]+)?)\s*(ml|mL|ML|㎖|g|G|그램)?',
      caseSensitive: false,
    ).firstMatch(s);
    if (match == null) return (amount: 100, unit: 'g');

    final numStr = match.group(1)!.replaceAll(',', '.');
    final amount = double.tryParse(numStr) ?? 100;
    final rawUnit = (match.group(2) ?? '').toLowerCase();
    final unit = (rawUnit == 'ml' || rawUnit == '㎖') ? 'ml' : 'g';

    return (amount: amount > 0 ? amount : 100, unit: unit);
  }

  static String formatServingLabel(double amount, String unit) {
    final a = (amount - amount.round()).abs() < 0.05
        ? amount.round().toString()
        : amount.toStringAsFixed(1);
    return '$a$unit';
  }

  // ── 팩토리 ───────────────────────────────────────────────
  factory FoodItem.fromApiRow(Map<dynamic, dynamic> map, String fallback) {
    double field(List<String> keys) => _toDouble(_get(map, keys));
    String str(List<String> keys) =>
        (_get(map, keys) ?? '').toString().trim();

    /// 빈 문자열·null 표기는 건너뛰고 첫 유효 값.
    String firstStr(List<String> keys) {
      for (final k in keys) {
        final v = str([k]);
        if (v.isEmpty) continue;
        if (v.toLowerCase() == 'null' || v == '-') continue;
        return v;
      }
      return '';
    }

    final name = str(const ['FOOD_NM_KR', 'DESC_KOR', 'PRDLST_NM', 'RCP_NM']);
    // 식약처 DB 원본 표기("달걀_난백_삶은것" 등)의 "_"는 화면에 그대로
    // 노출하지 않는다.
    final cleanedName = name
        .replaceAll('_', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final displayName = cleanedName.isNotEmpty ? cleanedName : fallback;

    final brand = firstStr(const ['BRAND_DISPLAY', 'MAKER_NM', 'MAKER_NAME']);

    // SERVING_SIZE = 영양성분함량기준량 (보통 100g/100ml). AMT_NUM* 값의 기준.
    final rawNutrientBasis = firstStr(const [
      'SERVING_SIZE',
      'serving_size',
      'SERVING_WT',
      'SERVING_WGT',
    ]);
    final nutrientBasis = parseServingSize(rawNutrientBasis);
    final basisAmount =
        nutrientBasis.amount > 0 ? nutrientBasis.amount : 100.0;

    // Z10500 = 식품중량(상품 1개 용량). 없으면 1회 섭취/분량 참고량.
    final rawProduct = firstStr(const [
      'Z10500',
      'NUTRI_AMOUNT_SERVING',
      'DISH_ONE_SERVING',
    ]);
    final hasProduct = rawProduct.isNotEmpty;
    var product = hasProduct
        ? parseServingSize(rawProduct)
        : nutrientBasis;

    // 음료 등: 기준은 ml인데 식품중량만 g로 오는 경우 → 용량 단위는 ml로 표시.
    var productUnit = product.unit;
    if (nutrientBasis.unit == 'ml' && product.unit == 'g') {
      productUnit = 'ml';
    }

    final kcal = field(const ['AMT_NUM1', 'NUTR_CONT1', 'ENERC_KCAL', 'KCAL']);
    final carb = field(const ['AMT_NUM6', 'NUTR_CONT2']);
    final protein = field(const ['AMT_NUM3', 'NUTR_CONT3']);
    final fat = field(const ['AMT_NUM4', 'NUTR_CONT4']);
    final fiber = field(const ['AMT_NUM8', 'NUTR_CONT5']);

    final kcalPerUnit = kcal / basisAmount;
    final carbPerUnit = carb / basisAmount;
    final proteinPerUnit = protein / basisAmount;
    final fatPerUnit = fat / basisAmount;
    final fiberPerUnit = fiber / basisAmount;

    final servingAmount = product.amount > 0 ? product.amount : basisAmount;
    final servingLabel = formatServingLabel(servingAmount, productUnit);

    return FoodItem._(
      name: displayName,
      brand: brand,
      rawServingSize: servingLabel,
      servingAmount: servingAmount,
      servingUnit: productUnit,
      // 목록·상세 기본 표시는 상품 1개(식품중량) 기준 영양
      kcal: kcalPerUnit * servingAmount,
      carb: carbPerUnit * servingAmount,
      protein: proteinPerUnit * servingAmount,
      fat: fatPerUnit * servingAmount,
      fiber: fiberPerUnit * servingAmount,
      kcalPerUnit: kcalPerUnit,
      carbPerUnit: carbPerUnit,
      proteinPerUnit: proteinPerUnit,
      fatPerUnit: fatPerUnit,
      fiberPerUnit: fiberPerUnit,
    );
  }
}

/// "마이 식단"에 저장된 즐겨찾는 음식 한 건 — [FoodItem] 스냅샷 + 삭제용 id.
class MyDietItem {
  final String id;
  final FoodItem food;

  const MyDietItem({required this.id, required this.food});

  Map<String, dynamic> toMap() => {'id': id, 'food': food.toJson()};

  factory MyDietItem.fromMap(Map map) => MyDietItem(
        id: (map['id'] ?? '').toString(),
        food: FoodItem.fromJson(
          Map<String, dynamic>.from(map['food'] as Map),
        ),
      );

  /// 같은 음식인지 — 이름·단위·단위당 영양으로 판별 (검색 결과 병합 로직과 동일 기준).
  static bool sameFood(FoodItem a, FoodItem b) {
    bool numEq(double x, double y) => (x - y).abs() < 1e-6;
    return a.name == b.name &&
        a.servingUnit == b.servingUnit &&
        numEq(a.kcalPerUnit, b.kcalPerUnit) &&
        numEq(a.carbPerUnit, b.carbPerUnit) &&
        numEq(a.proteinPerUnit, b.proteinPerUnit) &&
        numEq(a.fatPerUnit, b.fatPerUnit);
  }
}

// ── 내부 헬퍼 ──────────────────────────────────────────────

double _toDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  final s = v.toString().trim().replaceAll(',', '.');
  if (s.isEmpty) return 0;
  return double.tryParse(s) ?? 0;
}

Map<String, dynamic> _stringKeyMap(Map map) => {
      for (final e in map.entries) e.key.toString(): e.value,
    };

dynamic _get(Map map, List<String> keys) {
  final sm = _stringKeyMap(map);
  final lower = {for (final e in sm.entries) e.key.toLowerCase(): e.value};
  for (final k in keys) {
    if (sm.containsKey(k)) return sm[k];
    if (lower.containsKey(k.toLowerCase())) return lower[k.toLowerCase()];
  }
  return null;
}
