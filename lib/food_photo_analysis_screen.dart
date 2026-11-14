import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'food_detail_screen.dart';
import 'food_item.dart';
import 'food_photo_analysis.dart';
import 'models.dart';
import 'nutrition_scan_quota.dart';
import 'responsive_content.dart';
import 'scan_source_widgets.dart';

const Color _bgColor = Color(0xFFF2F2F2);
const Color _primary = Color(0xFF3F5F8B);
const Color _borderColor = Color(0xFFE0E0E0);
const Color _chipBorder = Color(0xFFDDE3EB);
const Color _errorColor = Color(0xFFB3261E);

/// 업로드 크기를 줄이면서 음식 형태는 충분히 보이는 크기.
/// (영양성분표 스캔과 같은 값. Gemini 3 계열은 이미지당 고정 토큰이라
/// 크기를 줄여도 Gemini 비용은 같다.)
const int _kPhotoMaxWidth = 1536;
const int _kPhotoImageQuality = 90;

/// 홈에서 "사진으로 기록"을 눌렀을 때 뜨는 촬영 방법 선택 시트.
/// 취소하거나 무료 한도를 다 썼으면 null.
Future<ImageSource?> showFoodPhotoSourceSheet(
  BuildContext context,
  NutritionScanQuotaStatus quota,
) {
  return showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '사진으로 기록하기',
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
                ),
              ],
            ),
            if (!quota.isExhausted) ScanQuotaChip(quota: quota),
            const SizedBox(height: 20),
            if (quota.isExhausted)
              ScanQuotaExhaustedNotice(onSubscribeTap: () => Navigator.pop(ctx))
            else ...[
              ScanSourceOption(
                icon: Icons.photo_camera_outlined,
                label: '사진 촬영',
                description: '카메라로 바로 촬영해요',
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              const SizedBox(height: 10),
              ScanSourceOption(
                icon: Icons.photo_library_outlined,
                label: '앨범에서 선택',
                description: '저장된 사진을 불러와요',
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
              const SizedBox(height: 16),
              const Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.black45),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '음식이 잘 보이게 위에서 찍으면 더 정확해요',
                      style: TextStyle(fontSize: 12, color: Colors.black45),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// [FoodPhotoAnalysisScreen]이 기록을 마치고 돌려주는 값.
class FoodPhotoLogResult {
  const FoodPhotoLogResult({required this.mealId, required this.foods});

  /// 기록할 식사의 [MealEntry.id].
  final String mealId;
  final List<FoodRecord> foods;
}

/// 음식 사진을 AI로 분석해 음식별 양·칼로리를 보여주고, 고른 식사에
/// 한 번에 기록하는 화면. 기록하면 [FoodPhotoLogResult]를 돌려준다.
class FoodPhotoAnalysisScreen extends StatefulWidget {
  const FoodPhotoAnalysisScreen({
    super.key,
    required this.initialSource,
    required this.meals,
  });

  final ImageSource initialSource;

  /// 기록할 수 있는 식사 목록(대시보드에서 보고 있는 날짜).
  final List<MealEntry> meals;

  @override
  State<FoodPhotoAnalysisScreen> createState() =>
      _FoodPhotoAnalysisScreenState();
}

/// 결과 목록의 한 줄. 상세 화면에서 양을 바꾸면 [amountLabel]도 바뀐다.
class _Entry {
  _Entry(this.record, this.amountLabel);

  FoodRecord record;
  String amountLabel;
}

class _FoodPhotoAnalysisScreenState extends State<FoodPhotoAnalysisScreen> {
  final ImagePicker _picker = ImagePicker();

  String? _imagePath;
  bool _busy = false;
  String? _error;
  bool _retriable = false;
  bool _quotaExceeded = false;

  /// 분석이 끝나면 채워진다. 음식을 못 찾았으면 빈 목록.
  List<_Entry>? _entries;
  late String _selectedMealId;

  /// 다시 촬영한 사진까지 모두 기억했다가 화면을 나갈 때 지운다.
  final Set<String> _capturedImagePaths = {};

  @override
  void initState() {
    super.initState();
    _selectedMealId = _defaultMealId();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pickAndAnalyze(widget.initialSource, popIfCancelled: true);
    });
  }

  @override
  void dispose() {
    for (final path in _capturedImagePaths) {
      try {
        final file = File(path);
        if (file.existsSync()) file.deleteSync();
      } catch (e) {
        debugPrint('음식 사진 임시 파일 삭제 실패: $e');
      }
    }
    super.dispose();
  }

  /// 지금 시각에 맞는 고정 식사(아침/점심/저녁)를 기본으로 고른다.
  String _defaultMealId() {
    final hour = DateTime.now().hour;
    final name = hour < 10
        ? '아침'
        : hour < 15
        ? '점심'
        : '저녁';
    final match = widget.meals.where((m) => m.isFixed && m.name == name);
    if (match.isNotEmpty) return match.first.id;
    return widget.meals.first.id;
  }

  MealEntry get _selectedMeal => widget.meals.firstWhere(
    (m) => m.id == _selectedMealId,
    orElse: () => widget.meals.first,
  );

  // ── 촬영 · 분석 ─────────────────────────────────────────────

  Future<void> _pickAndAnalyze(
    ImageSource source, {
    bool popIfCancelled = false,
  }) async {
    final XFile? picked;
    try {
      picked = await _picker.pickImage(
        source: source,
        maxWidth: _kPhotoMaxWidth.toDouble(),
        imageQuality: _kPhotoImageQuality,
      );
    } catch (e) {
      debugPrint('음식 사진 선택 실패: $e');
      if (!mounted) return;
      if (popIfCancelled && _imagePath == null) {
        Navigator.pop(context);
        return;
      }
      setState(() => _error = '카메라·사진 접근 권한을 확인해 주세요.');
      return;
    }

    if (!mounted) return;
    if (picked == null) {
      if (popIfCancelled && _imagePath == null) Navigator.pop(context);
      return;
    }

    _capturedImagePaths.add(picked.path);
    setState(() {
      _imagePath = picked!.path;
      _entries = null;
    });
    await _analyze();
  }

  Future<void> _analyze() async {
    final path = _imagePath;
    if (path == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _retriable = false;
    });

    try {
      final analysis = await analyzeFoodPhoto(File(path));
      if (!mounted) return;
      setState(() {
        _busy = false;
        _entries = [
          for (final f in analysis.foods) _Entry(f.toRecord(), f.amountLabel),
        ];
      });
    } on FoodPhotoQuotaExceeded catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _quotaExceeded = true;
        _error = e.message;
      });
    } on FirebaseFunctionsException catch (e) {
      debugPrint('음식 사진 분석 실패(functions): ${e.code} / ${e.message}');
      if (!mounted) return;
      final network = e.code == 'unavailable' || e.code == 'deadline-exceeded';
      setState(() {
        _busy = false;
        _retriable = true;
        _error = network
            ? '인터넷 연결이 불안정해요. 연결을 확인하고 다시 시도해 주세요.'
            : '지금은 분석이 원활하지 않아요. 잠시 후 다시 시도해 주세요.';
      });
    } on SocketException catch (e) {
      debugPrint('음식 사진 분석 실패(network): $e');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _retriable = true;
        _error = '인터넷 연결이 불안정해요. 연결을 확인하고 다시 시도해 주세요.';
      });
    } catch (e) {
      debugPrint('음식 사진 분석 실패: $e');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _retriable = true;
        _error = '사진을 분석하지 못했어요. 다시 시도하거나 다른 사진을 골라 주세요.';
      });
    }
  }

  // ── 결과 편집 · 기록 ──────────────────────────────────────────

  Future<void> _editEntry(int index) async {
    final entry = _entries![index];
    final record = await Navigator.push<FoodRecord>(
      context,
      MaterialPageRoute(
        builder: (_) => FoodDetailScreen(
          food: FoodItem.fromFoodRecord(entry.record),
          initialInputAmount: entry.record.sourceLoggedAmount,
        ),
      ),
    );
    if (!mounted || record == null) return;
    setState(() {
      final amount = record.sourceLoggedAmount;
      entry.record = record;
      if (amount != null) entry.amountLabel = '${_fmt(amount)}g';
    });
  }

  void _removeEntry(int index) {
    setState(() => _entries!.removeAt(index));
  }

  void _submit() {
    final entries = _entries;
    if (entries == null || entries.isEmpty) return;
    Navigator.pop(
      context,
      FoodPhotoLogResult(
        mealId: _selectedMeal.id,
        foods: [for (final e in entries) e.record],
      ),
    );
  }

  static String _fmt(double v) => v.round().toString();

  // ── UI ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final entries = _busy || _error != null ? null : _entries;
    final showResult = entries != null;
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios, size: 20),
          color: Colors.black87,
          tooltip: '뒤로',
        ),
        titleSpacing: 0,
        title: Text(
          showResult ? '분석 결과' : '사진 분석',
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
      ),
      bottomNavigationBar: entries != null && entries.isNotEmpty
          ? _buildBottomBar(entries)
          : null,
      body: _imagePath == null
          ? const SizedBox.shrink()
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: ResponsiveContent(
                maxWidth: 420,
                child: _busy
                    ? _buildAnalyzing()
                    : _error != null
                    ? _buildError()
                    : entries == null
                    ? const SizedBox.shrink()
                    : entries.isEmpty
                    ? _buildNoFood()
                    : _buildResult(entries),
              ),
            ),
    );
  }

  Widget _photo({double? height, bool dimmed = false, Widget? overlay}) {
    final stack = Stack(
      fit: StackFit.expand,
      children: [
        Image.file(File(_imagePath!), fit: BoxFit.cover),
        if (dimmed) Container(color: Colors.black.withValues(alpha: 0.45)),
        ?overlay,
      ],
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: height == null
          ? AspectRatio(aspectRatio: 1, child: stack)
          : SizedBox(height: height, child: stack),
    );
  }

  Widget _buildAnalyzing() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _photo(
          dimmed: true,
          overlay: const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome, color: Colors.white, size: 36),
                SizedBox(height: 8),
                Text(
                  'AI가 음식을 분석하고 있어요',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  '보통 5초 정도 걸려요',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 6,
            color: _primary,
            backgroundColor: Colors.black.withValues(alpha: 0.08),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '사진 속 음식 종류와 양을 추정하고 있어요',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.black.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: Colors.black45,
              minimumSize: const Size(64, 44),
            ),
            child: const Text('취소'),
          ),
        ),
      ],
    );
  }

  Widget _buildRetakeButtons() {
    final disabled = _quotaExceeded;
    final style = OutlinedButton.styleFrom(
      foregroundColor: _primary,
      side: const BorderSide(color: _chipBorder),
      minimumSize: const Size(0, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: disabled
                ? null
                : () => _pickAndAnalyze(ImageSource.camera),
            icon: const Icon(Icons.photo_camera_outlined, size: 18),
            label: const Text('다시 촬영'),
            style: style,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: disabled
                ? null
                : () => _pickAndAnalyze(ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined, size: 18),
            label: const Text('앨범에서 선택'),
            style: style,
          ),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _photo(),
        const SizedBox(height: 16),
        _Notice(icon: Icons.error_outline, text: _error!, color: _errorColor),
        const SizedBox(height: 16),
        if (_retriable) ...[
          FilledButton.icon(
            onPressed: _analyze,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('다시 시도'),
            style: FilledButton.styleFrom(
              backgroundColor: _primary,
              minimumSize: const Size(0, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        _buildRetakeButtons(),
      ],
    );
  }

  Widget _buildNoFood() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _photo(),
        const SizedBox(height: 16),
        const _Notice(
          icon: Icons.no_food_outlined,
          text: '사진에서 음식을 찾지 못했어요. 음식이 잘 보이게 다시 찍어 주세요.',
          color: _primary,
        ),
        const SizedBox(height: 16),
        _buildRetakeButtons(),
      ],
    );
  }

  Widget _buildResult(List<_Entry> entries) {
    final records = [for (final e in entries) e.record];
    double sum(double Function(FoodRecord r) f) =>
        records.fold(0, (s, r) => s + f(r));
    final kcal = sum((r) => r.kcal);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _photo(height: 160),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _borderColor, width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '이 사진의 예상 칼로리',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black.withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: _fmt(kcal),
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.black,
                      ),
                    ),
                    const TextSpan(
                      text: ' kcal',
                      style: TextStyle(fontSize: 20, color: Colors.black45),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '탄 ${_fmt(sum((r) => r.netCarb))}g · '
                '단 ${_fmt(sum((r) => r.protein))}g · '
                '지 ${_fmt(sum((r) => r.fat))}g',
                style: const TextStyle(fontSize: 13, color: Colors.black45),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          '인식된 음식 ${entries.length}개',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < entries.length; i++) ...[
          Dismissible(
            key: ObjectKey(entries[i]),
            direction: DismissDirection.endToStart,
            onDismissed: (_) => _removeEntry(i),
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFFF6B6B),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.delete_outline, color: Colors.white),
            ),
            child: _FoodResultTile(
              entry: entries[i],
              onEdit: () => _editEntry(i),
            ),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 6),
        const _Notice(
          icon: Icons.info_outline,
          text: 'AI가 추정한 값이에요. 양이 다르면 연필을 눌러 고치고, 빼고 싶은 음식은 왼쪽으로 밀어 지워 주세요.',
          color: _primary,
        ),
        const SizedBox(height: 20),
        const Text(
          '어느 식사에 기록할까요?',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final meal in widget.meals)
              _MealChip(
                label: meal.name,
                selected: meal.id == _selectedMeal.id,
                onTap: () => setState(() => _selectedMealId = meal.id),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildBottomBar(List<_Entry> entries) {
    final kcal = entries.fold<double>(0, (s, e) => s + e.record.kcal);
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: _borderColor)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: FilledButton(
            onPressed: _submit,
            style: FilledButton.styleFrom(
              backgroundColor: _primary,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: Text('${_selectedMeal.name}에 기록하기 · ${_fmt(kcal)} kcal'),
          ),
        ),
      ),
    );
  }
}

/// 분석 결과의 음식 한 줄(이름·양·탄단지·kcal·수정 버튼).
class _FoodResultTile extends StatelessWidget {
  const _FoodResultTile({required this.entry, required this.onEdit});

  final _Entry entry;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final r = entry.record;
    String g(double v) => v.round().toString();
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onEdit,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 4, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _borderColor, width: 1.2),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.black,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.amountLabel,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black45,
                      ),
                    ),
                    Text(
                      '탄 ${g(r.netCarb)}g · 단 ${g(r.protein)}g · 지 ${g(r.fat)}g',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black45,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${g(r.kcal)} kcal',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              IconButton(
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined, size: 20),
                color: Colors.black38,
                tooltip: '양 수정',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 어느 식사에 기록할지 고르는 단일 선택 칩(높이 44).
class _MealChip extends StatelessWidget {
  const _MealChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? _primary : Colors.white,
        shape: StadiumBorder(
          side: selected
              ? BorderSide.none
              : const BorderSide(color: _chipBorder),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44, minWidth: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    color: selected ? Colors.white : Colors.black87,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 아이콘과 함께 보여주는 안내 박스.
class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, required this.color});

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
