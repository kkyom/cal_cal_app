/// 한국 가공식품 영양성분표의 OCR 텍스트에서 탄수화물·단백질·지방·열량을 뽑아낸다.

/// 라벨 문구가 `열량`, `탄수화물`, `단백질`, `지방`으로 사실상 표준화돼 있어
/// 온디바이스 OCR 결과만으로 파싱. 외부 API 호출은 없음
library;

/// 영양성분 값이 어떤 양을 기준으로 적혀 있는지 나타내는 후보.
///
/// 예) `총 내용량 200g`, `1회 제공량 30g`, `100g당`, `1개당`.
class NutritionBasis {
  final String label;
  final double amount;

  /// `g` / `ml` 또는 낱개 단위(`개`, `봉`, `포` 등).
  final String unit;

  const NutritionBasis({
    required this.label,
    required this.amount,
    required this.unit,
  });

  String get display {
    // 낱개 1개 기준이면 "1개당 1개" 대신 "1개당"만 보여준다.
    if (amount == 1 && _pieceUnits.contains(unit) && label.endsWith('당')) {
      return label;
    }
    return '$label ${formatLabelNumber(amount)}$unit';
  }

  @override
  bool operator ==(Object other) =>
      other is NutritionBasis &&
      other.label == label &&
      other.amount == amount &&
      other.unit == unit;

  @override
  int get hashCode => Object.hash(label, amount, unit);

  @override
  String toString() => 'NutritionBasis($display)';
}

/// 영양성분표 OCR 파싱 결과. 인식되지 않은 항목은 null.
///
/// [carb]는 표의 총 탄수화물이 아니라, 식이섬유가 인식되면
/// `(탄수화물 - 식이섬유)`로 보정한 값이다.
///
/// 표 상단에 `100g당 …kcal`이 있으면 [isPerHundred]가 true이고,
/// `1개당`/`1봉당` 등이 있으면 [isPerPiece]가 true이다.
/// 둘 다 없으면 성분 수치는 총 내용량 기준이다.
class NutritionLabelReading {
  final double? kcal;
  final double? carb;
  final double? protein;
  final double? fat;

  /// 표에 적힌 식이섬유. [carb] 보정에만 쓰고 UI에는 노출하지 않는다.
  final double? fiber;

  /// 표의 탄단지·열량이 대응하는 기준량.
  final NutritionBasis? nutrientBasis;

  /// 상품 총 내용량. `100g당`/낱개 기준 표에서는 [nutrientBasis]와 별개로 보관한다.
  final NutritionBasis? totalContent;

  /// 표 상단에 `100g당`/`100ml당` 표기가 있어 수치가 100 단위 기준인지.
  final bool isPerHundred;

  /// `1개당`/`1봉당`/`1포당` 등 낱개 기준인지.
  final bool isPerPiece;

  /// 라벨/포장에서 읽힌 제품명. 없으면 null.
  final String? productName;

  const NutritionLabelReading({
    this.kcal,
    this.carb,
    this.protein,
    this.fat,
    this.fiber,
    this.nutrientBasis,
    this.totalContent,
    this.isPerHundred = false,
    this.isPerPiece = false,
    this.productName,
  });

  static const NutritionLabelReading empty = NutritionLabelReading();

  /// 기준량 — UI의 기준량 필드에 채울 값.
  NutritionBasis? get basis => nutrientBasis;

  bool get hasAnyMacro => carb != null || protein != null || fat != null;

  int get recognizedMacroCount =>
      (carb != null ? 1 : 0) + (protein != null ? 1 : 0) + (fat != null ? 1 : 0);

  /// 탄단지로부터 역산한 열량(4/4/9 kcal per g). 표에 열량이 없을 때만
  /// 최후 수단으로 쓴다.
  double? get estimatedKcal {
    if (!hasAnyMacro) return null;
    final total = (carb ?? 0) * 4 + (protein ?? 0) * 4 + (fat ?? 0) * 9;
    return total > 0 ? total : null;
  }

  /// 이 결과에서 비어 있는 항목만 [other]로 채운 새 결과를 만든다.
  /// (Gemini가 kcal 등 일부를 못 읽었을 때 ML Kit 결과로 보완하는 용도.)
  NutritionLabelReading mergeMissing(NutritionLabelReading other) {
    return NutritionLabelReading(
      kcal: kcal ?? other.kcal,
      carb: carb ?? other.carb,
      protein: protein ?? other.protein,
      fat: fat ?? other.fat,
      fiber: fiber ?? other.fiber,
      nutrientBasis: nutrientBasis ?? other.nutrientBasis,
      totalContent: totalContent ?? other.totalContent,
      isPerHundred: isPerHundred,
      isPerPiece: isPerPiece,
      productName: productName ?? other.productName,
    );
  }

  NutritionLabelReading copyWith({double? kcal}) {
    return NutritionLabelReading(
      kcal: kcal ?? this.kcal,
      carb: carb,
      protein: protein,
      fat: fat,
      fiber: fiber,
      nutrientBasis: nutrientBasis,
      totalContent: totalContent,
      isPerHundred: isPerHundred,
      isPerPiece: isPerPiece,
      productName: productName,
    );
  }

  /// Gemini 등 AI 구조화 응답을 앱 모델로 변환한다.
  ///
  /// [carb] 입력은 표에 적힌 총 탄수화물로 보고, 식이섬유가 있으면
  /// `(탄수화물 - 식이섬유)`로 보정한다.
  factory NutritionLabelReading.fromAiMap(Map<dynamic, dynamic> raw) {
    final m = <String, dynamic>{
      for (final e in raw.entries) e.key.toString(): e.value,
    };

    double? numOf(String key) {
      final v = m[key];
      if (v == null) return null;
      if (v is num) {
        final d = v.toDouble();
        if (d.isNaN || d.isInfinite || d < 0) return null;
        return d;
      }
      // "250kcal", "약 250 kcal", "100 g"처럼 단위·접두어가 붙어 와도
      // 첫 숫자만 뽑는다.
      final s = v.toString().trim().replaceAll(',', '.');
      if (s.isEmpty || s.toLowerCase() == 'null') return null;
      final match = RegExp(r'\d+(?:\.\d+)?').firstMatch(s);
      if (match == null) return null;
      final d = double.tryParse(match.group(0)!);
      if (d == null || d.isNaN || d.isInfinite || d < 0) return null;
      return d;
    }

    String? unitOf(String key) {
      final u = (m[key] ?? '').toString().trim().toLowerCase();
      if (u == 'ml' || u == '㎖') return 'ml';
      if (u == 'g' || u == '그램') return 'g';
      if (_pieceUnits.contains(u)) return u;
      return null;
    }

    final fiber = numOf('fiber');
    final rawCarb = numOf('carb');
    final carb = rawCarb == null
        ? null
        : fiber == null
            ? rawCarb
            : (rawCarb - fiber).clamp(0, double.infinity).toDouble();

    final isPerHundred = m['isPerHundred'] == true ||
        m['isPerHundred']?.toString().toLowerCase() == 'true';
    final isPerPiece = !isPerHundred &&
        (m['isPerPiece'] == true ||
            m['isPerPiece']?.toString().toLowerCase() == 'true');

    final basisLabelRaw = (m['basisLabel'] ?? '').toString().trim();
    final basisUnit = unitOf('basisUnit') ??
        (isPerHundred
            ? 'g'
            : isPerPiece
                ? '개'
                : null);
    final basisAmount = numOf('basisAmount') ??
        (isPerHundred
            ? 100.0
            : isPerPiece
                ? 1.0
                : null);

    NutritionBasis? nutrientBasis;
    if (basisAmount != null && basisAmount > 0 && basisUnit != null) {
      final label = isPerHundred
          ? '100$basisUnit당'
          : isPerPiece
              ? (basisLabelRaw.isNotEmpty ? basisLabelRaw : '1$basisUnit당')
              : (basisLabelRaw.isNotEmpty ? basisLabelRaw : '기준량');
      nutrientBasis = NutritionBasis(
        label: label,
        amount: isPerHundred ? 100 : basisAmount,
        unit: basisUnit,
      );
    }

    final totalAmount = numOf('totalContentAmount');
    final totalUnit = unitOf('totalContentUnit') ??
        (basisUnit == 'g' || basisUnit == 'ml' ? basisUnit : 'g');
    NutritionBasis? totalContent;
    if (totalAmount != null &&
        totalAmount > 0 &&
        totalUnit != null &&
        (totalUnit == 'g' || totalUnit == 'ml')) {
      totalContent = NutritionBasis(
        label: '총 내용량',
        amount: totalAmount,
        unit: totalUnit,
      );
    }

    // 100g당·낱개 기준이 아니면 기준량이 비었을 때 총 내용량을 기준으로 쓴다.
    if (!isPerHundred &&
        !isPerPiece &&
        nutrientBasis == null &&
        totalContent != null) {
      nutrientBasis = totalContent;
    }

    final name = (m['name'] ?? m['productName'] ?? '').toString().trim();

    return NutritionLabelReading(
      kcal: numOf('kcal'),
      carb: carb,
      protein: numOf('protein'),
      fat: numOf('fat'),
      fiber: fiber,
      nutrientBasis: nutrientBasis,
      totalContent: totalContent,
      isPerHundred: isPerHundred,
      isPerPiece: isPerPiece,
      productName: name.isEmpty ? null : name,
    );
  }
}

/// 소수점이 의미 없는 값은 정수로 표기한다.
String formatLabelNumber(double v) {
  if (v.isNaN || v.isInfinite) return '0';
  if ((v - v.round()).abs() < 0.05) return v.round().toString();
  return v.toStringAsFixed(1);
}

/// OCR 텍스트 한 덩어리를 파싱한다.
NutritionLabelReading parseNutritionLabel(String rawText) {
  final lines = _splitLines(rawText);
  if (lines.isEmpty) return NutritionLabelReading.empty;

  // 라벨이 세로로 눌려 찍히면 OCR이 글자 사이에 공백을 넣는다("탄 수 화 물").
  // 원문에서 못 찾은 항목만 공백 제거본으로 한 번 더 찾는다.
  final compact = lines.map(_compact).toList();

  double? value(RegExp keyword, Set<String> units) =>
      _findValue(lines, keyword, units) ?? _findValue(compact, keyword, units);

  final rawCarb = value(_carbKey, _gramUnits);
  final fiber = value(_fiberKey, _gramUnits);
  // 앱의 탄수화물은 순탄수화물(총 탄수화물 - 식이섬유)로 기록한다.
  final carb = rawCarb == null
      ? null
      : fiber == null
          ? rawCarb
          : (rawCarb - fiber).clamp(0, double.infinity).toDouble();

  final scale = _detectLabelScale(lines, compact);
  // 헤더의 `100g당 열량` / `1개당 OOkcal`을 표 본문 열량보다 우선한다.
  final kcal = scale.headerKcal ?? value(_kcalKey, _kcalUnits);

  return NutritionLabelReading(
    kcal: kcal,
    carb: carb,
    protein: value(_proteinKey, _gramUnits),
    fat: value(_fatKey, _gramUnits),
    fiber: fiber,
    nutrientBasis: scale.nutrientBasis,
    totalContent: scale.totalContent,
    isPerHundred: scale.isPerHundred,
    isPerPiece: scale.isPerPiece,
  );
}

// ── 키워드 ────────────────────────────────────────────────────

// `열랑`은 OCR 오인식 대비.
final RegExp _kcalKey = RegExp(r'열\s*[량랑]|칼로리|에너지');
final RegExp _carbKey = RegExp('탄수화물');
final RegExp _proteinKey = RegExp('단백질');
final RegExp _fiberKey = RegExp('식이섬유');

// `포화지방`·`트랜스지방`·`지방산`을 지방으로 오인하지 않도록 앞뒤를 막는다.
final RegExp _fatKey = RegExp(r'(?<![가-힣])지방(?!산)');

final List<RegExp> _nutrientKeys = [
  _kcalKey,
  _carbKey,
  _proteinKey,
  _fatKey,
  _fiberKey,
];

const Set<String> _gramUnits = {'g'};
const Set<String> _kcalUnits = {'kcal', '㎉'};

final RegExp _numberUnit = RegExp(
  r'(\d+(?:[.,]\d+)?)\s*(kcal|㎉|mg|g|ml|㎖|%)?',
  caseSensitive: false,
);

/// `100g당`, `100그램당`, `100 ml 당` 등. 열량 숫자는 별도로 추출한다.
final RegExp _per100Key = RegExp(
  r'100\s*(g|그램|ml|㎖)\s*당',
  caseSensitive: false,
);

/// `100g당` 뒤에 붙는 `열량(kcal) 250` / `열량 250` / `250kcal` 형태.
final RegExp _per100KcalNearby = RegExp(
  r'(?:열\s*[량랑]|칼로리|에너지)\s*\(?\s*kcal\s*\)?\s*[:=]?\s*(\d+(?:[.,]\d+)?)|'
  r'(?:열\s*[량랑]|칼로리|에너지)\s*[:=]?\s*(\d+(?:[.,]\d+)?)|'
  r'(\d+(?:[.,]\d+)?)\s*(?:kcal|㎉)',
  caseSensitive: false,
);

final RegExp _totalContentKey = RegExp(r'총\s*(내용량|중량|용량)');
final RegExp _servingKey = RegExp(r'1\s*회\s*(제공량|섭취량|섭취참고량|분량)');

/// 낱개 포장 단위. 긴 것부터 매칭해야 `봉지`가 `봉`으로 잘리지 않는다.
const Set<String> _pieceUnits = {
  '개',
  '봉',
  '봉지',
  '포',
  '팩',
  '입',
  '줄',
  '바',
  '병',
  '캔',
};

/// `1봉지당`, `1봉(20g)당`, `1개당`, `1포당` 등.
final RegExp _pieceKey = RegExp(
  r'1\s*(봉지|봉|개|포|팩|입|줄|바|병|캔)'
  r'(?:\s*\(\s*(\d+(?:[.,]\d+)?)\s*(g|그램|ml|㎖)\s*\))?'
  r'\s*당',
  caseSensitive: false,
);

// ── 내부 구현 ─────────────────────────────────────────────────

class _LabelScale {
  final bool isPerHundred;
  final bool isPerPiece;
  final NutritionBasis? nutrientBasis;
  final NutritionBasis? totalContent;
  final double? headerKcal;

  const _LabelScale({
    required this.isPerHundred,
    this.isPerPiece = false,
    this.nutrientBasis,
    this.totalContent,
    this.headerKcal,
  });
}

List<String> _splitLines(String rawText) => rawText
    .replaceAll('\r', '\n')
    .split('\n')
    .map((l) => l.trim())
    .where((l) => l.isNotEmpty)
    .toList();

String _compact(String line) => line.replaceAll(RegExp(r'\s+'), '');

bool _hasOtherNutrientKeyword(String line, RegExp exclude) {
  for (final key in _nutrientKeys) {
    if (key == exclude) continue;
    if (key.hasMatch(line)) return true;
  }
  return false;
}

/// 키워드가 있는 줄에서 값을 찾고, 없으면 바로 다음 줄까지 살펴본다.
/// (라벨명과 수치가 줄바꿈으로 갈라져 인식되는 경우가 흔하다.)
double? _findValue(List<String> lines, RegExp keyword, Set<String> units) {
  for (var i = 0; i < lines.length; i++) {
    final match = keyword.firstMatch(lines[i]);
    if (match == null) continue;

    final sameLine = _valueIn(lines[i].substring(match.end), units);
    if (sameLine != null) return sameLine;

    for (var j = i + 1; j < lines.length && j <= i + 2; j++) {
      if (_hasOtherNutrientKeyword(lines[j], keyword)) break;
      final next = _valueIn(lines[j], units);
      if (next != null) return next;
    }
  }
  return null;
}

/// 단위가 명시된 숫자를 우선 채택하고, 없으면 단위 없는 숫자를 쓴다.
/// `%`(1일 영양성분 기준치)와 다른 단위(`mg` 등)는 건너뛴다.
double? _valueIn(String text, Set<String> units) =>
    _scanNumber(text, units, requireUnit: true) ??
    _scanNumber(text, units, requireUnit: false);

double? _scanNumber(
  String text,
  Set<String> units, {
  required bool requireUnit,
}) {
  for (final m in _numberUnit.allMatches(text)) {
    final unit = (m.group(2) ?? '').toLowerCase();
    if (unit.isEmpty) {
      if (requireUnit) continue;
    } else if (!units.contains(unit)) {
      continue;
    }
    final parsed = double.tryParse(m.group(1)!.replaceAll(',', '.'));
    if (parsed == null || parsed.isNaN || parsed.isInfinite || parsed < 0) {
      continue;
    }
    return parsed;
  }
  return null;
}

({double amount, String unit})? _amountIn(String text) =>
    _scanAmount(text, requireUnit: true) ??
    _scanAmount(text, requireUnit: false);

({double amount, String unit})? _scanAmount(
  String text, {
  required bool requireUnit,
}) {
  for (final m in _numberUnit.allMatches(text)) {
    final unit = (m.group(2) ?? '').toLowerCase();
    if (unit.isEmpty) {
      if (requireUnit) continue;
    } else if (unit != 'g' && unit != 'ml' && unit != '㎖') {
      continue;
    }
    final parsed = double.tryParse(m.group(1)!.replaceAll(',', '.'));
    if (parsed == null || parsed.isNaN || parsed.isInfinite || parsed <= 0) {
      continue;
    }
    return (
      amount: parsed,
      unit: (unit == 'ml' || unit == '㎖') ? 'ml' : 'g',
    );
  }
  return null;
}

NutritionBasis? _findLabeledAmount(
  List<String> lines,
  List<String> compact,
  RegExp key,
  String label,
) {
  for (final source in [lines, compact]) {
    for (var i = 0; i < source.length; i++) {
      final m = key.firstMatch(source[i]);
      if (m == null) continue;
      final parsed = _amountIn(source[i].substring(m.end)) ??
          (i + 1 < source.length ? _amountIn(source[i + 1]) : null);
      if (parsed == null) continue;
      return NutritionBasis(
        label: label,
        amount: parsed.amount,
        unit: parsed.unit,
      );
    }
  }
  return null;
}

/// 표의 수치 기준을 가른다.
///
/// 우선순위: `100g당` → 낱개(`1개당` 등) → 총 내용량 → 1회 제공량
_LabelScale _detectLabelScale(List<String> lines, List<String> compact) {
  final perHundred = _findPerHundred(lines, compact);
  final perPiece = _findPerPiece(lines, compact);

  final total = _findLabeledAmount(
    lines,
    compact,
    _totalContentKey,
    '총 내용량',
  );
  final serving = _findLabeledAmount(
    lines,
    compact,
    _servingKey,
    '1회 제공량',
  );

  if (perHundred != null) {
    return _LabelScale(
      isPerHundred: true,
      nutrientBasis: NutritionBasis(
        label: '100${perHundred.unit}당',
        amount: 100,
        unit: perHundred.unit,
      ),
      totalContent: total,
      headerKcal: perHundred.kcal,
    );
  }

  if (perPiece != null) {
    // 낱개 표에서는 탄단지·열량도 보통 1개 기준이다.
    return _LabelScale(
      isPerHundred: false,
      isPerPiece: true,
      nutrientBasis: perPiece.basis,
      totalContent: total,
      headerKcal: perPiece.kcal,
    );
  }

  // 그 외에는 표의 수치는 총 내용량(또는 1회 제공량) 기준.
  final basis = total ?? serving;
  return _LabelScale(
    isPerHundred: false,
    nutrientBasis: basis,
    totalContent: total,
  );
}

/// `100그램당 열량(kcal) 250`, `100g당 250kcal` 등에서 단위·열량을 뽑는다.
({String unit, double? kcal})? _findPerHundred(
  List<String> lines,
  List<String> compact,
) {
  for (final source in [lines, compact]) {
    for (var i = 0; i < source.length; i++) {
      final m = _per100Key.firstMatch(source[i]);
      if (m == null) continue;

      final rawUnit = m.group(1)!.toLowerCase();
      final unit = (rawUnit == 'ml' || rawUnit == '㎖') ? 'ml' : 'g';

      // 같은 줄 나머지 → 다음 1~2줄에서 열량 숫자를 찾는다.
      // 나트륨 mg 등 다른 숫자를 오인하지 않도록 kcal/열량 근처만 본다.
      final chunks = <String>[source[i].substring(m.end)];
      for (var j = i + 1; j < source.length && j <= i + 2; j++) {
        chunks.add(source[j]);
      }
      final joined = chunks.join(' ');
      final kcal = _kcalAfterPerHundred(joined) ??
          _scanNumber(joined, _kcalUnits, requireUnit: true);

      return (unit: unit, kcal: kcal);
    }
  }
  return null;
}

double? _kcalAfterPerHundred(String text) {
  final m = _per100KcalNearby.firstMatch(text);
  if (m == null) return null;
  final raw = (m.group(1) ?? m.group(2) ?? m.group(3))?.replaceAll(',', '.');
  if (raw == null) return null;
  final parsed = double.tryParse(raw);
  if (parsed == null || parsed.isNaN || parsed.isInfinite || parsed <= 0) {
    return null;
  }
  return parsed;
}

/// `1개당 80kcal`, `1봉(20g)당 100kcal`, `1포당 열량 90` 등.
({NutritionBasis basis, double? kcal})? _findPerPiece(
  List<String> lines,
  List<String> compact,
) {
  for (final source in [lines, compact]) {
    for (var i = 0; i < source.length; i++) {
      final m = _pieceKey.firstMatch(source[i]);
      if (m == null) continue;

      final piece = m.group(1)!;
      final label = '1$piece당'; // 1개당, 1봉당, 1포당, 1팩당, 1입당, 1줄당, 1바당, 1병당, 1캔당 등
      final parenAmount = m.group(2);
      final parenUnitRaw = (m.group(3) ?? '').toLowerCase();
      final sameLineRest = source[i].substring(m.end);

      // 열량은 다음 줄까지 볼 수 있지만, 중량은 같은 줄만 본다.
      // (다음 줄 `탄수화물 12g`를 낱개 중량으로 오인하지 않기 위함)
      final kcalChunks = <String>[sameLineRest];
      for (var j = i + 1; j < source.length && j <= i + 2; j++) {
        kcalChunks.add(source[j]);
      }
      final kcalJoined = kcalChunks.join(' ');
      final kcal = _kcalAfterPerHundred(kcalJoined) ??
          _scanNumber(kcalJoined, _kcalUnits, requireUnit: true);

      NutritionBasis basis;
      if (parenAmount != null && parenAmount.isNotEmpty) {
        final amount = double.tryParse(parenAmount.replaceAll(',', '.'));
        final unit =
            (parenUnitRaw == 'ml' || parenUnitRaw == '㎖') ? 'ml' : 'g';
        if (amount != null && amount > 0) {
          basis = NutritionBasis(label: label, amount: amount, unit: unit);
        } else {
          basis = NutritionBasis(label: label, amount: 1, unit: piece);
        }
      } else {
        final weight = _amountIn(sameLineRest);
        if (weight != null) {
          // `1개당 20g 80kcal`처럼 낱개 중량이 있으면 g/ml 기준으로 둔다.
          basis = NutritionBasis(
            label: label,
            amount: weight.amount,
            unit: weight.unit,
          );
        } else {
          basis = NutritionBasis(label: label, amount: 1, unit: piece);
        }
      }

      return (basis: basis, kcal: kcal);
    }
  }
  return null;
}
