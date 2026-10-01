import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:keyboard_actions/keyboard_actions.dart';

import 'food_detail_screen.dart';
import 'food_item.dart';
import 'keyboard_actions_config.dart';
import 'models.dart';
import 'nutrition_label_ocr.dart';
import 'nutrition_scan_quota.dart';
import 'responsive_content.dart';
import 'support_screen.dart';

/// `parseNutritionLabel` Cloud Function 리전.
const String _kFirebaseFunctionsRegion = 'asia-northeast3';

/// 업로드·비용 절감을 위한 촬영 리사이즈.
///
/// 즉석 촬영(카메라)은 갤러리 사진보다 흔들림·초점 영향을 더 받아
/// 작은 `kcal` 숫자가 리사이즈 후 뭉개지기 쉽다. Cloud Function 업로드
/// 상한(4MB, [MAX_IMAGE_BYTES] in functions/index.js)에는 여유가 있다.
///
/// maxWidth는 Gemini의 768px 타일 경계를 의식해서 잡는다 — 1536은
/// 세로 사진 기준 타일 수를 1920 대비 한 단계 줄여 처리 속도를 높이면서도
/// (모델을 gemini-3.1-flash-lite로 올린 뒤) kcal 인식은 유지되는 값이다.
const int _kScanMaxWidth = 1536;
const int _kScanImageQuality = 90;

/// 서버(`parseNutritionLabel`)가 무료 일일 한도 초과로 거부했을 때
/// 일반 오류와 구분해 그대로 상위로 전달하기 위한 마커.
class _NutritionScanQuotaExceeded implements Exception {
  const _NutritionScanQuotaExceeded(this.message);

  final String message;
}

/// 영양성분표를 촬영해 탄·단·지를 인식하고, 사용자가 확인·수정한 뒤
/// [FoodRecord]로 반환하는 화면.
///
/// 인식은 Gemini(Cloud Function)로 한다. 실패하면 사진과 입력 폼을
/// 남겨 사용자가 값을 직접 입력하도록 유도한다.
class NutritionLabelScanScreen extends StatefulWidget {
  const NutritionLabelScanScreen({
    super.key,
    this.initialSource = ImageSource.camera,
  });

  /// 화면 진입 시 바로 열 소스. 검색 화면에서 "사진 촬영"/"앨범에서 선택"
  /// 중 이미 골라서 넘어오므로, 여기서 다시 고르게 하지 않는다.
  final ImageSource initialSource;

  @override
  State<NutritionLabelScanScreen> createState() =>
      _NutritionLabelScanScreenState();
}

class _NutritionLabelScanScreenState extends State<NutritionLabelScanScreen> {
  final ImagePicker _picker = ImagePicker();

  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _amountCtrl = TextEditingController();
  final TextEditingController _carbCtrl = TextEditingController();
  final TextEditingController _proteinCtrl = TextEditingController();
  final TextEditingController _fatCtrl = TextEditingController();
  final TextEditingController _kcalCtrl = TextEditingController();

  final FocusNode _nameFocus = FocusNode();
  final FocusNode _amountFocus = FocusNode();
  final FocusNode _carbFocus = FocusNode();
  final FocusNode _proteinFocus = FocusNode();
  final FocusNode _fatFocus = FocusNode();
  final FocusNode _kcalFocus = FocusNode();

  late final List<FocusNode> _focusNodes = [
    _nameFocus,
    _amountFocus,
    _carbFocus,
    _proteinFocus,
    _fatFocus,
    _kcalFocus,
  ];

  String _unit = 'g';
  String? _imagePath;
  bool _busy = true;
  String? _error;

  /// 마지막 실패가 네트워크·서버 일시 오류라 같은 사진으로 재시도하면
  /// 복구될 수 있는 상태. true일 때만 "다시 시도" 버튼을 노출한다.
  bool _retriable = false;
  NutritionLabelReading _reading = NutritionLabelReading.empty;

  /// 오늘 무료 인식 횟수를 다 써서 서버가 거부한 상태. true면 재촬영·앨범
  /// 선택 버튼을 막아 더 이상 인식을 시도하지 않는다(직접 입력은 계속 가능).
  bool _quotaExceeded = false;

  /// 다시 촬영 시 이전 사진 경로도 남겨 두었다가 화면을 나갈 때 함께 지운다.
  final Set<String> _capturedImagePaths = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scan(widget.initialSource, popIfCancelled: true);
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    _carbCtrl.dispose();
    _proteinCtrl.dispose();
    _fatCtrl.dispose();
    _kcalCtrl.dispose();
    for (final node in _focusNodes) {
      node.dispose();
    }
    _deleteCapturedImages();
    super.dispose();
  }

  /// FoodRecord에는 이미지가 포함되지 않으므로, 이 화면을 벗어나면
  /// (기록 추가·뒤로가기 모두) 촬영 중 남긴 임시 사진 파일을 정리한다.
  void _deleteCapturedImages() {
    for (final path in _capturedImagePaths) {
      try {
        final file = File(path);
        if (file.existsSync()) file.deleteSync();
      } catch (e) {
        debugPrint('스캔 임시 이미지 삭제 실패: $e');
      }
    }
    _capturedImagePaths.clear();
  }

  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: _kFirebaseFunctionsRegion);

  /// 서버가 `consumeNutritionScanQuota`로 갱신하는 문서를 실시간 구독해
  /// 남은 횟수 표시를 스캔 직후 바로 갱신한다. 별도로 다시 불러올 필요 없음.
  Stream<DocumentSnapshot<Map<String, dynamic>>>? get _quotaStream =>
      nutritionScanQuotaStream();

  // ── 촬영 · 인식 ─────────────────────────────────────────────

  Future<void> _scan(
    ImageSource source, {
    bool popIfCancelled = false,
  }) async {
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _retriable = false;
    });

    final XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: source,
        maxWidth: _kScanMaxWidth.toDouble(),
        imageQuality: _kScanImageQuality,
      );
    } catch (e) {
      debugPrint('영양성분표 사진 선택 실패: $e');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '카메라·사진 접근 권한을 확인해 주세요.';
      });
      if (popIfCancelled && _imagePath == null) Navigator.pop(context);
      return;
    }

    if (!mounted) return;
    if (picked == null) {
      setState(() => _busy = false);
      if (popIfCancelled && _imagePath == null) Navigator.pop(context);
      return;
    }

    // 인식 실패해도 사진과 입력 폼은 남겨 직접 입력할 수 있게 한다.
    setState(() => _imagePath = picked!.path);
    _capturedImagePaths.add(picked.path);

    // 네이티브 카메라에서 복귀한 직후 포커스/제스처 상태가 꼬일 수 있어 정리한다.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;
    FocusManager.instance.primaryFocus?.unfocus();

    await _recognizeAndApply(File(picked.path));
  }

  /// 마지막으로 찍은 사진으로 인식만 다시 시도한다. 네트워크 순단 등으로
  /// 실패했을 때 재촬영 없이 복구하는 용도.
  Future<void> _retryRecognition() async {
    final path = _imagePath;
    if (path == null || _busy || _quotaExceeded) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _retriable = false;
    });
    await _recognizeAndApply(File(path));
  }

  /// [file]을 Gemini로 인식해 폼에 반영한다. 실패해도 사진과 입력 폼은
  /// 그대로 두어 사용자가 값을 직접 입력할 수 있게 한다.
  Future<void> _recognizeAndApply(File file) async {
    try {
      final reading = await _recognizeLabel(file);
      if (!mounted) return;
      setState(() {
        _reading = reading;
        _busy = false;
        _retriable = false;
        _error = reading.hasAnyMacro
            ? null
            : '값을 인식하지 못했어요. 표가 화면에 꽉 차도록 다시 촬영하거나 직접 입력해 주세요.';
        _applyReading(reading);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        FocusManager.instance.primaryFocus?.unfocus();
      });
    } on _NutritionScanQuotaExceeded catch (e) {
      debugPrint('영양성분표 인식 한도 초과: ${e.message}');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _retriable = false;
        _quotaExceeded = true;
        _reading = NutritionLabelReading.empty;
        _error = e.message;
      });
    } on FirebaseFunctionsException catch (e) {
      debugPrint('영양성분표 인식 실패(functions): ${e.code} / ${e.message}');
      if (!mounted) return;
      setState(() {
        _busy = false;
        // 서버·네트워크 일시 오류는 같은 사진으로 재시도하면 복구될 수 있다.
        _retriable = true;
        _reading = NutritionLabelReading.empty;
        _error = _isNetworkErrorCode(e.code)
            ? '인터넷 연결이 불안정해요. 연결을 확인하고 다시 시도해 주세요.'
            : '지금은 인식이 원활하지 않아요. 잠시 후 다시 시도하거나 값을 직접 입력해 주세요.';
      });
    } on SocketException catch (e) {
      debugPrint('영양성분표 인식 실패(network): $e');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _retriable = true;
        _reading = NutritionLabelReading.empty;
        _error = '인터넷 연결이 불안정해요. 연결을 확인하고 다시 시도해 주세요.';
      });
    } catch (e) {
      debugPrint('영양성분표 인식 실패: $e');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _retriable = false;
        _reading = NutritionLabelReading.empty;
        _error = '사진에서 값을 읽지 못했어요. 표가 화면에 꽉 차도록 다시 촬영하거나 직접 입력해 주세요.';
      });
    }
  }

  /// 서버 로직 오류가 아니라 단말의 연결 상태 때문으로 보이는 코드.
  static bool _isNetworkErrorCode(String code) =>
      code == 'unavailable' || code == 'deadline-exceeded';

  /// Gemini(Cloud Function)로 인식한다. 실패 시 예외를 그대로 던져
  /// [_recognizeAndApply]가 사진·입력 폼을 남긴 채 직접 입력을 안내하게 한다.
  ///
  /// Gemini가 탄단지는 읽었는데 kcal만 못 읽는 경우가 있어, 그럴 때는
  /// 탄단지로부터 역산한 kcal을 최후 수단으로 채운다.
  Future<NutritionLabelReading> _recognizeLabel(File file) async {
    final NutritionLabelReading gemini;
    try {
      gemini = await _recognizeWithGemini(file);
    } on FirebaseFunctionsException catch (e) {
      // 무료 한도 초과는 일반 오류와 구분해 그대로 위로 전달한다 —
      // 안 그러면 사용자가 한도를 넘긴 줄 모르게 된다.
      if (e.code == 'resource-exhausted') {
        throw _NutritionScanQuotaExceeded(
          e.message?.trim().isNotEmpty == true
              ? e.message!
              : '오늘 무료 인식 횟수를 모두 사용했어요. 내일 다시 시도해 주세요.',
        );
      }
      rethrow;
    }

    if (gemini.kcal == null) {
      final estimated = gemini.estimatedKcal;
      if (estimated != null) return gemini.copyWith(kcal: estimated);
    }
    return gemini;
  }

  Future<NutritionLabelReading> _recognizeWithGemini(File file) async {
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw StateError('빈 이미지입니다.');
    }
    final mimeType = _mimeTypeForPath(file.path);
    final callable = _functions.httpsCallable(
      'parseNutritionLabel',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 55)),
    );
    final res = await callable.call({
      'imageBase64': base64Encode(bytes),
      'mimeType': mimeType,
    });

    final data = res.data;
    if (data is! Map) {
      throw StateError('인식 응답 형식이 올바르지 않습니다.');
    }
    final readingRaw = data['reading'];
    if (readingRaw is! Map) {
      throw StateError('인식 결과에 reading이 없습니다.');
    }
    return NutritionLabelReading.fromAiMap(readingRaw);
  }

  String _mimeTypeForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  /// 인식된 값만 채우고, 인식되지 않은 항목은 기존 입력을 유지한다.
  void _applyReading(NutritionLabelReading reading) {
    final name = reading.productName?.trim();
    if (name != null && name.isNotEmpty && _nameCtrl.text.trim().isEmpty) {
      _nameCtrl.text = name;
    }
    final basis = reading.basis;
    if (basis != null) {
      _amountCtrl.text = formatLabelNumber(basis.amount);
      _unit = basis.unit;
    } else if (_amountCtrl.text.trim().isEmpty) {
      _amountCtrl.text = '100';
    }
    _fill(_carbCtrl, reading.carb);
    _fill(_proteinCtrl, reading.protein);
    _fill(_fatCtrl, reading.fat);
    _fill(_kcalCtrl, reading.kcal);
  }

  void _fill(TextEditingController ctrl, double? value) {
    if (value == null) return;
    ctrl.text = formatLabelNumber(value);
  }

  // ── 저장 ───────────────────────────────────────────────────

  double? _parseNumber(String raw, {required bool allowZero}) {
    final text = raw.trim().replaceAll(',', '.');
    if (text.isEmpty) return allowZero ? 0 : null;
    final value = double.tryParse(text);
    if (value == null || value.isNaN || value.isInfinite) return null;
    if (value < 0) return null;
    if (!allowZero && value == 0) return null;
    return value;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      _showSnack('이름을 입력해 주세요.');
      return;
    }

    final amount = _parseNumber(_amountCtrl.text, allowZero: false);
    if (amount == null) {
      _showSnack('기준량을 0보다 큰 숫자로 입력해 주세요.');
      return;
    }

    final carb = _parseNumber(_carbCtrl.text, allowZero: true);
    final protein = _parseNumber(_proteinCtrl.text, allowZero: true);
    final fat = _parseNumber(_fatCtrl.text, allowZero: true);
    if (carb == null || protein == null || fat == null) {
      _showSnack('탄/단/지는 0 이상의 숫자로 입력해 주세요.');
      return;
    }
    if ((carb + protein + fat) <= 0) {
      _showSnack('탄/단/지 중 하나 이상을 입력해 주세요.');
      return;
    }

    final kcalInput = _parseNumber(_kcalCtrl.text, allowZero: true);
    if (kcalInput == null) {
      _showSnack('열량은 0 이상의 숫자로 입력해 주세요.');
      return;
    }
    final kcal = kcalInput > 0 ? kcalInput : carb * 4 + protein * 4 + fat * 9;

    // 기준량 대비 1단위 값을 함께 저장해 두면, 상세 추가 화면에서 그램 수를
    // 바꿔도 비례 계산이 된다. 실제 먹은 양(그램 수)은 여기서 받지 않고
    // FoodDetailScreen에서 설정한다.
    final item = FoodItem.fromJson({
      'name': name,
      'rawServingSize': FoodItem.formatServingLabel(amount, _unit),
      'servingAmount': amount,
      'servingUnit': _unit,
      'kcal': kcal,
      'carb': carb,
      'protein': protein,
      'fat': fat,
      'fiber': 0.0,
      'kcalPerUnit': kcal / amount,
      'carbPerUnit': carb / amount,
      'proteinPerUnit': protein / amount,
      'fatPerUnit': fat / amount,
      'fiberPerUnit': 0.0,
    });

    FocusScope.of(context).unfocus();
    final record = await Navigator.push<FoodRecord>(
      context,
      MaterialPageRoute(builder: (_) => FoodDetailScreen(food: item)),
    );
    if (!mounted) return;
    // 상세 화면에서 취소하면 이 화면(값 수정)으로 그대로 남는다.
    if (record != null) Navigator.pop(context, record);
  }

  // ── UI ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 키보드가 필드를 가리지 않도록 하고, 스크롤은 폼의 ScrollView가 담당한다.
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios,
            color: Colors.black87,
            size: 20,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '영양정보 인식',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      body: _imagePath == null
          ? _buildLoading()
          : KeyboardActions(
              // 다른 화면과 같이 disableScroll: true.
              // false면 BottomAreaAvoider가 ScrollView를 한 겹 더 씌워
              // 카메라 복귀 후 필드 탭/입력이 먹통이 되는 경우가 있다.
              disableScroll: true,
              config: buildKeyboardActionsConfig(_focusNodes),
              child: _buildForm(),
            ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(strokeWidth: 2.5),
          SizedBox(height: 16),
          Text(
            '영양성분표를 AI로 인식하는 중…',
            style: TextStyle(fontSize: 14, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return ResponsiveContent(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_imagePath != null) _buildPreview(_imagePath!),
            if (_imagePath != null) const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (_busy || _quotaExceeded)
                        ? null
                        : () => _scan(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_outlined, size: 18),
                    label: const Text('다시 촬영'),
                    style: _outlinedStyle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (_busy || _quotaExceeded)
                        ? null
                        : () => _scan(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: const Text('앨범에서 선택'),
                    style: _outlinedStyle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _buildQuotaHint(),
            const SizedBox(height: 14),

            _buildNotice(),
            if (!_busy && !_quotaExceeded && (_error != null || _retriable)) ...[
              const SizedBox(height: 4),
              Wrap(
                children: [
                  if (_retriable && _imagePath != null)
                    TextButton.icon(
                      onPressed: _retryRecognition,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('다시 시도'),
                    ),
                  if (_error != null)
                    const SupportReportButton(contextLabel: '영양성분표 스캔'),
                ],
              ),
            ],
            const SizedBox(height: 14),

            TextField(
              controller: _nameCtrl,
              focusNode: _nameFocus,
              textInputAction: TextInputAction.next,
              decoration: _fieldDecoration(
                label: '제품명',
                hint: '',
              ),
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _amountCtrl,
              focusNode: _amountFocus,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: _numberFormatters,
              textInputAction: TextInputAction.next,
              decoration: _fieldDecoration(
                label: '기준량',
                hint: '',
              ),
            ),
            if (_reading.nutrientBasis != null ||
                _reading.totalContent != null) ...[
              const SizedBox(height: 8),
              _buildScaleHint(),
            ],
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _carbCtrl,
                    focusNode: _carbFocus,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: _numberFormatters,
                    textInputAction: TextInputAction.next,
                    decoration: _fieldDecoration(label: '탄수화물'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _proteinCtrl,
                    focusNode: _proteinFocus,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: _numberFormatters,
                    textInputAction: TextInputAction.next,
                    decoration: _fieldDecoration(label: '단백질'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _fatCtrl,
                    focusNode: _fatFocus,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: _numberFormatters,
                    textInputAction: TextInputAction.next,
                    decoration: _fieldDecoration(label: '지방'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _kcalCtrl,
                    focusNode: _kcalFocus,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: _numberFormatters,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    decoration: _fieldDecoration(
                      label: '열량',
                      hint: '비우면 자동 계산',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _busy ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 18),
                ),
                child: const Text(
                  '기록에 추가하기',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(String path) {
    return GestureDetector(
      onTap: () => _openImagePreview(path),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          alignment: Alignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: Image.file(
                File(path),
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
            if (_busy)
              Container(
                color: Colors.black26,
                child: const Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openImagePreview(String path) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _FullScreenImagePreview(path: path),
      ),
    );
  }

  /// 오늘 남은 무료 AI 인식 횟수(구독 중이면 무제한)를 실시간으로 보여준다.
  Widget _buildQuotaHint() {
    final stream = _quotaStream;
    if (stream == null) return const SizedBox.shrink();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final status = NutritionScanQuotaStatus.fromDoc(snapshot.data!.data());
        final text = status.isSubscribed
            ? 'AI 인식 무제한 이용 중'
            : '오늘 남은 무료 AI 인식: ${status.remaining}/$kFreeDailyScanLimit회';
        return Text(
          text,
          style: const TextStyle(
            fontSize: 12,
            color: Color(0xFF8A8F98),
            fontWeight: FontWeight.w600,
          ),
        );
      },
    );
  }

  /// 100g당 표면 총 내용량과 기준량을 分け 안내하고,
  /// 아니면 총 내용량 기준임을 짧게 보여준다.
  Widget _buildScaleHint() {
    final basis = _reading.nutrientBasis;
    final total = _reading.totalContent;
    final String text;
    if (_reading.isPerHundred) {
      final totalPart = total == null
          ? '총 내용량은 인식되지 않았어요'
          : '총 내용량 ${formatLabelNumber(total.amount)}${total.unit}';
      final basisPart = basis == null
          ? '아래 수치는 100 단위 기준이에요'
          : '아래 수치는 ${basis.label} 기준이에요';
      text = '$totalPart · $basisPart';
    } else if (_reading.isPerPiece) {
      final basisPart = basis == null ? '1개 기준' : '${basis.display} 기준';
      final totalPart = total == null
          ? null
          : '총 내용량 ${formatLabelNumber(total.amount)}${total.unit}';
      text = totalPart == null
          ? '아래 수치는 $basisPart'
          : '$totalPart · 아래 수치는 $basisPart';
    } else if (total != null) {
      text = '총 내용량 ${formatLabelNumber(total.amount)}${total.unit} 기준';
    } else if (basis != null) {
      text = '${basis.display} 기준';
    } else {
      text = '표에 적힌 기준량을 확인해 주세요';
    }

    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        height: 1.35,
        color: Color(0xFF3F5F8B),
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildNotice() {
    // 인식 중엔 아직 값이 안 채워진 게 당연하므로, 그 사이 뜨는 이전/기본
    // 알림(예: "인식하지 못했어요")보다 로딩 안내를 우선 보여준다.
    final (message, color) = _busy
        ? ('영양성분표를 인식하고 있어요. 잠시만 기다려 주세요.', const Color(0xFF3F5F8B))
        : switch ((_error, _reading.recognizedMacroCount)) {
            (final String e, _) => (e, const Color(0xFFB3261E)),
            (_, 3) => ('인식된 값이 표와 같은지 확인해 주세요.', const Color(0xFF3F5F8B)),
            (_, 0) => (
                '값을 인식하지 못했어요. 표가 화면에 꽉 차도록 다시 촬영하거나 직접 입력해 주세요.',
                const Color(0xFFB3261E),
              ),
            _ => (
                '일부만 인식했어요. 비어 있는 값을 채우고 나머지도 확인해 주세요.',
                const Color(0xFF9A6700),
              ),
          };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 스타일 · 작은 위젯 ────────────────────────────────────────

/// 촬영한 영양성분표 사진을 확대해서 볼 수 있는 전체 화면 뷰어.
class _FullScreenImagePreview extends StatelessWidget {
  const _FullScreenImagePreview({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.pop(context),
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: Center(child: Image.file(File(path))),
                ),
              ),
            ),
            Positioned(
              top: 4,
              left: 4,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final List<TextInputFormatter> _numberFormatters = [
  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
];

final ButtonStyle _outlinedStyle = OutlinedButton.styleFrom(
  foregroundColor: const Color(0xFF3F5F8B),
  side: const BorderSide(color: Color(0xFFDDE3EB)),
  padding: const EdgeInsets.symmetric(vertical: 12),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
);

InputDecoration _fieldDecoration({required String label, String? hint}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  );
}
