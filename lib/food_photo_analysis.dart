/// 음식 사진 AI 분석(`analyzeFoodPhoto` Cloud Function) 호출과 응답 모델.
///
/// 영양성분표 인식과 같은 무료 일일 한도(`nutritionScanQuota`)를 함께 쓴다.
library;

import 'dart:convert';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';

import 'food_item.dart';
import 'models.dart';
import 'nutrition_label_ocr.dart' show formatLabelNumber;

const String _kFunctionsRegion = 'asia-northeast3';

/// 서버가 무료 일일 한도 초과로 거부했을 때 일반 오류와 구분하기 위한 예외.
class FoodPhotoQuotaExceeded implements Exception {
  const FoodPhotoQuotaExceeded(this.message);

  final String message;

  @override
  String toString() => message;
}

/// AI가 사진에서 찾은 음식 한 가지(추정 양 기준 영양소).
class FoodPhotoItem {
  const FoodPhotoItem({
    required this.name,
    required this.portion,
    required this.grams,
    required this.kcal,
    required this.carb,
    required this.protein,
    required this.fat,
  });

  final String name;

  /// "1인분", "2조각"처럼 사람이 읽는 양 표현. 없으면 빈 문자열.
  final String portion;

  /// 추정 섭취량(g 또는 음료는 ml).
  final double grams;
  final double kcal;
  final double carb;
  final double protein;
  final double fat;

  /// 응답 한 항목을 읽는다. 이름이나 양이 없으면 null.
  static FoodPhotoItem? fromAiMap(Map<dynamic, dynamic> raw) {
    double numOf(String key) {
      final v = raw[key];
      final d = v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
      if (d == null || d.isNaN || d.isInfinite || d < 0) return 0;
      return d;
    }

    final name = (raw['name'] ?? '').toString().trim();
    final grams = numOf('grams');
    if (name.isEmpty || grams <= 0) return null;

    final carb = numOf('carb');
    final protein = numOf('protein');
    final fat = numOf('fat');
    var kcal = numOf('kcal');
    if (kcal <= 0) kcal = carb * 4 + protein * 4 + fat * 9;

    return FoodPhotoItem(
      name: name,
      portion: (raw['portion'] ?? '').toString().trim(),
      grams: grams,
      kcal: kcal,
      carb: carb,
      protein: protein,
      fat: fat,
    );
  }

  /// 상세 화면에서 양을 바꿔도 비례 계산되도록 1g당 값을 담은 [FoodItem].
  FoodItem toFoodItem() => FoodItem.fromJson({
    'name': name,
    'rawServingSize': FoodItem.formatServingLabel(grams, 'g'),
    'servingAmount': grams,
    'servingUnit': 'g',
    'kcal': kcal,
    'carb': carb,
    'protein': protein,
    'fat': fat,
    'fiber': 0.0,
    'kcalPerUnit': kcal / grams,
    'carbPerUnit': carb / grams,
    'proteinPerUnit': protein / grams,
    'fatPerUnit': fat / grams,
    'fiberPerUnit': 0.0,
  });

  /// 추정 양 그대로 기록할 [FoodRecord].
  FoodRecord toRecord() => toFoodItem().toRecord(grams);

  /// "1인분 · 400g" 형태의 양 표기.
  String get amountLabel {
    final g = '${formatLabelNumber(grams)}g';
    return portion.isEmpty ? g : '$portion · $g';
  }
}

/// 사진 한 장의 분석 결과.
class FoodPhotoAnalysis {
  const FoodPhotoAnalysis({required this.isFood, required this.foods});

  /// 사진에 음식이 없다고 판단했으면 false.
  final bool isFood;
  final List<FoodPhotoItem> foods;

  factory FoodPhotoAnalysis.fromAiMap(Map<dynamic, dynamic> raw) {
    final list = raw['foods'];
    final foods = list is List
        ? list
              .whereType<Map<dynamic, dynamic>>()
              .map(FoodPhotoItem.fromAiMap)
              .whereType<FoodPhotoItem>()
              .toList()
        : <FoodPhotoItem>[];
    final isFood = raw['isFood'] != false;
    return FoodPhotoAnalysis(isFood: isFood && foods.isNotEmpty, foods: foods);
  }
}

/// [file]을 `analyzeFoodPhoto`로 보내 분석한다.
///
/// 무료 한도를 넘기면 [FoodPhotoQuotaExceeded], 그 밖의 서버·네트워크 오류는
/// [FirebaseFunctionsException] 등을 그대로 던진다.
Future<FoodPhotoAnalysis> analyzeFoodPhoto(File file) async {
  final bytes = await file.readAsBytes();
  if (bytes.isEmpty) throw StateError('빈 이미지입니다.');

  final lower = file.path.toLowerCase();
  final mimeType = lower.endsWith('.png')
      ? 'image/png'
      : lower.endsWith('.webp')
      ? 'image/webp'
      : 'image/jpeg';

  final callable = FirebaseFunctions.instanceFor(region: _kFunctionsRegion)
      .httpsCallable(
        'analyzeFoodPhoto',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 55)),
      );

  final HttpsCallableResult<dynamic> res;
  try {
    res = await callable.call({
      'imageBase64': base64Encode(bytes),
      'mimeType': mimeType,
    });
  } on FirebaseFunctionsException catch (e) {
    if (e.code == 'resource-exhausted') {
      throw FoodPhotoQuotaExceeded(
        e.message?.trim().isNotEmpty == true
            ? e.message!
            : '오늘 무료 인식 횟수를 모두 사용했어요. 내일 다시 시도해 주세요.',
      );
    }
    rethrow;
  }

  final data = res.data;
  if (data is! Map || data['analysis'] is! Map) {
    throw StateError('분석 응답 형식이 올바르지 않습니다.');
  }
  return FoodPhotoAnalysis.fromAiMap(data['analysis'] as Map);
}
