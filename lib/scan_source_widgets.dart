/// 영양성분표 스캔과 음식 사진 분석이 함께 쓰는 "사진 촬영 / 앨범에서 선택"
/// 선택지와 무료 인식 한도 관련 위젯.
library;

import 'package:flutter/material.dart';

import 'nutrition_scan_quota.dart';

/// 남은 무료 인식 횟수(또는 구독 중) 표시 칩.
class ScanQuotaChip extends StatelessWidget {
  const ScanQuotaChip({super.key, required this.quota});

  final NutritionScanQuotaStatus quota;

  @override
  Widget build(BuildContext context) {
    final text = quota.isSubscribed
        ? 'AI 인식 무제한 이용 중'
        : '오늘 남은 무료 인식 ${quota.remaining}/$kFreeDailyScanLimit회';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF2196F3).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFF2196F3),
        ),
      ),
    );
  }
}

/// 사진 소스 선택(영양성분표 스캔·음식 사진 분석) 선택지 한 줄(아이콘 + 라벨 + 설명).
class ScanSourceOption extends StatelessWidget {
  const ScanSourceOption({
    super.key,
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
class ScanQuotaExhaustedNotice extends StatelessWidget {
  const ScanQuotaExhaustedNotice({super.key, required this.onSubscribeTap});

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
