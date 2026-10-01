import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'responsive_content.dart';

const Color _bgColor = Color(0xFFF2F2F2);
const Color _primaryColor = Color(0xFF3F5F8B);

const String _appName = '칼캘';

/// 설정 > 앱 정보. 버전 정보와 오픈소스 라이선스를 보여준다.
class AppInfoScreen extends StatefulWidget {
  const AppInfoScreen({super.key});

  @override
  State<AppInfoScreen> createState() => _AppInfoScreenState();
}

class _AppInfoScreenState extends State<AppInfoScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _version = info.version);
      }
    } catch (e) {
      debugPrint('앱 버전 조회 실패: $e');
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
          '앱 정보',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
        ),
      ),
      body: ResponsiveContent(
        child: ListView(
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline, color: _primaryColor),
              title: const Text('버전', style: TextStyle(color: Colors.black)),
              trailing: Text(
                _version,
                style: const TextStyle(color: Colors.black54),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(
                Icons.description_outlined,
                color: _primaryColor,
              ),
              title: const Text(
                '오픈소스 라이선스',
                style: TextStyle(color: Colors.black),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showLicensePage(
                context: context,
                applicationName: _appName,
                applicationVersion: _version,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
