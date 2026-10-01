import 'package:flutter/material.dart';

const _bg = Color(0xFFF2F2F2);
const _primary = Color(0xFF3F5F8B);
const _ink = Color(0xFF1F2D3D);

/// 한 장의 도움말 슬라이드: 강조 이미지 + 창에 표시할 제목/설명.
class _Slide {
  const _Slide({
    required this.asset,
    required this.aspectRatio,
    required this.title,
    required this.body,
  });

  final String asset;
  /// 이미지 원본 가로/세로. 출력 프레임이 이 비율에 맞춰 줄어든다.
  final double aspectRatio;
  final String title;
  final String body;
}

const List<_Slide> _slides = [
  _Slide(
    asset: 'assets/help/help_1.png',
    aspectRatio: 1087 / 1447,
    title: '오늘의 칼로리와 영양 균형',
    body: '먹은 음식을 기록하면 남은 칼로리와\n탄·단·지 비율을 여기서 한눈에 볼 수 있어요',
  ),
  _Slide(
    asset: 'assets/help/help_2.png',
    aspectRatio: 1086 / 1448,
    title: '지난 기록과 목표일 관리',
    body: '캘린더에서 월별 기록을 확인하고,\n목표일 버튼으로 목표 날짜를 바꿀 수 있어요',
  ),
  _Slide(
    asset: 'assets/help/help_3.png',
    aspectRatio: 1086 / 1448,
    title: '날짜별 목표 달성 현황',
    body: '캘린더에서 날짜 아래 색깔로\n목표 달성 여부를 확인할 수 있어요',
  ),
  _Slide(
    asset: 'assets/help/help_4.png',
    aspectRatio: 1086 / 1448,
    title: '잊지 않도록 알림 받기',
    body: '알림 버튼에서 기록 리마인더와\n나만의 알림을 설정할 수 있어요',
  ),
  _Slide(
    asset: 'assets/help/help_5.png',
    aspectRatio: 1086 / 1448,
    title: '끼니별로 기록하기',
    body: "끼니별로 식단을 기록하고,\n추가 버튼으로 더 많은 음식을 추가할 수 있어요",
  ),
  _Slide(
    asset: 'assets/help/help_6.png',
    aspectRatio: 1086 / 1448,
    title: '검색하고 빠르게 기록',
    body: '음식을 검색하거나 이미지로 쉽게 입력하고,\n자주 먹는 음식은 마이 식단에 저장할 수 있어요',
  ),
  _Slide(
    asset: 'assets/help/help_7.png',
    aspectRatio: 990 / 1320,
    title: '영양성분표를 찍어서 기록',
    body: '제품 뒷면의 영양성분표를 찍으면\n탄·단·지·열량을 자동으로 채워줘요',
  ),
];

/// 첫 실행(온보딩 직후) 및 설정 > "사용법 다시 보기"에서 띄우는 도움말 슬라이드.
///
/// 화면 전체를 덮지 않고, 떠 있는 카드(창) 형태로 표시한다. 호출부가
/// 어두운 배경(barrier) 위에 [Center] 등으로 띄워서 사용한다.
/// 이미지는 강조 표시만 담고, 설명 문구는 이 위젯이 카드 안에 텍스트로 그린다.
/// [onFinish]는 "건너뛰기" 또는 마지막 장의 "시작하기"에서 호출된다.
class HelpTutorialScreen extends StatefulWidget {
  const HelpTutorialScreen({super.key, required this.onFinish});

  final VoidCallback onFinish;

  @override
  State<HelpTutorialScreen> createState() => _HelpTutorialScreenState();
}

class _HelpTutorialScreenState extends State<HelpTutorialScreen> {
  final _controller = PageController();
  int _page = 0;

  bool get _isLast => _page == _slides.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_isLast) {
      widget.onFinish();
    } else {
      _controller.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;
    final cardWidth = screen.width < 460 ? screen.width - 48 : 420.0;
    final cardHeight = (screen.height * 0.8).clamp(480.0, 720.0);

    return Material(
      color: _bg,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      elevation: 16,
      child: SizedBox(
        width: cardWidth,
        height: cardHeight,
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: widget.onFinish,
                child: const Text(
                  '건너뛰기',
                  style: TextStyle(color: Colors.black54, fontSize: 15),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) => _SlideView(slide: _slides[i]),
              ),
            ),
            const SizedBox(height: 12),
            _Dots(count: _slides.length, index: _page),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 2,
                  ),
                  child: Text(
                    _isLast ? '시작하기' : '다음',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
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

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide});

  final _Slide slide;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxW = constraints.maxWidth;
                final maxH = constraints.maxHeight;
                var width = maxW;
                var height = width / slide.aspectRatio;
                if (height > maxH) {
                  height = maxH;
                  width = height * slide.aspectRatio;
                }
                return Center(
                  child: SizedBox(
                    width: width,
                    height: height,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.08),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.asset(
                          slide.asset,
                          fit: BoxFit.cover,
                          width: width,
                          height: height,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              Text(
                slide.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                slide.body,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: Colors.black54,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final active = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: active ? 22 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: active ? _primary : _primary.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }
}

/// [HelpTutorialScreen]을 화면 전체를 덮는 어두운 배경(barrier) 위에 띄운다.
/// 라우트를 새로 push하지 않는(예: 앱 시작 게이트) 자리에서 사용한다.
class HelpTutorialOverlay extends StatelessWidget {
  const HelpTutorialOverlay({super.key, required this.onFinish});

  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {}, // 뒤 화면 탭 차단(바깥 탭으로 닫히지 않음)
        child: ColoredBox(
          color: Colors.black54,
          child: Center(child: HelpTutorialScreen(onFinish: onFinish)),
        ),
      ),
    );
  }
}
