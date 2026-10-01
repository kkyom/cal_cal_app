import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

const Color _primaryColor = Color(0xFF3F5F8B);

/// 네트워크 연결이 없으면 앱 본문 대신 오프라인 차단 화면을 보여 준다.
class ConnectivityGate extends StatefulWidget {
  final Widget child;

  const ConnectivityGate({super.key, required this.child});

  @override
  State<ConnectivityGate> createState() => _ConnectivityGateState();
}

class _ConnectivityGateState extends State<ConnectivityGate> {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;

  bool _ready = false;
  bool _online = true;

  static bool _hasConnection(List<ConnectivityResult> results) {
    return results.any((r) => r != ConnectivityResult.none);
  }

  Future<void> _refresh() async {
    try {
      final results = await _connectivity.checkConnectivity();
      if (!mounted) return;
      setState(() {
        _online = _hasConnection(results);
        _ready = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _online = false;
        _ready = true;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _refresh();
    _subscription = _connectivity.onConnectivityChanged.listen((results) {
      if (!mounted) return;
      setState(() {
        _online = _hasConnection(results);
        _ready = true;
      });
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        backgroundColor: Color(0xFFF2F2F2),
        body: Center(
          child: CircularProgressIndicator(color: _primaryColor),
        ),
      );
    }
    if (!_online) {
      return const OfflineScreen();
    }
    return widget.child;
  }
}

/// 인터넷 연결이 필요할 때 표시하는 전체 화면.
class OfflineScreen extends StatelessWidget {
  const OfflineScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F2),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.wifi_off_rounded,
                    size: 64,
                    color: _primaryColor.withValues(alpha: 0.85),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '인터넷 연결이 필요합니다',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1F2D3D),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '네트워크에 연결되면 자동으로 이어집니다.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      color: Colors.black.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
