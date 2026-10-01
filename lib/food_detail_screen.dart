import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:keyboard_actions/keyboard_actions.dart';
import 'food_item.dart';
import 'keyboard_actions_config.dart';

class FoodDetailScreen extends StatefulWidget {
  final FoodItem food;

  /// 기록에서 다시 열 때 등, 텍스트필드·비례 계산의 초기 섭취량.
  final double? initialInputAmount;

  const FoodDetailScreen({
    super.key,
    required this.food,
    this.initialInputAmount,
  });

  @override
  State<FoodDetailScreen> createState() => _FoodDetailScreenState();
}

class _FoodDetailScreenState extends State<FoodDetailScreen> {
  late final TextEditingController _ctrl;
  final FocusNode _amountFocus = FocusNode();
  late double _inputAmount;

  /// +/- 버튼이 다루는 최소·최대 "개수"(1개 용량 배수).
  static const double _minServings = 0.5;
  static const double _maxServings = 99;

  FoodItem get _food => widget.food;

  /// 1개 용량(g 또는 ml). 없으면 0.
  double get _servingBase =>
      _food.servingAmount > 0 ? _food.servingAmount : 0;

  /// 현재 입력량을 "개수"로 환산 (1개 용량이 없으면 null).
  double? get _servingCount {
    final base = _servingBase;
    if (base <= 0) return null;
    return _inputAmount / base;
  }

  bool get _canDecrement {
    final count = _servingCount;
    if (count == null) return _inputAmount > 0;
    return count > _minServings + 0.001;
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initialInputAmount;
    _inputAmount = (initial != null && initial > 0)
        ? initial
        : _food.servingAmount;
    _ctrl = TextEditingController(text: _formatAmount(_inputAmount));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  String _formatAmount(double v) {
    if ((v - v.round()).abs() < 0.05) return v.round().toString();
    return v.toStringAsFixed(1);
  }

  String _formatNutrient(double v) {
    if (v.isNaN || v.isInfinite) return '0';
    if ((v - v.round()).abs() < 0.05) return v.round().toString();
    return v.toStringAsFixed(1);
  }

  void _onAmountChanged(String text) {
    final parsed = double.tryParse(text.replaceAll(',', '.')) ?? 0;
    setState(() => _inputAmount = parsed);
  }

  /// [dir] < 0 이면 감소, > 0 이면 증가.
  /// 1개 용량 배수로 이동한다: … 0.5개 → 1개 → 2개 → 3개 …
  /// 음식마다 단위(g/ml)가 달라도 항상 "1개 용량"만큼 더하고 빼므로 동일하게 동작.
  void _stepServing(int dir) {
    final base = _servingBase > 0 ? _servingBase : _inputAmount;
    if (base <= 0) return;

    // 근사 정수/0.5는 스냅해서 부동소수 오차 제거.
    final raw = _inputAmount / base;
    var count = raw;
    if ((raw - raw.round()).abs() < 0.02) count = raw.round().toDouble();

    double next;
    if (dir < 0) {
      if (count <= 1.0 + 0.001) {
        next = _minServings; // 1개 이하 → 0.5개까지만
      } else {
        next = (count.ceil() - 1).toDouble(); // 2개대 → 이전 정수 개수
      }
    } else {
      next = count < 1.0 - 0.001 ? 1.0 : (count.floor() + 1).toDouble();
      if (next > _maxServings) next = _maxServings;
    }

    final amount = next * base;
    setState(() {
      _inputAmount = amount;
      _ctrl.text = _formatAmount(amount);
      _ctrl.selection =
          TextSelection.collapsed(offset: _ctrl.text.length);
    });
  }

  void _addRecord() {
    if (_inputAmount <= 0) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('1 이상의 섭취량을 입력해주세요.')));
      return;
    }
    final record = _food.toRecord(_inputAmount);
    Navigator.pop(context, record);
  }

  @override
  Widget build(BuildContext context) {
    final kcal = _food.kcalFor(_inputAmount);
    final carb = _food.carbFor(_inputAmount);
    final protein = _food.proteinFor(_inputAmount);
    final fat = _food.fatFor(_inputAmount);
    final fiber = _food.fiberFor(_inputAmount);
    final netCarb = carb - fiber < 0 ? 0.0 : carb - fiber;

    return KeyboardActions(
      disableScroll: true,
      config: buildKeyboardActionsConfig([_amountFocus]),
      child: Scaffold(
        resizeToAvoidBottomInset: false,
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
          title: Text(
            _food.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          centerTitle: true,
        ),
        body: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 20,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 상품 1개 용량 안내
                    Center(
                      child: Text(
                        '1개 용량: ${_food.rawServingSize}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black45,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // ── 섭취량 입력 ──────────────────────────────
                    Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _StepButton(
                            icon: Icons.remove,
                            onTap: _canDecrement
                                ? () => _stepServing(-1)
                                : null,
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 110,
                            child: TextField(
                              controller: _ctrl,
                              focusNode: _amountFocus,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9.,]'),
                                ),
                              ],
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 40,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87,
                              ),
                              onChanged: _onAmountChanged,
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Colors.black26,
                                    width: 1.5,
                                  ),
                                ),
                                focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(
                                    color: Color(0xFF2196F3),
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _food.servingUnit,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w500,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _StepButton(
                            icon: Icons.add,
                            onTap: () => _stepServing(1),
                          ),
                        ],
                      ),
                    ),
                    if (_servingCount != null) ...[
                      const SizedBox(height: 12),
                      Center(
                        child: Text(
                          '${_formatAmount(_servingCount!)}개',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black45,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 40),

                    // ── 영양성분 카드 ──────────────────────────────
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 20,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F8F8),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '영양성분',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.black45,
                            ),
                          ),
                          const SizedBox(height: 14),

                          // 에너지
                          _NutrientRow(
                            label: '에너지',
                            value: _formatNutrient(kcal),
                            unit: 'kcal',
                            isHighlight: true,
                          ),

                          const _Divider(),

                          // 탄수화물 + 식이섬유 + 순탄수화물
                          _NutrientRow(
                            label: '탄수화물',
                            value: _formatNutrient(carb),
                            unit: 'g',
                          ),
                          Padding(
                            padding: const EdgeInsets.only(
                              left: 16,
                              top: 4,
                              bottom: 4,
                            ),
                            child: Text(
                              '식이섬유  ${_formatNutrient(fiber)}g',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black38,
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(
                              left: 16,
                              top: 4,
                              bottom: 4,
                            ),
                            child: Text(
                              '순탄수화물  ${_formatNutrient(netCarb)}g',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black38,
                              ),
                            ),
                          ),

                          const _Divider(),

                          // 단백질
                          _NutrientRow(
                            label: '단백질',
                            value: _formatNutrient(protein),
                            unit: 'g',
                          ),

                          const _Divider(),

                          // 지방
                          _NutrientRow(
                            label: '지방',
                            value: _formatNutrient(fat),
                            unit: 'g',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),

            // ── 하단 고정 버튼 ──────────────────────────────────
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _addRecord,
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
    );
  }
}

// ── 재사용 위젯 ──────────────────────────────────────────────

class _NutrientRow extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final bool isHighlight;

  const _NutrientRow({
    required this.label,
    required this.value,
    required this.unit,
    this.isHighlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isHighlight ? Colors.black87 : Colors.black87;
    final valueSize = isHighlight ? 22.0 : 18.0;
    final labelSize = isHighlight ? 15.0 : 14.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: labelSize,
              fontWeight: isHighlight ? FontWeight.w600 : FontWeight.w400,
              color: textColor,
            ),
          ),
          RichText(
            text: TextSpan(
              style: TextStyle(
                fontSize: valueSize,
                fontWeight: isHighlight ? FontWeight.w700 : FontWeight.w600,
                color: textColor,
              ),
              children: [
                TextSpan(text: value),
                TextSpan(
                  text: ' $unit',
                  style: TextStyle(
                    fontSize: labelSize,
                    fontWeight: FontWeight.w400,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _StepButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: enabled ? Colors.black26 : Colors.black12,
              width: 1.5,
            ),
          ),
          child: Icon(
            icon,
            size: 22,
            color: enabled ? Colors.black87 : Colors.black26,
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return const Divider(height: 1, thickness: 1, color: Color(0xFFEEEEEE));
  }
}
