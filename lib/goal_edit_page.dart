import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// --- 목표 데이터 모델 ---
class GoalData {
  final double carb;
  final double protein;
  final double fat;

  const GoalData({
    required this.carb,
    required this.protein,
    required this.fat,
  });

  int get totalKcal => (carb * 4 + protein * 4 + fat * 9).round();
}

// --- 목표 수정 페이지 ---
class GoalEditPage extends StatefulWidget {
  final GoalData initial;

  const GoalEditPage({super.key, required this.initial});

  @override
  State<GoalEditPage> createState() => _GoalEditPageState();
}

class _GoalEditPageState extends State<GoalEditPage> {
  late final TextEditingController _carbCtrl;
  late final TextEditingController _proteinCtrl;
  late final TextEditingController _fatCtrl;

  double _carb = 0;
  double _protein = 0;
  double _fat = 0;

  @override
  void initState() {
    super.initState();
    _carb = widget.initial.carb;
    _protein = widget.initial.protein;
    _fat = widget.initial.fat;
    _carbCtrl = TextEditingController(text: _carb.toStringAsFixed(0));
    _proteinCtrl = TextEditingController(text: _protein.toStringAsFixed(0));
    _fatCtrl = TextEditingController(text: _fat.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _carbCtrl.dispose();
    _proteinCtrl.dispose();
    _fatCtrl.dispose();
    super.dispose();
  }

  int get _totalKcal => (_carb * 4 + _protein * 4 + _fat * 9).round();

  void _onChanged() {
    setState(() {
      _carb = double.tryParse(_carbCtrl.text) ?? 0;
      _protein = double.tryParse(_proteinCtrl.text) ?? 0;
      _fat = double.tryParse(_fatCtrl.text) ?? 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
      appBar: AppBar(
        title: const Text(
          '목표 수정',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        backgroundColor: const Color(0xFF3F5F8B),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
              decoration: BoxDecoration(
                color: const Color(0xFF3F5F8B),
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0x33FFFFFF), Color(0x26000000)],
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 16,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const Text(
                    '총 목표 칼로리',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$_totalKcal kcal',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '탄수화물×4 + 단백질×4 + 지방×9',
                    style: TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            _MacroField(
              label: '탄수화물',
              kcalPerGram: 4,
              controller: _carbCtrl,
              onChanged: (_) => _onChanged(),
              color: const Color(0xFFFFCE54),
            ),
            const SizedBox(height: 12),
            _MacroField(
              label: '단백질',
              kcalPerGram: 4,
              controller: _proteinCtrl,
              onChanged: (_) => _onChanged(),
              color: const Color(0xFFF6D55C),
            ),
            const SizedBox(height: 12),
            _MacroField(
              label: '지방',
              kcalPerGram: 9,
              controller: _fatCtrl,
              onChanged: (_) => _onChanged(),
              color: const Color(0xFF4B89DC),
            ),

            const SizedBox(height: 32),

            ElevatedButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  GoalData(carb: _carb, protein: _protein, fat: _fat),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3F5F8B),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 2,
              ),
              child: const Text(
                '저장',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MacroField extends StatelessWidget {
  final String label;
  final int kcalPerGram;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final Color color;

  const _MacroField({
    required this.label,
    required this.kcalPerGram,
    required this.controller,
    required this.onChanged,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 44,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(5),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
                Text(
                  '1g = ${kcalPerGram}kcal',
                  style: const TextStyle(fontSize: 11, color: Colors.black38),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 100,
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              textAlign: TextAlign.right,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
              ],
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              decoration: InputDecoration(
                suffixText: 'g',
                suffixStyle: const TextStyle(
                  color: Colors.black54,
                  fontSize: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: Color(0xFF3F5F8B),
                    width: 2,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
