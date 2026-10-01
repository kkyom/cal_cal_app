import 'package:flutter/material.dart';
import 'center_toast.dart';
import 'firestore_service.dart';
import 'food_detail_screen.dart';
import 'food_item.dart';
import 'models.dart';
import 'responsive_content.dart';

String _fmt(double v) {
  if (v.isNaN || v.isInfinite) return '0';
  if ((v - v.round()).abs() < 0.05) return v.round().toString();
  return v.toStringAsFixed(1);
}

/// 자주 먹는 음식을 별 아이콘으로 저장해두고 다시 꺼내 쓰는 화면.
/// 항목을 누르면 [FoodDetailScreen]에서 그램수를 조정해 현재 식사 기록에 추가한다.
class MyDietScreen extends StatefulWidget {
  const MyDietScreen({super.key});

  @override
  State<MyDietScreen> createState() => _MyDietScreenState();
}

class _MyDietScreenState extends State<MyDietScreen> {
  late List<MyDietItem> _items;

  @override
  void initState() {
    super.initState();
    _items = FirestoreService.loadMyDiet();
  }

  Future<void> _openDetail(MyDietItem item) async {
    final record = await Navigator.push<FoodRecord>(
      context,
      MaterialPageRoute(builder: (_) => FoodDetailScreen(food: item.food)),
    );
    if (!mounted) return;
    if (record != null) Navigator.pop(context, record);
  }

  void _remove(MyDietItem item) {
    setState(() {
      FirestoreService.removeFromMyDietById(item.id);
      _items = FirestoreService.loadMyDiet();
    });
    showCenterToast(context, '마이 식단에서 삭제했어요');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
          '마이 식단',
          style: TextStyle(
            color: Colors.black87,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
      ),
      body: ResponsiveContent(
        child: _items.isEmpty
            ? const _MyDietEmptyState()
            : ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                itemCount: _items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (ctx, index) {
                  final item = _items[index];
                  final food = item.food;
                  final servingLabel = food.rawServingSize.isNotEmpty
                      ? food.rawServingSize
                      : '${food.servingAmount.toStringAsFixed(0)}${food.servingUnit}';
                  final nutritionLine =
                      '에너지 ${_fmt(food.kcal)}kcal · 탄 ${_fmt(food.carb)}g · 단 ${_fmt(food.protein)}g · 지 ${_fmt(food.fat)}g';

                  return Container(
                    padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8F8F8),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFEEEEEE)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => _openDetail(item),
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 2,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    food.name,
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
                        IconButton(
                          onPressed: () => _remove(item),
                          icon: const Icon(
                            Icons.star,
                            color: Color(0xFFFFC107),
                            size: 22,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          tooltip: '마이 식단에서 삭제',
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _MyDietEmptyState extends StatelessWidget {
  const _MyDietEmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_border, size: 56, color: Color(0xFFDDDDDD)),
          SizedBox(height: 14),
          Text(
            '자주 먹는 음식에 별을 눌러 저장해보세요!',
            style: TextStyle(color: Color(0xFFBBBBBB), fontSize: 15),
          ),
        ],
      ),
    );
  }
}
