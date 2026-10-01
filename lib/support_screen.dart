import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'responsive_content.dart';
import 'support_service.dart';

const Color _bgColor = Color(0xFFF2F2F2);
const Color _primaryColor = Color(0xFF3F5F8B);

/// 메일 앱을 열지 못했을 때 이메일 주소를 안내하는 공통 다이얼로그.
Future<void> showSupportFallbackDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('메일 앱을 열 수 없어요'),
      content: const Text(
        '아래 주소로 문의해 주세요.\n\n${SupportService.supportEmail}',
      ),
      actions: [
        TextButton(
          onPressed: () {
            Clipboard.setData(
              const ClipboardData(text: SupportService.supportEmail),
            );
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('이메일 주소를 복사했어요.')),
            );
          },
          child: const Text('주소 복사'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('확인'),
        ),
      ],
    ),
  );
}

/// 문의/신고 메일을 연다. 실패 시 이메일 주소 안내 다이얼로그로 대체한다.
Future<void> composeSupportMail(
  BuildContext context,
  SupportTopic topic, {
  String? contextLabel,
  String? extraContent,
}) async {
  final opened = await SupportService.composeMail(
    topic,
    contextLabel: contextLabel,
    extraContent: extraContent,
  );
  if (opened || !context.mounted) return;
  await showSupportFallbackDialog(context);
}

/// 에러 상태 화면에 끼워 넣는 "오류 신고" 링크 버튼.
/// [contextLabel]로 어느 화면에서 눌렀는지 메일에 함께 담는다.
class SupportReportButton extends StatelessWidget {
  const SupportReportButton({super.key, required this.contextLabel});

  final String contextLabel;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => composeSupportMail(
        context,
        SupportTopic.bug,
        contextLabel: contextLabel,
      ),
      icon: const Icon(Icons.error_outline, size: 18),
      label: const Text('오류 신고'),
      style: TextButton.styleFrom(foregroundColor: _primaryColor),
    );
  }
}

/// 설정 > 문의 및 피드백. 문의하기 / 오류 신고 진입점.
/// 메일 앱을 열지 못하면 이메일 주소를 안내한다.
class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text(
          '문의 및 피드백',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: ResponsiveContent(
        child: ListView(
          children: [
            ListTile(
              leading: const Icon(
                Icons.mail_outline,
                color: _primaryColor,
              ),
              title: const Text(
                '문의하기',
                style: TextStyle(color: Colors.black),
              ),
              subtitle: const Text(
                '기능 제안, 사용 중 궁금한 점',
                style: TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => composeSupportMail(context, SupportTopic.inquiry),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(
                Icons.bug_report_outlined,
                color: _primaryColor,
              ),
              title: const Text(
                '오류 신고하기',
                style: TextStyle(color: Colors.black),
              ),
              subtitle: const Text(
                '검색이 안 되거나 값이 이상할 때',
                style: TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => composeSupportMail(context, SupportTopic.bug),
            ),
            const Divider(height: 1),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Text(
                '메일 앱이 열리면서 앱 버전·기기 정보·사용자 식별자가 본문에 자동으로 '
                '채워져요. 문제를 빠르게 확인하는 데만 쓰이며, 원하지 않으면 지우고 '
                '보내도 됩니다.',
                style: TextStyle(fontSize: 12, color: Colors.black45, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
