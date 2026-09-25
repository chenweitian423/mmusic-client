import 'package:flutter/material.dart';

import 'core/api.dart';
import 'core/embedded/plugin_store.dart';
import 'core/globals.dart';
import 'core/music_source.dart';
import 'core/settings.dart';
import 'core/sources.dart';
import 'ui/pages/home_shell.dart';
import 'ui/pages/login.dart';
import 'ui/pages/plugins.dart';
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

/// 启动闸门。两条完全不同的路径：
///
///  * **服务端模式**：没配地址 → 配置页；配了但没登录 → 登录页；已登录 → 主页。
///  * **内置源模式**：不需要服务器也不需要登录，只要**有启用的插件**就进主页；
///    一个插件都没有时给一页导入引导 —— 直接放进去会是一个搜什么都没结果的空壳，
///    用户会以为是坏了。
class Gate extends StatefulWidget {
  const Gate({super.key});

  @override
  State<Gate> createState() => _GateState();
}

enum _GateStatus { checking, needServer, needLogin, needPlugins, ready, error }

class _GateState extends State<Gate> {
  _GateStatus _status = _GateStatus.checking;
  String _error = '';

  @override
  void initState() {
    super.initState();
    sourceKindN.addListener(_onModeChanged);
    _check();
  }

  @override
  void dispose() {
    sourceKindN.removeListener(_onModeChanged);
    super.dispose();
  }

  void _onModeChanged() {
    if (mounted) _check();
  }

  Future<void> _check() async {
    setState(() => _status = _GateStatus.checking);

    if (isEmbeddedMode) {
      // 插件列表可能刚被导入变化过（自动导入内置插件是异步的），先加载一次
      await favorites.load(force: true);
      setState(() {
        _status = pluginStore.enabled.isEmpty
            ? _GateStatus.needPlugins
            : _GateStatus.ready;
      });
      return;
    }

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
      case _GateStatus.needPlugins:
        return _NeedPluginsPage(onRescan: _check);
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
                  const Icon(Icons.cloud_off_rounded,
                      size: 56, color: Colors.grey),
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

/// 内置源模式下"一个插件都没有"时看到的引导页。
class _NeedPluginsPage extends StatelessWidget {
  const _NeedPluginsPage({required this.onRescan});

  /// 从插件管理页回来时重新判断（导入了就进主页）。
  final Future<void> Function() onRescan;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 80),
              const Icon(Icons.extension_rounded, color: kRed, size: 56),
              const SizedBox(height: 16),
              const Text('还没有可用的插件',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                '内置源模式靠 App 自己跑插件取歌，所以要先把插件导进来。\n'
                '导入一次即可，之后不再依赖任何服务器。',
                style: TextStyle(
                    fontSize: 14, color: Colors.grey.shade600, height: 1.5),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: kRed,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(23)),
                  ),
                  onPressed: () async {
                    await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const PluginsPage()));
                    await onRescan();
                  },
                  child: const Text('导入插件', style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: () async {
                    await setSourceMode(SourceKind.server);
                  },
                  child: const Text('改用服务端模式',
                      style: TextStyle(color: Colors.grey)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 重新进入启动闸门(登录、换服务器、切音源模式后调用)
void restartToGate(BuildContext context) {
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const Gate()),
    (r) => false,
  );
}
