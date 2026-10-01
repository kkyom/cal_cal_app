import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:image_picker/image_picker.dart';
import 'package:keyboard_actions/keyboard_actions.dart';
// import 'ad_banner_widget.dart'; // 광고 비활성화
import 'models.dart';
import 'firestore_service.dart';
import 'food_item.dart';
import 'food_detail_screen.dart';
import 'keyboard_actions_config.dart';
import 'center_toast.dart';
import 'my_diet_screen.dart';
import 'nutrition_label_scan_screen.dart';
import 'nutrition_scan_quota.dart';
import 'responsive_content.dart';
import 'support_screen.dart';
import 'support_service.dart';
// import 'subscription_screen.dart'; // 결제 비활성화
import 'dart:async';
import 'dart:convert' show jsonDecode;

const Duration _kSearchDebounce = Duration(milliseconds: 500);

/// `searchFood`가 배포된 리전(콘솔과 동일).
const String? _kFirebaseFunctionsRegion = 'asia-northeast3';

const String _kSearchUserError =
    '식품 정보를 불러오지 못했어요.\n잠시 후 다시 시도해 주세요.';

typedef OnFoodRecordAdd = void Function(FoodRecord food, {bool clearSearch});

String _searchErrorForUser(String detail) {
  debugPrint('식품 검색 오류: $detail');
  return _kSearchUserError;
}

String _fmt(double v) {
  if (v.isNaN || v.isInfinite) return '0';
  if ((v - v.round()).abs() < 0.05) return v.round().toString();
  return v.toStringAsFixed(1);
}

List<Map<dynamic, dynamic>> _normalizeItemRows(dynamic items) {
  if (items == null) return const [];
  if (items is List) {
    return items
        .whereType<Map>()
        .map((e) => Map<dynamic, dynamic>.from(e))
        .toList();
  }
  if (items is Map) {
    final m = Map<dynamic, dynamic>.from(items);
    if (m.containsKey('item')) {
      final it = m['item'];
      if (it is List) {
        return it
            .whereType<Map>()
            .map((e) => Map<dynamic, dynamic>.from(e))
            .toList();
      }
      if (it is Map) {
        return [Map<dynamic, dynamic>.from(it)];
      }
      return const [];
    }
    return [m];
  }
  return const [];
}

bool _mapLooksLikeGoKrApi(Map<dynamic, dynamic> m) =>
    m.containsKey('I2790') ||
    m.containsKey('response') ||
    (m.containsKey('header') && m.containsKey('body'));

Map<dynamic, dynamic>? _unwrapCallablePayload(dynamic data) {
  dynamic d = data;
  if (d is String) {
    final s = d.trim();
    if (s.isEmpty) return null;
    try {
      d = jsonDecode(s);
    } catch (_) {
      return null;
    }
  }
  if (d is! Map) return null;
  Map<dynamic, dynamic> m = Map<dynamic, dynamic>.from(d);

  if (_mapLooksLikeGoKrApi(m)) return m;

  for (final wrap in ['data', 'result', 'payload']) {
    final inner = m[wrap];
    if (inner is Map) {
      final im = Map<dynamic, dynamic>.from(inner);
      if (_mapLooksLikeGoKrApi(im)) return im;
      final inner2 = im['data'];
      if (inner2 is Map) {
        final im2 = Map<dynamic, dynamic>.from(inner2);
        if (_mapLooksLikeGoKrApi(im2)) return im2;
      }
    }
  }

  for (final e in m.entries) {
    final lc = e.key.toString().toLowerCase();
    if (lc == 'response' && e.value is Map) {
      return {'response': e.value};
    }
    if (lc == 'i2790' && e.value is Map) {
      return {'I2790': e.value};
    }
  }

  if (m.containsKey('body') && m['body'] is Map) {
    final hdr = m['header'];
    return {
      'response': {
        'header': hdr is Map
            ? hdr
            : const {'resultCode': '00', 'resultMsg': ''},
        'body': m['body'],
      },
    };
  }

  return m;
}

({List<FoodItem> items, String? error}) _parseHeaderAndBodyMaps(
  Map<dynamic, dynamic> header,
  Map<dynamic, dynamic> body,
  String fallbackQuery,
) {
  final code = header['resultCode']?.toString() ?? '';
  if (code.isNotEmpty && code != '00' && code != '03') {
    final msg = header['resultMsg']?.toString() ?? '';
    return (
      items: const [],
      error: _searchErrorForUser(
        msg.isNotEmpty ? msg : '검색 결과를 불러올 수 없어요 ($code)',
      ),
    );
  }
  final b = Map<dynamic, dynamic>.from(body);
  final rows = <Map<dynamic, dynamic>>[
    ..._normalizeItemRows(b['items']),
    ..._normalizeItemRows(b['item']),
  ];
  final items = <FoodItem>[];
  for (final r in rows) {
    items.add(FoodItem.fromApiRow(r, fallbackQuery));
  }
  return (items: items, error: null);
}

({List<FoodItem> items, String? error}) _parseSearchFoodPayload(
  dynamic data,
  String fallbackQuery,
) {
  final root = _unwrapCallablePayload(data);
  if (root == null) {
    final hint = data == null
        ? 'null'
        : '${data.runtimeType}${data is String ? " (JSON 파싱 실패 가능)" : ""}';
    return (
      items: const [],
      error: _searchErrorForUser('응답 형식이 올바르지 않아요. ($hint)'),
    );
  }

  final i2790 = root['I2790'];
  if (i2790 is Map) {
    final block = Map<dynamic, dynamic>.from(i2790);
    final result = block['RESULT'];
    if (result is Map) {
      final code = result['CODE']?.toString();
      final msg = result['MSG']?.toString();
      if (code != null && code != 'INFO-000') {
        return (
          items: const [],
          error: _searchErrorForUser(
            (msg != null && msg.isNotEmpty)
                ? msg
                : '검색 결과를 불러올 수 없어요 ($code)',
          ),
        );
      }
    }
    final rowsDyn = block['row'];
    if (rowsDyn is! List) {
      return (items: const [], error: null);
    }
    final items = <FoodItem>[];
    for (final r in rowsDyn) {
      if (r is! Map) continue;
      items.add(
        FoodItem.fromApiRow(Map<dynamic, dynamic>.from(r), fallbackQuery),
      );
    }
    return (items: items, error: null);
  }

  final response = root['response'];
  if (response is Map) {
    final resp = Map<dynamic, dynamic>.from(response);
    final header = resp['header'];
    final body = resp['body'];
    if (header is Map && body is Map) {
      return _parseHeaderAndBodyMaps(
        Map<dynamic, dynamic>.from(header),
        Map<dynamic, dynamic>.from(body),
        fallbackQuery,
      );
    }
    if (body is Map) {
      return _parseHeaderAndBodyMaps(
        header is Map
            ? Map<dynamic, dynamic>.from(header)
            : const {'resultCode': '00', 'resultMsg': ''},
        Map<dynamic, dynamic>.from(body),
        fallbackQuery,
      );
    }
    return (
      items: const [],
      error: _searchErrorForUser('응답에 body가 없습니다.'),
    );
  }

  final h = root['header'];
  final b = root['body'];
  if (h is Map && b is Map) {
    return _parseHeaderAndBodyMaps(
      Map<dynamic, dynamic>.from(h),
      Map<dynamic, dynamic>.from(b),
      fallbackQuery,
    );
  }

  final keys = root.keys.map((k) => k.toString()).take(12).join(', ');
  return (
    items: const [],
    error: _searchErrorForUser(
      '지원하지 않는 응답 형식입니다. 최상위 키: ${keys.isEmpty ? "(없음)" : keys}',
    ),
  );
}

FirebaseFunctions _firebaseFunctionsForSearch() {
  final r = _kFirebaseFunctionsRegion?.trim();
  if (r == null || r.isEmpty) return FirebaseFunctions.instance;
  return FirebaseFunctions.instanceFor(region: r);
}

// --- 음식 검색 화면 ---
class FoodSearchScreen extends StatefulWidget {
  final String mealName;
  final List<FoodRecord> initialFoods;

  const FoodSearchScreen({
    super.key,
    required this.mealName,
    this.initialFoods = const [],
  });

  @override
  State<FoodSearchScreen> createState() => _FoodSearchScreenState();
}

class _FoodSearchScreenState extends State<FoodSearchScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  bool _hasQuery = false;
  bool _isSearchFocused = false;

  late final List<FoodRecord> _recordedFoods;

  double? _tryParseGram(String raw) {
    final t = raw.trim().replaceAll(',', '.');
    if (t.isEmpty) return 0;
    final v = double.tryParse(t);
    if (v == null) return null;
    if (v.isNaN || v.isInfinite) return null;
    if (v < 0) return null;
    return v;
  }

  Future<void> _openDirectMemo() async {
    final record = await showModalBottomSheet<FoodRecord>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      constraints: const BoxConstraints(maxWidth: 560),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _DirectMemoSheet(tryParseGram: _tryParseGram),
    );

    if (!mounted) return;
    if (record != null) _addFood(record);
  }

  /// 검색 결과가 이상할 때 남기는 문의. 유형+메모를 받아 기존 문의 메일
  /// 파이프라인([SupportService.composeMail])에 얹는다.
  Future<void> _openSearchFeedbackSheet() async {
    final query = _searchCtrl.text.trim();
    final extraContent = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      constraints: const BoxConstraints(maxWidth: 560),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _SearchFeedbackSheet(query: query),
    );

    if (extraContent == null || !mounted) return;
    await composeSupportMail(
      context,
      SupportTopic.bug,
      contextLabel: query.isEmpty ? '음식 검색' : '음식 검색 (검색어: "$query")',
      extraContent: extraContent,
    );
  }

  /// "마이 식단"(즐겨찾는 음식) 목록에서 골라 현재 식사에 추가한다.
  Future<void> _openMyDiet() async {
    final record = await Navigator.push<FoodRecord>(
      context,
      MaterialPageRoute(builder: (_) => const MyDietScreen()),
    );
    if (!mounted) return;
    if (record != null) {
      _addFood(record);
    } else {
      // 마이 식단 화면에서 별 아이콘으로 삭제만 하고 돌아왔을 수 있으니,
      // 기록 목록의 별 아이콘 상태(저장 여부)를 다시 그려 동기화한다.
      setState(() {});
    }
  }

  /// 영양성분표를 촬영해 탄·단·지를 인식하고, 확인 화면에서 수정 후 기록한다.
  Future<void> _openNutritionLabelScan() async {
    _searchFocus.unfocus();

    // 다이얼로그에서 남은 횟수를 보여주므로, 다 썼어도 다이얼로그는 그대로
    // 띄운다 — 소진 여부는 화면 안에서 실제로 막는다.
    final quota = await fetchNutritionScanQuotaStatus();
    if (!mounted) return;

    final source = await _pickNutritionScanSource(quota);
    if (source == null || !mounted) return;

    final record = await Navigator.push<FoodRecord>(
      context,
      MaterialPageRoute(
        builder: (_) => NutritionLabelScanScreen(initialSource: source),
      ),
    );

    if (!mounted) return;
    if (record != null) _addFood(record);
  }

  /// "사진 촬영"/"앨범에서 선택"을 고르는 다이얼로그. 남은 무료 횟수도
  /// 같이 보여준다. 취소하면 null.
  Future<ImageSource?> _pickNutritionScanSource(
    NutritionScanQuotaStatus quota,
  ) {
    final quotaText = quota.isSubscribed
        ? 'AI 인식 무제한 이용 중'
        : '오늘 남은 무료 인식 ${quota.remaining}/$kFreeDailyScanLimit회';
    return showDialog<ImageSource>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 14, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '이미지로 간편 기록하기',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close, size: 20),
                    color: Colors.black38,
                    tooltip: '닫기',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              if (!quota.isExhausted) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2196F3).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    quotaText,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2196F3),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              if (quota.isExhausted)
                _ScanQuotaExhaustedNotice(
                  onSubscribeTap: () {
                    Navigator.pop(ctx);
                    // 결제 비활성화로 구독 화면 이동 임시 제거
                    // if (!mounted) return;
                    // Navigator.push(
                    //   context,
                    //   MaterialPageRoute(
                    //     builder: (_) => const SubscriptionScreen(),
                    //   ),
                    // );
                  },
                )
              else ...[
                _ScanSourceOption(
                  icon: Icons.photo_camera_outlined,
                  label: '사진 촬영',
                  description: '카메라로 바로 촬영해요',
                  onTap: () => Navigator.pop(ctx, ImageSource.camera),
                ),
                const SizedBox(height: 10),
                _ScanSourceOption(
                  icon: Icons.photo_library_outlined,
                  label: '앨범에서 선택',
                  description: '저장된 사진을 불러와요',
                  onTap: () => Navigator.pop(ctx, ImageSource.gallery),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  double get _totalKcal => _recordedFoods.fold(0, (sum, f) => sum + f.kcal);
  double get _carbKcal => _recordedFoods.fold(0, (sum, f) => sum + f.carb * 4);
  double get _proteinKcal =>
      _recordedFoods.fold(0, (sum, f) => sum + f.protein * 4);
  double get _fatKcal => _recordedFoods.fold(0, (sum, f) => sum + f.fat * 9);

  double _macroPercent(double macroKcal) {
    if (_totalKcal == 0) return 0;
    return (macroKcal / _totalKcal * 100).clamp(0, 100);
  }

  /// 검색/API 기반 동일 식품인지 — 이름·단위·단위당 영양으로 판별.
  bool _sameSourceFood(FoodRecord a, FoodRecord b) {
    final aj = a.sourceFoodItemJson;
    final bj = b.sourceFoodItemJson;
    if (aj == null || bj == null || aj.isEmpty || bj.isEmpty) return false;

    bool numEq(dynamic x, dynamic y) {
      final dx = (x as num?)?.toDouble();
      final dy = (y as num?)?.toDouble();
      if (dx == null || dy == null) return dx == dy;
      return (dx - dy).abs() < 1e-9;
    }

    return aj['name'] == bj['name'] &&
        aj['servingUnit'] == bj['servingUnit'] &&
        numEq(aj['kcalPerUnit'], bj['kcalPerUnit']) &&
        numEq(aj['carbPerUnit'], bj['carbPerUnit']) &&
        numEq(aj['proteinPerUnit'], bj['proteinPerUnit']) &&
        numEq(aj['fatPerUnit'], bj['fatPerUnit']);
  }

  void _addFood(FoodRecord food, {bool clearSearch = true}) {
    setState(() {
      final canMerge = food.sourceFoodItemJson != null &&
          food.sourceFoodItemJson!.isNotEmpty;
      final mergeIndex = canMerge
          ? _recordedFoods.indexWhere((e) => _sameSourceFood(e, food))
          : -1;

      if (mergeIndex >= 0) {
        final existing = _recordedFoods[mergeIndex];
        final totalAmount = (existing.sourceLoggedAmount ?? 0) +
            (food.sourceLoggedAmount ?? 0);
        final item = FoodItem.fromJson(existing.sourceFoodItemJson!);
        _recordedFoods[mergeIndex] = item.toRecord(totalAmount);
      } else {
        _recordedFoods.add(food);
      }

      if (clearSearch) {
        _searchCtrl.clear();
        _searchFocus.unfocus();
      }
    });
    showCenterToast(context, '음식 추가 완료!');
  }

  void _removeFood(int index) {
    setState(() => _recordedFoods.removeAt(index));
  }

  bool _sameFood(FoodRecord a, FoodRecord b) =>
      a.name == b.name &&
      a.carb == b.carb &&
      a.protein == b.protein &&
      a.fat == b.fat &&
      a.fiber == b.fiber &&
      a.kcalOverride == b.kcalOverride &&
      a.sourceLoggedAmount == b.sourceLoggedAmount;

  bool get _hasChanges {
    final initial = widget.initialFoods;
    if (initial.length != _recordedFoods.length) return true;
    for (var i = 0; i < initial.length; i++) {
      if (!_sameFood(initial[i], _recordedFoods[i])) return true;
    }
    return false;
  }

  /// 뒤로가기 / 스와이프: 저장하지 않고 나간다.
  /// 음식이 없거나 변경이 없으면 바로 닫고, 변경이 있으면 확인한다.
  Future<void> _discardAndLeave() async {
    if (_recordedFoods.isEmpty || !_hasChanges) {
      if (mounted) Navigator.pop(context);
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '저장하지 않고 나갈까요?',
          style: TextStyle(
            color: Color(0xFF3F5F8B),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: const Text(
          '변경한 내용이 저장되지 않습니다.',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF767474).withValues(alpha: 0.8),
              textStyle: const TextStyle(fontWeight: FontWeight.bold),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF3F5F8B).withValues(alpha: 0.8),
              textStyle: const TextStyle(fontWeight: FontWeight.bold),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('나가기'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.pop(context);
  }

  void _completeAndLeave() {
    Navigator.pop(context, _recordedFoods);
  }

  Future<void> _openRecordedFoodDetail(int index) async {
    final old = _recordedFoods[index];
    final item = FoodItem.fromFoodRecord(old);
    final record = await Navigator.push<FoodRecord>(
      context,
      MaterialPageRoute(
        builder: (_) => FoodDetailScreen(
          food: item,
          initialInputAmount: old.sourceLoggedAmount,
        ),
      ),
    );
    if (!mounted) return;
    if (record != null) {
      setState(() => _recordedFoods[index] = record);
    }
  }

  @override
  void initState() {
    super.initState();
    _recordedFoods = List.from(widget.initialFoods);
    _searchCtrl.addListener(() {
      setState(() => _hasQuery = _searchCtrl.text.trim().isNotEmpty);
    });
    _searchFocus.addListener(() {
      setState(() => _isSearchFocused = _searchFocus.hasFocus);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool hasFoods = _recordedFoods.isNotEmpty;
    final bool showRecordedList = hasFoods && !_hasQuery && !_isSearchFocused;

    return Scaffold(
      backgroundColor: Colors.white,
      // 검색창 포커스 시에도 하단 '기록 완료' 버튼이 제자리에 남도록 한다.
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios,
            color: Colors.black87,
            size: 20,
          ),
          onPressed: _discardAndLeave,
        ),
        title: Text(
          widget.mealName,
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(
              Icons.error_outline,
              color: Colors.black26,
              size: 20,
            ),
            tooltip: '검색 결과가 이상하면 알려주세요',
            onPressed: _openSearchFeedbackSheet,
          ),
        ],
      ),
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _discardAndLeave();
        },
        child: Stack(
          children: [
            ResponsiveContent(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 검색바 + 액션 버튼
                  Container(
                    color: const Color(0xFFF2F2F2),
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: const Color(0xFFE0E0E0)),
                          ),
                          child: TextField(
                            controller: _searchCtrl,
                            focusNode: _searchFocus,
                            textInputAction: TextInputAction.search,
                            style: const TextStyle(
                              fontSize: 15,
                              color: Colors.black87,
                            ),
                            decoration: InputDecoration(
                              hintText: '음식명을 검색하세요',
                              hintStyle: const TextStyle(
                                color: Colors.black38,
                                fontSize: 15,
                              ),
                              prefixIcon: const Icon(
                                Icons.search,
                                color: Colors.black45,
                                size: 22,
                              ),
                              suffixIcon: _hasQuery
                                  ? IconButton(
                                      icon: const Icon(
                                        Icons.clear,
                                        color: Colors.black38,
                                        size: 20,
                                      ),
                                      onPressed: () => _searchCtrl.clear(),
                                    )
                                  : null,
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 10),

                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _MyDietButton(onPressed: _openMyDiet),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.end,
                              children: [
                                _SearchActionButton(
                                  label: '이미지로 기록',
                                  onPressed: _openNutritionLabelScan,
                                ),
                                _SearchActionButton(
                                  label: '직접 기록',
                                  onPressed: _openDirectMemo,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // 영양 요약 (기록된 음식이 있을 때만; 목록과 동시에 표시)
                  if (showRecordedList)
                    _NutritionSummary(
                      totalKcal: _totalKcal,
                      carbPercent: _macroPercent(_carbKcal),
                      proteinPercent: _macroPercent(_proteinKcal),
                      fatPercent: _macroPercent(_fatKcal),
                    ),

                  // 검색 결과 / 기록 목록 / 빈 상태
                  Expanded(
                    child: _hasQuery
                        ? _SearchResults(
                            query: _searchCtrl.text,
                            onAdd: _addFood,
                          )
                        : showRecordedList
                        ? _RecordedFoodList(
                            foods: _recordedFoods,
                            onDelete: _removeFood,
                            onTapFood: _openRecordedFoodDetail,
                          )
                        : const _EmptyState(),
                  ),

                  const SizedBox(height: 8),
                  // Center(child: AdBannerWidget(adUnitId: AdUnitIds.foodSearch)), // 광고 비활성화
                  const SizedBox(height: 8),

                  // 기록 완료 버튼 (검색 결과 목록이 아닐 때만 표시)
                  if (!_hasQuery)
                    SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _completeAndLeave,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999),
                              ),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 18),
                            ),
                            child: const Text(
                              '기록 완료',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 검색 화면 상단 액션 칩 (직접 기록 / 바코드 인식 / 이미지로 기록).
class _SearchActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _SearchActionButton({
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF2196F3),
        foregroundColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 검색 화면 상단의 "마이 식단"(즐겨찾는 음식) 진입 버튼.
class _MyDietButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _MyDietButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(
        Icons.star_border_rounded,
        size: 18,
        color: Color(0xFFFFC107),
      ),
      label: const Text(
        '마이 식단',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Colors.black87,
        ),
      ),
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        side: const BorderSide(color: Color(0xFFE0E0E0)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
    );
  }
}

/// 음식 카드에 붙는 별 아이콘 — 눌러서 "마이 식단"에 저장/삭제를 토글한다.
class _FavoriteStarButton extends StatefulWidget {
  final FoodItem food;

  /// 삭제(−) 아이콘 등 옆에 바로 붙여야 할 때 탭 영역을 좁혀 간격을 줄인다.
  final bool compact;

  const _FavoriteStarButton({required this.food, this.compact = false});

  @override
  State<_FavoriteStarButton> createState() => _FavoriteStarButtonState();
}

class _FavoriteStarButtonState extends State<_FavoriteStarButton> {
  late bool _saved;

  @override
  void initState() {
    super.initState();
    _saved = FirestoreService.isInMyDiet(widget.food);
  }

  @override
  void didUpdateWidget(covariant _FavoriteStarButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.food != widget.food) {
      _saved = FirestoreService.isInMyDiet(widget.food);
    }
  }

  void _toggle() {
    setState(() {
      if (_saved) {
        FirestoreService.removeFromMyDietMatching(widget.food);
        _saved = false;
      } else {
        FirestoreService.addToMyDiet(widget.food);
        _saved = true;
      }
    });
    showCenterToast(
      context,
      _saved ? '마이 식단에 저장했어요' : '마이 식단에서 삭제했어요',
    );
  }

  @override
  Widget build(BuildContext context) {
    final boxSize = widget.compact ? 28.0 : 36.0;
    return IconButton(
      onPressed: _toggle,
      icon: Icon(
        _saved ? Icons.star_rounded : Icons.star_border_rounded,
        color: const Color(0xFFFFC107),
        size: widget.compact ? 20 : 22,
      ),
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(minWidth: boxSize, minHeight: boxSize),
      tooltip: _saved ? '마이 식단에서 삭제' : '마이 식단에 저장',
    );
  }
}

/// "이미지로 간편 기록하기" 다이얼로그의 선택지 한 줄(아이콘 + 라벨 + 설명).
class _ScanSourceOption extends StatelessWidget {
  const _ScanSourceOption({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF6F8FB),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: const Color(0xFF2196F3), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black45,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.black26, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// 오늘 무료 인식을 다 썼을 때 촬영/앨범 선택지 대신 보여주는 안내.
/// [onSubscribeTap]은 원래 구독 화면으로 이동시켰다 (결제 비활성화로 현재는 다이얼로그만 닫음).
class _ScanQuotaExhaustedNotice extends StatelessWidget {
  const _ScanQuotaExhaustedNotice({required this.onSubscribeTap});

  final VoidCallback onSubscribeTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF6F8FB),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.bedtime_outlined,
                  color: Color(0xFF2196F3),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '오늘 무료 인식을 모두 사용했어요',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '내일 다시 $kFreeDailyScanLimit회 무료로 이용할 수 있어요',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black45,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Material(
          color: const Color(0xFF2196F3),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onSubscribeTap,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: Text(
                  '구독하고 기능 제한 없이 사용하기',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// --- 영양성분 요약 섹션 ---
class _NutritionSummary extends StatelessWidget {
  final double totalKcal;
  final double carbPercent;
  final double proteinPercent;
  final double fatPercent;

  const _NutritionSummary({
    required this.totalKcal,
    required this.carbPercent,
    required this.proteinPercent,
    required this.fatPercent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '총 ${totalKcal.toStringAsFixed(0)}kcal',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          _MacroBar(
            label: '탄수화물',
            percent: carbPercent,
            color: const Color(0xFF34C759),
          ),
          const SizedBox(height: 6),
          _MacroBar(
            label: '단백질',
            percent: proteinPercent,
            color: const Color(0xFF2196F3),
          ),
          const SizedBox(height: 6),
          _MacroBar(
            label: '지방',
            percent: fatPercent,
            color: const Color(0xFFF5A623),
          ),
        ],
      ),
    );
  }
}

// --- 매크로 바 ---
class _MacroBar extends StatelessWidget {
  final String label;
  final double percent;
  final Color color;

  const _MacroBar({
    required this.label,
    required this.percent,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final double ratio = (percent / 100).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            Text(
              '${percent.toStringAsFixed(0)}%',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Stack(
          children: [
            Container(
              height: 14,
              decoration: BoxDecoration(
                color: const Color(0xFFEEEEEE),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            FractionallySizedBox(
              widthFactor: ratio,
              child: Container(
                height: 14,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DirectMemoSheet extends StatefulWidget {
  final double? Function(String raw) tryParseGram;

  const _DirectMemoSheet({required this.tryParseGram});

  @override
  State<_DirectMemoSheet> createState() => _DirectMemoSheetState();
}

class _DirectMemoSheetState extends State<_DirectMemoSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _carbCtrl;
  late final TextEditingController _proteinCtrl;
  late final TextEditingController _fatCtrl;
  late final TextEditingController _fiberCtrl;

  final FocusNode _nameFocus = FocusNode();
  final FocusNode _amountFocus = FocusNode();
  final FocusNode _carbFocus = FocusNode();
  final FocusNode _proteinFocus = FocusNode();
  final FocusNode _fatFocus = FocusNode();
  final FocusNode _fiberFocus = FocusNode();

  late final List<FocusNode> _focusNodes;

  bool get _hasFieldFocus => _focusNodes.any((n) => n.hasFocus);

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _amountCtrl = TextEditingController();
    _carbCtrl = TextEditingController();
    _proteinCtrl = TextEditingController();
    _fatCtrl = TextEditingController();
    _fiberCtrl = TextEditingController();
    _focusNodes = [
      _nameFocus,
      _amountFocus,
      _carbFocus,
      _proteinFocus,
      _fatFocus,
      _fiberFocus,
    ];
    for (final node in _focusNodes) {
      node.addListener(_onFocusChanged);
    }
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final node in _focusNodes) {
      node.removeListener(_onFocusChanged);
    }
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    _carbCtrl.dispose();
    _proteinCtrl.dispose();
    _fatCtrl.dispose();
    _fiberCtrl.dispose();
    _nameFocus.dispose();
    _amountFocus.dispose();
    _carbFocus.dispose();
    _proteinFocus.dispose();
    _fatFocus.dispose();
    _fiberFocus.dispose();
    super.dispose();
  }

  void _submit() {
    if (!mounted) return;
    final name = _nameCtrl.text.trim();
    final amount = widget.tryParseGram(_amountCtrl.text);
    final carb = widget.tryParseGram(_carbCtrl.text);
    final protein = widget.tryParseGram(_proteinCtrl.text);
    final fat = widget.tryParseGram(_fatCtrl.text);
    final fiber = widget.tryParseGram(_fiberCtrl.text);

    if (name.isEmpty) return;
    if (amount == null || amount <= 0) return;
    if (carb == null || protein == null || fat == null || fiber == null) {
      return;
    }
    if ((carb + protein + fat) <= 0) return;
    if (fiber > carb) return;

    FocusScope.of(context).unfocus();
    Navigator.pop(
      context,
      FoodRecord(
        name: name,
        carb: carb,
        protein: protein,
        fat: fat,
        fiber: fiber,
        sourceLoggedAmount: amount,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    // 툴바 패딩은 포커스에 묶어 키보드 dismiss와 동시에 줄인다.
    // (viewInsets == 0이 된 뒤에 +45를 빼면 한 단계 더 떨어지는 느낌이 난다.)
    final barInset = _hasFieldFocus ? kKeyboardActionsBarHeight : 0.0;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: AnimatedPadding(
        // 올라올 때는 즉시, 내려갈 때만 툴바 dismiss와 맞춘다.
        duration: barInset > 0
            ? Duration.zero
            : const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: barInset),
        child: KeyboardActions(
          disableScroll: true,
          config: buildKeyboardActionsConfig(_focusNodes),
          child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E5EA),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '직접 기록',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            color: Colors.black87,
                            letterSpacing: -0.3,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          '음식명과 영양 정보를 입력해 주세요',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.black45,
                          ),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF2F2F2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.close,
                        size: 18,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _DirectMemoField(
                controller: _nameCtrl,
                focusNode: _nameFocus,
                label: '음식명',
                icon: Icons.restaurant_menu_rounded,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              _MacroField(
                controller: _amountCtrl,
                focusNode: _amountFocus,
                label: '먹은양',
                color: const Color(0xFF757575),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _MacroField(
                      controller: _carbCtrl,
                      focusNode: _carbFocus,
                      label: '탄수화물',
                      color: const Color(0xFF34C759),
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MacroField(
                      controller: _proteinCtrl,
                      focusNode: _proteinFocus,
                      label: '단백질',
                      color: const Color(0xFF2196F3),
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MacroField(
                      controller: _fatCtrl,
                      focusNode: _fatFocus,
                      label: '지방',
                      color: const Color(0xFFF5A623),
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _MacroField(
                controller: _fiberCtrl,
                focusNode: _fiberFocus,
                label: '식이섬유',
                color: const Color(0xFF8D6E63),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  child: const Text(
                    '기록 완료',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
          ),
        ),
      ),
    );
  }
}

/// "검색 결과가 이상해요" 문의 시트 — 유형 선택(필수) + 메모(선택).
class _SearchFeedbackSheet extends StatefulWidget {
  final String query;

  const _SearchFeedbackSheet({required this.query});

  @override
  State<_SearchFeedbackSheet> createState() => _SearchFeedbackSheetState();
}

class _SearchFeedbackSheetState extends State<_SearchFeedbackSheet> {
  static const _categories = [
    '브랜드/제조사가 이상해요',
    '영양성분이 틀린 것 같아요',
    '이름이 이상해요(오타 등)',
    '찾는 음식이 없어요',
    '기타',
  ];

  final _noteCtrl = TextEditingController();
  String? _selectedCategory;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  /// 시트는 메일을 직접 열지 않고, 조합한 내용만 호출부(부모 State)에
  /// 반환한다 — pop 이후의 이 위젯 context로 비동기 작업을 이어가지 않기 위함.
  void _submit() {
    final category = _selectedCategory;
    if (category == null) return;
    final note = _noteCtrl.text.trim();
    final extraContent = '[문의] $category${note.isEmpty ? '' : '\n$note'}';
    Navigator.pop(context, extraContent);
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E5EA),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const Text(
                '검색 결과가 이상하신가요',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              for (final category in _categories)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _SearchFeedbackCategoryRow(
                    label: category,
                    selected: _selectedCategory == category,
                    onTap: () => setState(() => _selectedCategory = category),
                  ),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: _noteCtrl,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  hintText: '자세히 알려주시면 도움이 돼요 (선택)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _selectedCategory == null ? null : _submit,
                child: const Text('문의 보내기'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 검색 결과 문의 시트의 유형 선택 한 줄 — 전부 같은 너비로 깔끔하게 정렬되도록
/// Wrap+ChoiceChip 대신 세로로 쌓는 카드 리스트로 구성한다.
class _SearchFeedbackCategoryRow extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SearchFeedbackCategoryRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEAF0FB) : const Color(0xFFF8F8F8),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? const Color(0xFF3F5F8B)
                : const Color(0xFFEEEEEE),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.black87,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
              size: 20,
              color: selected ? const Color(0xFF3F5F8B) : Colors.black26,
            ),
          ],
        ),
      ),
    );
  }
}

/// 직접 기록 시트의 음식명 입력 필드 (아이콘 + 라벨).
class _DirectMemoField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final IconData icon;
  final TextInputAction textInputAction;

  const _DirectMemoField({
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.icon,
    required this.textInputAction,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      textInputAction: textInputAction,
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 15),
        prefixIcon: Icon(icon, size: 21, color: Colors.black45),
        filled: true,
        fillColor: const Color(0xFFF6F8FB),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.black87, width: 1.4),
        ),
      ),
    );
  }
}

/// 직접 기록 시트의 탄/단/지 입력 카드 (매크로 색상 강조).
class _MacroField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final Color color;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;

  const _MacroField({
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.color,
    required this.textInputAction,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          TextField(
            controller: controller,
            focusNode: focusNode,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
            ),
            textInputAction: textInputAction,
            onSubmitted: onSubmitted,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              hintText: '0',
              hintStyle: TextStyle(
                fontSize: 18,
                color: Colors.black26,
                fontWeight: FontWeight.w600,
              ),
              suffixText: 'g',
              suffixStyle: TextStyle(
                fontSize: 13,
                color: Colors.black38,
                fontWeight: FontWeight.w600,
              ),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }
}

// --- 기록된 음식 목록 ---
class _RecordedFoodList extends StatelessWidget {
  final List<FoodRecord> foods;
  final ValueChanged<int> onDelete;
  final ValueChanged<int> onTapFood;

  const _RecordedFoodList({
    required this.foods,
    required this.onDelete,
    required this.onTapFood,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      itemCount: foods.length,
      separatorBuilder: (_, i) => const SizedBox(height: 8),
      itemBuilder: (_, index) {
        final food = foods[index];
        final unit =
            (food.sourceFoodItemJson?['servingUnit'] as String?) ?? 'g';
        final amount = food.sourceLoggedAmount;
        final amountPrefix =
            amount != null && amount > 0 ? '${_fmt(amount)}$unit · ' : '';
        final nutritionLine =
            '$amountPrefix${food.kcal.toStringAsFixed(0)} kcal  탄 ${food.carb.toStringAsFixed(0)}g  단 ${food.protein.toStringAsFixed(0)}g  지 ${food.fat.toStringAsFixed(0)}g';
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F8F8),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFEEEEEE)),
          ),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => onTapFood(index),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          food.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.black87,
                          ),
                        ),
                        Text(
                          nutritionLine,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black38,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              _FavoriteStarButton(
                food: FoodItem.fromFoodRecordAtLoggedAmount(food),
                compact: true,
              ),
              IconButton(
                onPressed: () => onDelete(index),
                icon: const Icon(
                  Icons.remove_circle_outline,
                  color: Colors.redAccent,
                  size: 20,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: '삭제',
              ),
            ],
          ),
        );
      },
    );
  }
}

// --- 빈 상태 위젯 ---
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search, size: 56, color: Color(0xFFDDDDDD)),
          SizedBox(height: 14),
          Text(
            '찾고있는 음식명을 검색해보세요!',
            style: TextStyle(color: Color(0xFFBBBBBB), fontSize: 15),
          ),
        ],
      ),
    );
  }
}

// --- 검색 결과 위젯 ---
class _SearchResults extends StatelessWidget {
  final String query;
  final OnFoodRecordAdd onAdd;

  const _SearchResults({required this.query, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return _RemoteSearchResults(query: query, onAdd: onAdd);
  }
}

class _RemoteSearchResults extends StatefulWidget {
  final String query;
  final OnFoodRecordAdd onAdd;

  const _RemoteSearchResults({required this.query, required this.onAdd});

  @override
  State<_RemoteSearchResults> createState() => _RemoteSearchResultsState();
}

class _RemoteSearchResultsState extends State<_RemoteSearchResults> {
  Timer? _debounce;
  bool _loading = false;
  String? _error;
  List<FoodItem> _results = const [];

  @override
  void initState() {
    super.initState();
    _scheduleFetch();
  }

  @override
  void didUpdateWidget(covariant _RemoteSearchResults oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query.trim() != widget.query.trim()) {
      _scheduleFetch();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _scheduleFetch() {
    _debounce?.cancel();
    final q = widget.query.trim();
    _debounce = Timer(_kSearchDebounce, () {
      _fetch(q);
    });
  }

  Future<void> _fetch(String q) async {
    if (!mounted) return;
    if (q.isEmpty) {
      setState(() {
        _loading = false;
        _error = null;
        _results = const [];
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final fn = _firebaseFunctionsForSearch();
      final callable = fn.httpsCallable(
        'searchFood',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 45)),
      );
      final res = await callable.call({'query': q, 'searchQuery': q});
      final parsed = _parseSearchFoodPayload(res.data, q);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _results = parsed.items;
        _error = parsed.error;
      });
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _results = const [];
        _error = _searchErrorForUser(
          '[${e.code}] ${e.message ?? '검색 중 오류가 발생했습니다.'}',
        );
      });
    } catch (e, st) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _results = const [];
        _error = _searchErrorForUser('검색 중 오류가 발생했습니다. $e\n$st');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: () => _fetch(widget.query.trim()),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('다시 시도'),
                  ),
                  const SupportReportButton(contextLabel: '음식 검색'),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (_results.isEmpty) {
      return const Center(
        child: Text('검색 결과가 없어요', style: TextStyle(color: Colors.black45)),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      itemCount: _results.length,
      separatorBuilder: (_, index) => const SizedBox(height: 8),
      itemBuilder: (ctx, index) {
        final item = _results[index];
        final n = _fmt;
        final servingLabel = item.rawServingSize.isNotEmpty
            ? item.rawServingSize
            : '${item.servingAmount.toStringAsFixed(0)}${item.servingUnit}';
        final nutritionLine =
            '${n(item.kcal)}kcal · 탄 ${n(item.carb)}g · 단 ${n(item.protein)}g · 지 ${n(item.fat)}g';

        return Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F8F8),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFEEEEEE)),
          ),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final record = await Navigator.push<FoodRecord>(
                      ctx,
                      MaterialPageRoute(
                        builder: (_) => FoodDetailScreen(food: item),
                      ),
                    );
                    if (record != null) {
                      widget.onAdd(record, clearSearch: true);
                    }
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (item.brand.isNotEmpty) ...[
                          Text(
                            item.brand,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Colors.black45,
                            ),
                          ),
                          const SizedBox(height: 2),
                        ],
                        Text(
                          item.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          servingLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black45,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          nutritionLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black38,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              _FavoriteStarButton(food: item, compact: true),
              IconButton(
                onPressed: () => widget.onAdd(
                  item.toRecord(item.servingAmount),
                  clearSearch: true,
                ),
                icon: const Icon(
                  Icons.add_circle_outline,
                  color: Color(0xFF2196F3),
                  size: 22,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 28,
                  minHeight: 28,
                ),
                tooltip: '바로 추가',
              ),
            ],
          ),
        );
      },
    );
  }
}
