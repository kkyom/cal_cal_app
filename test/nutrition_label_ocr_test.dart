import 'package:cal_cal_app/nutrition_label_ocr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseNutritionLabel', () {
    test('100g당이 없으면 총 내용량을 기준량으로 쓴다', () {
      const text = '''
영양정보
총 내용량 200g
300kcal
나트륨 400mg 20%
탄수화물 45g 14%
당류 12g 12%
지방 8g 15%
트랜스지방 0g
포화지방 3g 20%
콜레스테롤 5mg 2%
단백질 12g 22%
''';

      final reading = parseNutritionLabel(text);

      expect(reading.carb, 45);
      expect(reading.protein, 12);
      expect(reading.fat, 8);
      expect(reading.isPerHundred, isFalse);
      expect(reading.basis?.amount, 200);
      expect(reading.basis?.label, '총 내용량');
      expect(reading.totalContent?.amount, 200);
      expect(reading.nutrientBasis, reading.totalContent);
    });

    test('100g당이 있으면 기준량은 100, 총 내용량은 따로 둔다', () {
      const text = '''
영양정보
총 내용량 200g
100g당 250kcal
나트륨 200mg
탄수화물 20g
당류 5g
식이섬유 3g
단백질 10g
지방 4g
''';

      final reading = parseNutritionLabel(text);

      expect(reading.isPerHundred, isTrue);
      expect(reading.nutrientBasis?.label, '100g당');
      expect(reading.nutrientBasis?.amount, 100);
      expect(reading.totalContent?.label, '총 내용량');
      expect(reading.totalContent?.amount, 200);
      expect(reading.kcal, 250);
      expect(reading.carb, 17); // 20 - 3
      expect(reading.protein, 10);
      expect(reading.fat, 4);
    });

    test('1봉당 열량을 읽고 영양성분은 낱개 기준으로 둔다', () {
      const text = '''
영양정보
총 내용량 10개(200g)
1봉당 80kcal
탄수화물 12g
단백질 3g
지방 2g
''';

      final reading = parseNutritionLabel(text);

      expect(reading.isPerPiece, isTrue);
      expect(reading.isPerHundred, isFalse);
      expect(reading.kcal, 80);
      expect(reading.nutrientBasis?.label, '1봉당');
      expect(reading.nutrientBasis?.amount, 1);
      expect(reading.carb, 12);
      expect(reading.protein, 3);
      expect(reading.fat, 2);
    });

    test('1개당 중량과 열량이 같이 있으면 중량을 기준량으로 쓴다', () {
      const text = '''
1개당 20g 100kcal
탄수화물 15g
단백질 4g
지방 3g
''';

      final reading = parseNutritionLabel(text);

      expect(reading.isPerPiece, isTrue);
      expect(reading.kcal, 100);
      expect(reading.nutrientBasis?.label, '1개당');
      expect(reading.nutrientBasis?.amount, 20);
      expect(reading.nutrientBasis?.unit, 'g');
      expect(reading.carb, 15);
    });

    test('1포당·1봉지당 표기도 인식한다', () {
      expect(parseNutritionLabel('1포당 90kcal\n탄수화물 10g').kcal, 90);
      expect(
        parseNutritionLabel('1봉지당 70kcal\n단백질 2g').nutrientBasis?.label,
        '1봉지당',
      );
    });

    test('100g당이 있으면 1개당보다 100g당을 우선한다', () {
      const text = '''
1개당 80kcal
100g당 400kcal
탄수화물 50g
''';

      final reading = parseNutritionLabel(text);

      expect(reading.isPerHundred, isTrue);
      expect(reading.isPerPiece, isFalse);
      expect(reading.kcal, 400);
      expect(reading.nutrientBasis?.amount, 100);
    });

    test('100그램당 열량(kcal) 표기를 읽어 열량 필드에 넣는다', () {
      const text = '''
영양정보
총 내용량 80g
100그램당 열량(kcal) 372
탄수화물 45g
단백질 20g
지방 8g
''';

      final reading = parseNutritionLabel(text);

      expect(reading.isPerHundred, isTrue);
      expect(reading.nutrientBasis?.amount, 100);
      expect(reading.kcal, 372);
      expect(reading.totalContent?.amount, 80);
    });

    test('100그램당 열량과 숫자가 줄바꿈으로 갈라져도 읽는다', () {
      const text = '''
총 내용량 80g
100그램당 열량(kcal)
372
탄수화물 45g
단백질 20g
지방 8g
''';

      final reading = parseNutritionLabel(text);

      expect(reading.isPerHundred, isTrue);
      expect(reading.kcal, 372);
    });

    test('100g당과 총 내용량이 한 줄에 있어도 구분한다', () {
      const text = '총 내용량 500g 100g당 180kcal\n탄수화물 30g\n단백질 8g\n지방 2g';

      final reading = parseNutritionLabel(text);

      expect(reading.isPerHundred, isTrue);
      expect(reading.nutrientBasis?.amount, 100);
      expect(reading.totalContent?.amount, 500);
      expect(reading.kcal, 180);
    });

    test('100ml당이면 기준 단위를 ml로 둔다', () {
      const text = '총 내용량 350ml\n100ml당 40kcal\n탄수화물 10g\n단백질 0g\n지방 0g';

      final reading = parseNutritionLabel(text);

      expect(reading.isPerHundred, isTrue);
      expect(reading.nutrientBasis?.unit, 'ml');
      expect(reading.nutrientBasis?.amount, 100);
      expect(reading.totalContent?.amount, 350);
      expect(reading.totalContent?.unit, 'ml');
    });

    test('열량 키워드가 있는 줄에서 kcal을 읽는다', () {
      const text = '총 내용량 100g\n열량 250kcal\n탄수화물 30g\n단백질 10g\n지방 5g';

      final reading = parseNutritionLabel(text);

      expect(reading.kcal, 250);
      expect(reading.recognizedMacroCount, 3);
    });

    test('포화지방·트랜스지방을 지방으로 오인하지 않는다', () {
      const text = '포화지방 3g 20%\n트랜스지방 0.5g\n지방 11g 20%';

      expect(parseNutritionLabel(text).fat, 11);
    });

    test('당류를 탄수화물로 오인하지 않는다', () {
      const text = '당류 12g\n탄수화물 45g';

      expect(parseNutritionLabel(text).carb, 45);
    });

    test('식이섬유가 있으면 탄수화물에서 뺀다', () {
      const text = '''
탄수화물 45g 14%
당류 12g 12%
식이섬유 8g 29%
단백질 12g
지방 8g
''';

      final reading = parseNutritionLabel(text);

      expect(reading.fiber, 8);
      expect(reading.carb, 37);
    });

    test('식이섬유가 탄수화물보다 크면 0으로 보정한다', () {
      const text = '탄수화물 5g\n식이섬유 8g';

      final reading = parseNutritionLabel(text);

      expect(reading.fiber, 8);
      expect(reading.carb, 0);
    });

    test('식이섬유가 없으면 탄수화물을 그대로 쓴다', () {
      const text = '탄수화물 30g\n단백질 10g';

      final reading = parseNutritionLabel(text);

      expect(reading.fiber, isNull);
      expect(reading.carb, 30);
    });

    test('%는 값으로 쓰지 않고 g 단위 숫자를 고른다', () {
      const text = '탄수화물 6% 45g';

      expect(parseNutritionLabel(text).carb, 45);
    });

    test('항목명과 수치가 줄바꿈으로 갈라져도 읽는다', () {
      const text = '탄수화물\n45g\n단백질\n12g\n지방\n8g';

      final reading = parseNutritionLabel(text);

      expect(reading.carb, 45);
      expect(reading.protein, 12);
      expect(reading.fat, 8);
    });

    test('앞 항목의 값을 다음 항목이 가져가지 않는다', () {
      const text = '탄수화물\n단백질 12g';

      final reading = parseNutritionLabel(text);

      expect(reading.carb, isNull);
      expect(reading.protein, 12);
    });

    test('100g당이 없고 1회 제공량만 있으면 그걸 기준으로 쓴다', () {
      const text = '1회 제공량 30g\n탄수화물 20g';

      final reading = parseNutritionLabel(text);

      expect(reading.isPerHundred, isFalse);
      expect(reading.basis?.label, '1회 제공량');
      expect(reading.basis?.amount, 30);
      expect(reading.totalContent, isNull);
    });

    test('ml 라벨은 단위를 ml로 인식한다', () {
      const text = '총 내용량 350ml\n열량 140kcal\n탄수화물 35g';

      final reading = parseNutritionLabel(text);

      expect(reading.isPerHundred, isFalse);
      expect(reading.basis?.unit, 'ml');
      expect(reading.basis?.amount, 350);
    });

    test('개수 표기가 섞여도 단위가 붙은 숫자를 총 내용량으로 쓴다', () {
      const text = '총 내용량 2개(180g)\n탄수화물 30g';

      expect(parseNutritionLabel(text).basis?.amount, 180);
    });

    test('글자 사이에 공백이 끼어도 읽는다', () {
      const text = '탄 수 화 물 45g\n단 백 질 12g';

      final reading = parseNutritionLabel(text);

      expect(reading.carb, 45);
      expect(reading.protein, 12);
    });

    test('소수점과 쉼표 표기를 모두 처리한다', () {
      const text = '탄수화물 4.5g\n단백질 1,5g\n지방 0.3g';

      final reading = parseNutritionLabel(text);

      expect(reading.carb, 4.5);
      expect(reading.protein, 1.5);
      expect(reading.fat, 0.3);
    });

    test('빈 텍스트는 빈 결과를 준다', () {
      final reading = parseNutritionLabel('   \n\n');

      expect(reading.hasAnyMacro, isFalse);
      expect(reading.nutrientBasis, isNull);
      expect(reading.totalContent, isNull);
    });

    test('영양성분표가 아닌 텍스트는 값을 만들어내지 않는다', () {
      final reading = parseNutritionLabel('유통기한 2026.12.31\n제조원 서울공장');

      expect(reading.hasAnyMacro, isFalse);
      expect(reading.kcal, isNull);
    });
  });

  group('NutritionLabelReading.fromAiMap', () {
    test('100g당 AI 응답에서 기준량과 총 내용량을 구분하고 식이섬유를 뺀다', () {
      final reading = NutritionLabelReading.fromAiMap({
        'name': '프로틴바',
        'kcal': 250,
        'carb': 20,
        'protein': 10,
        'fat': 4,
        'fiber': 3,
        'isPerHundred': true,
        'basisAmount': 100,
        'basisUnit': 'g',
        'totalContentAmount': 200,
        'totalContentUnit': 'g',
      });

      expect(reading.productName, '프로틴바');
      expect(reading.isPerHundred, isTrue);
      expect(reading.nutrientBasis?.amount, 100);
      expect(reading.totalContent?.amount, 200);
      expect(reading.carb, 17);
      expect(reading.kcal, 250);
    });

    test('AI 응답 kcal에 단위가 붙어 있어도 숫자를 넣는다', () {
      final reading = NutritionLabelReading.fromAiMap({
        'kcal': '372kcal',
        'carb': 45,
        'protein': 20,
        'fat': 8,
        'isPerHundred': true,
        'basisAmount': 100,
        'basisUnit': 'g',
      });

      expect(reading.kcal, 372);
    });

    test('AI 응답 kcal에 접두어가 붙어 있어도 숫자를 넣는다', () {
      final reading = NutritionLabelReading.fromAiMap({
        'kcal': '약 250 kcal',
        'carb': 45,
        'protein': 20,
        'fat': 8,
      });

      expect(reading.kcal, 250);
    });

    test('kcal이 null이고 탄단지만 있으면 kcal은 null이다', () {
      final reading = NutritionLabelReading.fromAiMap({
        'kcal': null,
        'carb': 45,
        'protein': 20,
        'fat': 8,
        'isPerHundred': true,
        'basisAmount': 100,
        'basisUnit': 'g',
      });

      expect(reading.kcal, isNull);
      expect(reading.hasAnyMacro, isTrue);
    });

    test('AI 응답에서 1개당 기준을 반영한다', () {
      final reading = NutritionLabelReading.fromAiMap({
        'kcal': 80,
        'carb': 12,
        'protein': 3,
        'fat': 2,
        'isPerHundred': false,
        'isPerPiece': true,
        'basisLabel': '1봉당',
        'basisAmount': 1,
        'basisUnit': '봉',
        'totalContentAmount': 200,
        'totalContentUnit': 'g',
      });

      expect(reading.isPerPiece, isTrue);
      expect(reading.kcal, 80);
      expect(reading.nutrientBasis?.label, '1봉당');
      expect(reading.nutrientBasis?.amount, 1);
      expect(reading.carb, 12);
      expect(reading.totalContent?.amount, 200);
    });

    test('100g당이 없으면 총 내용량을 기준으로 쓴다', () {
      final reading = NutritionLabelReading.fromAiMap({
        'kcal': 300,
        'carb': 45,
        'protein': 12,
        'fat': 8,
        'fiber': null,
        'isPerHundred': false,
        'basisAmount': null,
        'basisUnit': null,
        'totalContentAmount': 200,
        'totalContentUnit': 'g',
      });

      expect(reading.isPerHundred, isFalse);
      expect(reading.nutrientBasis?.amount, 200);
      expect(reading.carb, 45);
    });
  });

  group('NutritionLabelReading.mergeMissing / estimatedKcal', () {
    test('primary의 kcal이 없으면 fallback의 kcal로 채운다', () {
      const primary = NutritionLabelReading(
        carb: 45,
        protein: 20,
        fat: 8,
        isPerHundred: true,
      );
      const fallback = NutritionLabelReading(kcal: 372, carb: 44);

      final merged = primary.mergeMissing(fallback);

      expect(merged.kcal, 372);
      expect(merged.carb, 45); // primary 값 우선, fallback으로 덮어쓰지 않는다.
      expect(merged.isPerHundred, isTrue);
    });

    test('primary에 이미 kcal이 있으면 fallback으로 덮어쓰지 않는다', () {
      const primary = NutritionLabelReading(kcal: 250, carb: 45);
      const fallback = NutritionLabelReading(kcal: 999);

      expect(primary.mergeMissing(fallback).kcal, 250);
    });

    test('탄단지로 kcal을 추정한다(4/4/9)', () {
      const reading = NutritionLabelReading(carb: 10, protein: 5, fat: 2);

      expect(reading.estimatedKcal, 10 * 4 + 5 * 4 + 2 * 9);
    });

    test('탄단지가 전혀 없으면 kcal을 추정하지 않는다', () {
      expect(NutritionLabelReading.empty.estimatedKcal, isNull);
    });
  });

  group('formatLabelNumber', () {
    test('정수는 소수점 없이 표기한다', () {
      expect(formatLabelNumber(200), '200');
      expect(formatLabelNumber(4.5), '4.5');
    });
  });
}
