import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/api.dart';
import '../../core/settings.dart';
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
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.dns_rounded, color: kRed),
                  title: const Text('服务器地址', style: TextStyle(fontSize: 15)),
                  subtitle: Text(settings.serverUrl,
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
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 2, 16, 0),
                  child: Text('获取失败时会自动降级到其他音质',
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade500)),
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
                          child:
                              const Text('退出', style: TextStyle(color: kRed))),
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
          const SizedBox(height: 24),
          Center(
            child: Text('M音乐 v1.0.13 · mmusic 客户端',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
          ),
        ],
      ),
    );
  }
}
