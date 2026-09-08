import 'package:flutter/material.dart';

import 'core/api.dart';
import 'core/settings.dart';
import 'ui/pages/home_shell.dart';
import 'ui/pages/login.dart';
import 'ui/pages/server_setup.dart';

const kRed = Color(0xFFEC4141);

class MMusicApp extends StatelessWidget {
  const MMusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'M音乐',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: kRed,
          primary: kRed,
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F8FA),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          centerTitle: true,
          titleTextStyle: TextStyle(
            color: Colors.black87,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        splashFactory: InkRipple.splashFactory,
      ),
      home: const Gate(),
    );
  }
}

/// 启动闸门:服务器未配置 → 配置页;未登录 → 登录页;已登录 → 主页
class Gate extends StatefulWidget {
  const Gate({super.key});

  @override
  State<Gate> createState() => _GateState();
}

enum _GateStatus { checking, needServer, needLogin, ready, error }

class _GateState extends State<Gate> {
  _GateStatus _status = _GateStatus.checking;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() => _status = _GateStatus.checking);
    if (settings.serverUrl.isEmpty) {
      setState(() => _status = _GateStatus.needServer);
      return;
    }
    try {
      final st = await api.authStatus();
      if (st['authenticated'] == true) {
        setState(() => _status = _GateStatus.ready);
      } else {
        setState(() => _status = _GateStatus.needLogin);
      }
    } catch (e) {
      setState(() {
        _status = _GateStatus.error;
        _error = '无法连接服务器\n${settings.serverUrl}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_status) {
      case _GateStatus.checking:
        return const Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.music_note_rounded, color: kRed, size: 64),
                SizedBox(height: 16),
                CircularProgressIndicator(color: kRed),
              ],
            ),
          ),
        );
      case _GateStatus.needServer:
        return const ServerSetupPage();
      case _GateStatus.needLogin:
        return const LoginPage();
      case _GateStatus.ready:
        return const HomeShell();
      case _GateStatus.error:
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_rounded, size: 56, color: Colors.grey),
                  const SizedBox(height: 12),
                  Text(_error,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.black54)),
                  const SizedBox(height: 24),
                  FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: kRed),
                    onPressed: _check,
                    child: const Text('重试'),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => const ServerSetupPage()));
                    },
                    child: const Text('修改服务器地址'),
                  ),
                ],
              ),
            ),
          ),
        );
    }
  }
}

/// 重新进入启动闸门(登录、换服务器后调用)
void restartToGate(BuildContext context) {
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const Gate()),
    (r) => false,
  );
}
