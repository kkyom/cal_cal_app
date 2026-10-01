import 'package:flutter/material.dart';

import 'legal_links.dart';
import 'responsive_content.dart';

const Color _bgColor = Color(0xFFF2F2F2);
const Color _primaryColor = Color(0xFF3F5F8B);

/// 설정 > 이용 약관 및 정책. 이용약관·개인정보처리방침 링크를 제공한다.
class LegalPolicyScreen extends StatelessWidget {
  const LegalPolicyScreen({super.key});

  Future<void> _open(BuildContext context, Future<bool> Function() open) async {
    final ok = await open();
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('문서를 열 수 없어요. 잠시 후 다시 시도해 주세요.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _bgColor,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text(
          '이용 약관 및 정책',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: ResponsiveContent(
        child: ListView(
          children: [
            ListTile(
              leading: const Icon(
                Icons.description_outlined,
                color: _primaryColor,
              ),
              title: const Text(
                '이용약관',
                style: TextStyle(color: Colors.black),
              ),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => _open(context, LegalLinks.openTermsOfService),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(
                Icons.privacy_tip_outlined,
                color: _primaryColor,
              ),
              title: const Text(
                '개인정보 처리방침',
                style: TextStyle(color: Colors.black),
              ),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => _open(context, LegalLinks.openPrivacyPolicy),
            ),
          ],
        ),
      ),
    );
  }
}
