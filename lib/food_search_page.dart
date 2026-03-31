import 'package:flutter/material.dart';
import 'models.dart';

// --- 음식 검색 페이지 ---
class FoodSearchPage extends StatefulWidget {
  final String mealName;
  final List<FoodRecord> initialFoods;

  const FoodSearchPage({
    super.key,
    required this.mealName,
    this.initialFoods = const [],
  });

  @override
  State<FoodSearchPage> createState() => _FoodSearchPageState();
}

class _FoodSearchPageState extends State<FoodSearchPage> {
  final TextEditingController _searchCtrl = TextEditingController();
  bool _hasQuery = false;

  late final List<FoodRecord> _recordedFoods;

  double get _totalKcal =>
      _recordedFoods.fold(0, (sum, f) => sum + f.kcal);
  double get _carbKcal =>
      _recordedFoods.fold(0, (sum, f) => sum + f.carb * 4);
  double get _proteinKcal =>
      _recordedFoods.fold(0, (sum, f) => sum + f.protein * 4);
  double get _fatKcal =>
      _recordedFoods.fold(0, (sum, f) => sum + f.fat * 9);

  double _macroPercent(double macroKcal) {
    if (_totalKcal == 0) return 0;
    return (macroKcal / _totalKcal * 100).clamp(0, 100);
  }

  void _addFood(FoodRecord food) {
    setState(() {
      _recordedFoods.add(food);
      _searchCtrl.clear();
    });
  }

  void _removeFood(int index) {
    setState(() => _recordedFoods.removeAt(index));
  }

  @override
  void initState() {
    super.initState();
    _recordedFoods = List.from(widget.initialFoods);
    _searchCtrl.addListener(() {
      setState(() => _hasQuery = _searchCtrl.text.trim().isNotEmpty);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool hasFoods = _recordedFoods.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios,
              color: Colors.black87, size: 20),
          onPressed: () => Navigator.pop(context, _recordedFoods),
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
      ),
      body: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) Navigator.pop(context, _recordedFoods);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 검색바 + 직접 메모 버튼
            Container(
              color: const Color(0xFFF2F2F2),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0xFFE0E0E0)),
                    ),
                    child: TextField(
                      controller: _searchCtrl,
                      textInputAction: TextInputAction.search,
                      style: const TextStyle(
                          fontSize: 15, color: Colors.black87),
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
                                icon: const Icon(Icons.clear,
                                    color: Colors.black38, size: 20),
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

                  ElevatedButton(
                    onPressed: () {
                      // TODO: 직접 메모 기능 추후 연결 예정
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2196F3),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                    ),
                    child: const Text(
                      '직접 메모',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),

            // 영양 요약 (기록된 음식이 있을 때)
            if (hasFoods)
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
                  : hasFoods
                      ? _RecordedFoodList(
                          foods: _recordedFoods,
                          onDelete: _removeFood,
                        )
                      : const _EmptyState(),
            ),

            // 기록 완료 버튼
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () =>
                        Navigator.pop(context, _recordedFoods),
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
                      '기록 완료',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
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

// --- 영양 요약 섹션 ---
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
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '총 ${totalKcal.toStringAsFixed(0)}kcal',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 14),
          _MacroBar(
            label: '탄수화물',
            percent: carbPercent,
            color: const Color(0xFFFF9800),
          ),
          const SizedBox(height: 10),
          _MacroBar(
            label: '단백질',
            percent: proteinPercent,
            color: const Color(0xFF2196F3),
          ),
          const SizedBox(height: 10),
          _MacroBar(
            label: '지방',
            percent: fatPercent,
            color: const Color(0xFF4CAF50),
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
            Text(label,
                style: const TextStyle(fontSize: 13, color: Colors.black54)),
            Text('${percent.toStringAsFixed(0)}%',
                style: const TextStyle(fontSize: 13, color: Colors.black54)),
          ],
        ),
        const SizedBox(height: 5),
        Stack(
          children: [
            Container(
              height: 24,
              decoration: BoxDecoration(
                color: const Color(0xFFEEEEEE),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            FractionallySizedBox(
              widthFactor: ratio,
              child: Container(
                height: 24,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  '${percent.toStringAsFixed(0)}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// --- 기록된 음식 목록 ---
class _RecordedFoodList extends StatelessWidget {
  final List<FoodRecord> foods;
  final ValueChanged<int> onDelete;

  const _RecordedFoodList({
    required this.foods,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      itemCount: foods.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, index) {
        final food = foods[index];
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
                      '${food.kcal.toStringAsFixed(0)} kcal  탄 ${food.carb.toStringAsFixed(0)}g  단 ${food.protein.toStringAsFixed(0)}g  지 ${food.fat.toStringAsFixed(0)}g',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.black38),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => onDelete(index),
                icon: const Icon(Icons.remove_circle_outline,
                    color: Colors.redAccent, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
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
            '음식명을 검색해보세요',
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
  final ValueChanged<FoodRecord> onAdd;

  const _SearchResults({required this.query, required this.onAdd});

  static const List<Map<String, dynamic>> _sampleData = [
    {'carb': 30.0, 'protein': 5.0, 'fat': 2.0},
    {'carb': 60.0, 'protein': 15.0, 'fat': 10.0},
    {'carb': 20.0, 'protein': 8.0, 'fat': 5.0},
  ];

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      itemCount: 3,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, index) {
        final data = _sampleData[index];
        final carb = data['carb'] as double;
        final protein = data['protein'] as double;
        final fat = data['fat'] as double;
        final kcal = carb * 4 + protein * 4 + fat * 9;
        final name = '$query (예시 ${index + 1})';

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F8F8),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFEEEEEE)),
          ),
          child: Row(
            children: [
              const Icon(Icons.fastfood_outlined,
                  color: Colors.black38, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      '${kcal.toStringAsFixed(0)} kcal  탄 ${carb.toStringAsFixed(0)}g  단 ${protein.toStringAsFixed(0)}g  지 ${fat.toStringAsFixed(0)}g',
                      style: const TextStyle(
                          fontSize: 11, color: Colors.black38),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => onAdd(FoodRecord(
                  name: name,
                  carb: carb,
                  protein: protein,
                  fat: fat,
                )),
                icon: const Icon(Icons.add_circle_outline,
                    color: Color(0xFF2196F3), size: 26),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        );
      },
    );
  }
}
