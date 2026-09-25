import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/api.dart';
import '../../core/app_info.dart';
import '../../core/embedded/plugin_store.dart';
import '../../core/music_source.dart';
import '../../core/settings.dart';
import '../../core/sources.dart';
import 'plugins.dart';
import 'server_setup.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const _qualities = [
    ('128', '标准音质 128k'),
    ('192', '较高音质 192k'),
    ('320', '极高音质 320k'),
    ('999', '无损音质 FLAC'),
  ];

  @override
  Widget build(BuildContext context) {
    final embedded = isEmbeddedMode;
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 音源模式：整个 App 的数据来源，放在第一位
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Text('音源模式',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
                  child: Text(
                    '两条完全独立的数据来源，随时可切换；各自的收藏/歌单互不影响',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                ),
                RadioListTile<String>(
                  value: 'server',
                  groupValue: settings.sourceMode,
                  activeColor: kRed,
                  dense: true,
                  title: const Text('服务端（NAS）', style: TextStyle(fontSize: 14)),
                  subtitle: const Text('数据来自自建服务，可在网页端共享收藏与歌单',
                      style: TextStyle(fontSize: 11)),
                  onChanged: (v) => _switchMode(v!),
                ),
                RadioListTile<String>(
                  value: 'embedded',
                  groupValue: settings.sourceMode,
                  activeColor: kRed,
                  dense: true,
                  title: const Text('内置源（App 内跑插件）',
                      style: TextStyle(fontSize: 14)),
                  subtitle: Text(
                    '不依赖服务器；已导入 ${pluginStore.enabled.length} 个插件',
                    style: const TextStyle(fontSize: 11),
                  ),
                  onChanged: (v) => _switchMode(v!),
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.extension_rounded, color: kRed),
                  title: const Text('插件管理', style: TextStyle(fontSize: 15)),
                  subtitle: Text(
                    '${pluginStore.plugins.value.length} 个插件 · '
                    '${pluginStore.enabled.length} 个已启用',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded,
                      color: Colors.grey),
                  onTap: () async {
                    await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const PluginsPage()));
                    if (mounted) setState(() {});
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.dns_rounded, color: kRed),
                  title: const Text('服务器地址', style: TextStyle(fontSize: 15)),
                  subtitle: Text(
                      settings.serverUrl.isEmpty ? '未设置' : settings.serverUrl,
                      style: const TextStyle(fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right_rounded,
                      color: Colors.grey),
                  onTap: () {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const ServerSetupPage()));
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Text('播放音质',
                      style:
                          TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
                  child: Text('获取失败时会自动降级到其他音质',
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                ),
                for (final q in _qualities)
                  RadioListTile<String>(
                    value: q.$1,
                    groupValue: settings.quality,
                    activeColor: kRed,
                    dense: true,
                    title: Text(q.$2, style: const TextStyle(fontSize: 14)),
                    onChanged: (v) async {
                      await settings.setQuality(v!);
                      setState(() {});
                    },
                  ),
                const SizedBox(height: 6),
              ],
            ),
          ),
          // 内置源模式下没有登录态这回事，摆一个点了没用的按钮只是噪音
          if (!embedded) ...[
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                leading: const Icon(Icons.logout_rounded, color: kRed),
                title: const Text('退出登录',
                    style: TextStyle(fontSize: 15, color: kRed)),
                onTap: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('退出登录'),
                      content: const Text('确定要退出当前账号吗?'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('取消')),
                        TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('退出',
                                style: TextStyle(color: kRed))),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await api.logout();
                    if (context.mounted) restartToGate(context);
                  }
                },
              ),
            ),
          ],
          const SizedBox(height: 24),
          Center(
            child: Text('M音乐 v$kAppVersion · ${musicSource.label}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  /// 切换音源模式。
  ///
  /// 切完必须回到启动闸门重走一遍：两种模式对"能不能进主界面"的前置条件完全不同
  /// （服务端要登录，内置源要有插件），留在原地会看到一个已经失效的页面。
  Future<void> _switchMode(String mode) async {
    if (mode == settings.sourceMode) return;
    await setSourceMode(
        mode == 'embedded' ? SourceKind.embedded : SourceKind.server);
    if (!mounted) return;
    restartToGate(context);
  }
}
