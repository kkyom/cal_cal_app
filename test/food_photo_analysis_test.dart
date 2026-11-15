import 'package:cal_cal_app/food_item.dart';
import 'package:cal_cal_app/food_photo_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FoodPhotoItem.fromAiMap', () {
    test('정상 응답을 그대로 읽는다', () {
      final item = FoodPhotoItem.fromAiMap({
        'name': '김치찌개',
        'portion': '1인분',
        'grams': 400,
        'kcal': 316,
        'carb': 12,
        'protein': 22,
        'fat': 20,
      })!;

      expect(item.name, '김치찌개');
      expect(item.portion, '1인분');
      expect(item.grams, 400);
      expect(item.kcal, 316);
      expect(item.carb, 12);
      expect(item.protein, 22);
      expect(item.fat, 20);
    });

    test('이름 앞뒤 공백은 지운다', () {
      final item = FoodPhotoItem.fromAiMap({
        'name': '  공기밥 ',
        'portion': ' 1공기 ',
        'grams': 210,
        'kcal': 300,
        'carb': 65,
        'protein': 6,
        'fat': 1,
      })!;
      expect(item.name, '공기밥');
      expect(item.portion, '1공기');
    });

    test('이름이 비어 있으면 버린다', () {
      expect(
        FoodPhotoItem.fromAiMap({'name': '  ', 'grams': 100, 'kcal': 100}),
        isNull,
      );
      expect(FoodPhotoItem.fromAiMap({'grams': 100, 'kcal': 100}), isNull);
    });

    test('양이 0 이하이거나 없으면 버린다', () {
      expect(FoodPhotoItem.fromAiMap({'name': '밥', 'grams': 0}), isNull);
      expect(FoodPhotoItem.fromAiMap({'name': '밥', 'grams': -5}), isNull);
      expect(FoodPhotoItem.fromAiMap({'name': '밥'}), isNull);
    });

    test('숫자가 문자열로 와도 읽는다', () {
      final item = FoodPhotoItem.fromAiMap({
        'name': '계란말이',
        'grams': '100',
        'kcal': '146.5',
        'carb': '3',
        'protein': '11',
        'fat': '10',
      })!;
      expect(item.grams, 100);
      expect(item.kcal, 146.5);
      expect(item.protein, 11);
    });

    test('음수·읽을 수 없는 영양소는 0으로 둔다', () {
      final item = FoodPhotoItem.fromAiMap({
        'name': '샐러드',
        'grams': 150,
        'kcal': 80,
        'carb': -3,
        'protein': 'abc',
        'fat': null,
      })!;
      expect(item.carb, 0);
      expect(item.protein, 0);
      expect(item.fat, 0);
      expect(item.kcal, 80);
    });

    test('kcal이 없거나 0이면 탄단지로 계산한다(4/4/9)', () {
      final item = FoodPhotoItem.fromAiMap({
        'name': '밥',
        'grams': 210,
        'carb': 65,
        'protein': 6,
        'fat': 1,
      })!;
      expect(item.kcal, 65 * 4 + 6 * 4 + 1 * 9);
    });

    test('portion이 없으면 빈 문자열', () {
      final item = FoodPhotoItem.fromAiMap({
        'name': '사과',
        'grams': 200,
        'kcal': 100,
      })!;
      expect(item.portion, '');
    });
  });

  group('FoodPhotoItem 변환', () {
    const item = FoodPhotoItem(
      name: '김치찌개',
      portion: '1인분',
      grams: 400,
      kcal: 316,
      carb: 12,
      protein: 22,
      fat: 20,
    );

    test('amountLabel은 "양 · 그램"으로 보여준다', () {
      expect(item.amountLabel, '1인분 · 400g');
    });

    test('portion이 없으면 그램만 보여준다', () {
      const noPortion = FoodPhotoItem(
        name: '사과',
        portion: '',
        grams: 200,
        kcal: 100,
        carb: 25,
        protein: 0,
        fat: 0,
      );
      expect(noPortion.amountLabel, '200g');
    });

    test('toRecord는 추정 양 그대로의 영양소를 기록한다', () {
      final r = item.toRecord();
      expect(r.name, '김치찌개');
      expect(r.kcal, closeTo(316, 0.001));
      expect(r.carb, closeTo(12, 0.001));
      expect(r.protein, closeTo(22, 0.001));
      expect(r.fat, closeTo(20, 0.001));
      expect(r.sourceLoggedAmount, 400);
      expect(r.sourceFoodItemJson, isNotNull);
    });

    test('기록을 다시 열어 양을 바꾸면 비례해서 계산된다', () {
      final r = item.toRecord();
      final food = FoodItem.fromFoodRecord(r);
      expect(food.servingAmount, 400);
      expect(food.kcalFor(200), closeTo(158, 0.001));
      expect(food.proteinFor(200), closeTo(11, 0.001));
    });
  });

  group('FoodPhotoAnalysis.fromAiMap', () {
    test('음식 목록을 읽고 잘못된 항목만 건너뛴다', () {
      final a = FoodPhotoAnalysis.fromAiMap({
        'isFood': true,
        'foods': [
          {'name': '김치찌개', 'grams': 400, 'kcal': 316},
          {'name': '', 'grams': 100, 'kcal': 50},
          'not a map',
          {'name': '공기밥', 'grams': 210, 'kcal': 300},
        ],
      });
      expect(a.isFood, isTrue);
      expect(a.foods.map((f) => f.name), ['김치찌개', '공기밥']);
    });

    test('isFood=false면 음식이 아니라고 본다', () {
      final a = FoodPhotoAnalysis.fromAiMap({'isFood': false, 'foods': []});
      expect(a.isFood, isFalse);
      expect(a.foods, isEmpty);
    });

    test('isFood=true여도 읽을 수 있는 음식이 없으면 음식이 아니라고 본다', () {
      final a = FoodPhotoAnalysis.fromAiMap({
        'isFood': true,
        'foods': [
          {'name': '', 'grams': 0},
        ],
      });
      expect(a.isFood, isFalse);
      expect(a.foods, isEmpty);
    });

    test('foods가 없거나 목록이 아니어도 깨지지 않는다', () {
      expect(FoodPhotoAnalysis.fromAiMap({}).foods, isEmpty);
      expect(FoodPhotoAnalysis.fromAiMap({'foods': 'oops'}).foods, isEmpty);
      expect(FoodPhotoAnalysis.fromAiMap({'foods': null}).isFood, isFalse);
    });
  });
}
