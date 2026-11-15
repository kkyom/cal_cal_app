import 'dart:async';
import 'dart:io';

import 'package:cal_cal_app/food_photo_analysis.dart';
import 'package:cal_cal_app/food_photo_analysis_screen.dart';
import 'package:cal_cal_app/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

/// 1x1 투명 PNG.
const List<int> _kTinyPng = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

const _kimchiStew = FoodPhotoItem(
  name: '김치찌개',
  portion: '1인분',
  grams: 400,
  kcal: 316,
  carb: 12,
  protein: 22,
  fat: 20,
);

const _rice = FoodPhotoItem(
  name: '공기밥',
  portion: '1공기',
  grams: 210,
  kcal: 300,
  carb: 65,
  protein: 6,
  fat: 1,
);

final _twoFoods = FoodPhotoAnalysis(
  isFood: true,
  foods: const [_kimchiStew, _rice],
);

late Directory _tmpDir;

/// 화면이 dispose 때 사진을 지우므로 매번 새 파일을 만든다.
XFile _newPhoto() {
  final file = File(
    '${_tmpDir.path}/photo_${DateTime.now().microsecondsSinceEpoch}.png',
  )..writeAsBytesSync(_kTinyPng);
  return XFile(file.path);
}

List<MealEntry> _meals() => [
  MealEntry(id: 'breakfast', name: '아침', isFixed: true),
  MealEntry(id: 'lunch', name: '점심', isFixed: true),
  MealEntry(id: 'dinner', name: '저녁', isFixed: true),
  MealEntry(id: 'snack1', name: '간식 1'),
];

/// 분석 화면을 띄우는 버튼이 있는 테스트 앱. 화면이 돌려준 값을 [results]에 담는다.
class _Harness {
  _Harness({
    required this.analyze,
    Future<XFile?> Function(ImageSource)? pickImage,
    this.hour = 12,
  }) : pickImage = pickImage ?? ((_) async => _newPhoto());

  final Future<FoodPhotoAnalysis> Function(File) analyze;
  final Future<XFile?> Function(ImageSource) pickImage;
  final int hour;
  final List<FoodPhotoLogResult?> results = [];
  bool popped = false;

  Widget build() {
    return MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                final r = await Navigator.push<FoodPhotoLogResult>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FoodPhotoAnalysisScreen(
                      initialSource: ImageSource.camera,
                      meals: _meals(),
                      pickImage: pickImage,
                      analyze: analyze,
                      now: () => DateTime(2026, 11, 14, hour),
                    ),
                  ),
                );
                popped = true;
                results.add(r);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _open(WidgetTester tester, _Harness h) async {
  tester.view.physicalSize = const Size(1200, 4200);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(h.build());
  await tester.tap(find.text('open'));
  // 화면 전환 + 첫 프레임 뒤 사진 선택·분석까지 진행.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

Finder _submitButton() => find.textContaining('에 기록하기');

void main() {
  setUpAll(() {
    _tmpDir = Directory.systemTemp.createTempSync('food_photo_test');
  });

  tearDownAll(() {
    if (_tmpDir.existsSync()) _tmpDir.deleteSync(recursive: true);
  });

  group('분석 결과', () {
    testWidgets('인식된 음식과 합계 kcal을 보여준다', (tester) async {
      final h = _Harness(analyze: (_) async => _twoFoods);
      await _open(tester, h);

      expect(find.text('분석 결과'), findsOneWidget);
      expect(find.text('인식된 음식 2개'), findsOneWidget);
      expect(find.text('김치찌개'), findsOneWidget);
      expect(find.text('1인분 · 400g'), findsOneWidget);
      expect(find.text('316 kcal'), findsOneWidget);
      expect(find.text('공기밥'), findsOneWidget);
      expect(find.text('탄 77g · 단 28g · 지 21g'), findsOneWidget);
      expect(find.text('점심에 기록하기 · 616 kcal'), findsOneWidget);
    });

    testWidgets('아침 시간이면 아침을 기본으로 고른다', (tester) async {
      final h = _Harness(analyze: (_) async => _twoFoods, hour: 8);
      await _open(tester, h);
      expect(find.text('아침에 기록하기 · 616 kcal'), findsOneWidget);
    });

    testWidgets('저녁 시간이면 저녁을 기본으로 고른다', (tester) async {
      final h = _Harness(analyze: (_) async => _twoFoods, hour: 19);
      await _open(tester, h);
      expect(find.text('저녁에 기록하기 · 616 kcal'), findsOneWidget);
    });

    testWidgets('식사 칩을 바꾸면 버튼 문구도 바뀐다', (tester) async {
      final h = _Harness(analyze: (_) async => _twoFoods);
      await _open(tester, h);

      await tester.tap(find.text('간식 1'));
      await tester.pump();
      expect(find.text('간식 1에 기록하기 · 616 kcal'), findsOneWidget);
    });

    testWidgets('기록하면 고른 식사와 음식들을 돌려준다', (tester) async {
      final h = _Harness(analyze: (_) async => _twoFoods);
      await _open(tester, h);

      await tester.tap(find.text('저녁'));
      await tester.pump();
      await tester.tap(_submitButton());
      await tester.pumpAndSettle();

      expect(h.results, hasLength(1));
      final r = h.results.single!;
      expect(r.mealId, 'dinner');
      expect(r.foods.map((f) => f.name), ['김치찌개', '공기밥']);
      expect(r.foods.first.kcal, closeTo(316, 0.001));
      expect(r.foods.first.sourceLoggedAmount, 400);
    });

    testWidgets('왼쪽으로 밀면 음식이 빠지고 합계가 다시 계산된다', (tester) async {
      final h = _Harness(analyze: (_) async => _twoFoods);
      await _open(tester, h);

      await tester.drag(find.text('김치찌개'), const Offset(-600, 0));
      await tester.pumpAndSettle();

      expect(find.text('김치찌개'), findsNothing);
      expect(find.text('인식된 음식 1개'), findsOneWidget);
      expect(find.text('점심에 기록하기 · 300 kcal'), findsOneWidget);
    });

    testWidgets('음식을 모두 지우면 기록 버튼 없이 안내를 보여준다', (tester) async {
      final h = _Harness(analyze: (_) async => _twoFoods);
      await _open(tester, h);

      await tester.drag(find.text('김치찌개'), const Offset(-600, 0));
      await tester.pumpAndSettle();
      await tester.drag(find.text('공기밥'), const Offset(-600, 0));
      await tester.pumpAndSettle();

      expect(_submitButton(), findsNothing);
      expect(find.textContaining('모두 지웠어요'), findsOneWidget);
      expect(find.textContaining('찾지 못했어요'), findsNothing);
    });
  });

  group('음식이 없거나 실패했을 때', () {
    testWidgets('음식이 아니면 안내와 다시 찍기 버튼을 보여준다', (tester) async {
      final h = _Harness(
        analyze: (_) async => const FoodPhotoAnalysis(isFood: false, foods: []),
      );
      await _open(tester, h);

      expect(find.textContaining('사진에서 음식을 찾지 못했어요'), findsOneWidget);
      expect(find.text('다시 촬영'), findsOneWidget);
      expect(find.text('앨범에서 선택'), findsOneWidget);
      expect(_submitButton(), findsNothing);
    });

    testWidgets('무료 한도를 넘기면 다시 찍기를 막는다', (tester) async {
      final h = _Harness(
        analyze: (_) async =>
            throw const FoodPhotoQuotaExceeded('무료 이용은 하루 10회까지예요.'),
      );
      await _open(tester, h);

      expect(find.text('무료 이용은 하루 10회까지예요.'), findsOneWidget);
      expect(find.text('다시 시도'), findsNothing);
      final retake = tester.widget<ButtonStyleButton>(
        find.ancestor(
          of: find.text('다시 촬영'),
          matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
        ),
      );
      expect(retake.onPressed, isNull);
    });

    testWidgets('네트워크 오류면 같은 사진으로 다시 시도할 수 있다', (tester) async {
      var calls = 0;
      final h = _Harness(
        analyze: (_) async {
          calls++;
          if (calls == 1) throw const SocketException('offline');
          return _twoFoods;
        },
      );
      await _open(tester, h);

      expect(find.textContaining('인터넷 연결이 불안정해요'), findsOneWidget);
      await tester.tap(find.text('다시 시도'));
      await tester.pump();
      await tester.pump();

      expect(calls, 2);
      expect(find.text('인식된 음식 2개'), findsOneWidget);
    });

    testWidgets('분석 중에는 진행 상태를 보여주고 취소할 수 있다', (tester) async {
      final pending = Completer<FoodPhotoAnalysis>();
      final h = _Harness(analyze: (_) => pending.future);
      await _open(tester, h);

      expect(find.text('AI가 음식을 분석하고 있어요'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      await tester.tap(find.text('취소'));
      await tester.pumpAndSettle();
      expect(h.popped, isTrue);
      expect(h.results.single, isNull);

      // 화면을 닫은 뒤 결과가 와도 문제없어야 한다.
      pending.complete(_twoFoods);
      await tester.pump();
    });

    testWidgets('처음 사진 선택을 취소하면 화면을 닫는다', (tester) async {
      final h = _Harness(
        analyze: (_) async => _twoFoods,
        pickImage: (_) async => null,
      );
      await _open(tester, h);
      await tester.pumpAndSettle();

      expect(h.popped, isTrue);
      expect(h.results.single, isNull);
    });
  });
}
