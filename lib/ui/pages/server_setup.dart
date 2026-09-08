import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/api.dart';
import '../../core/settings.dart';

class ServerSetupPage extends StatefulWidget {
  const ServerSetupPage({super.key});

  @override
  State<ServerSetupPage> createState() => _ServerSetupPageState();
}

class _ServerSetupPageState extends State<ServerSetupPage> {
  late final TextEditingController _ctrl;
  bool _busy = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
        text: settings.serverUrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    var url = _ctrl.text.trim();
    if (url.isEmpty) return;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    setState(() {
      _busy = true;
      _error = '';
    });
    final ok = await api.testServer(url);
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _busy = false;
        _error = '连接失败: 请确认地址正确，手机和服务器在同一网络';
      });
      return;
    }
    await settings.setServerUrl(url);
    api.configure();
    if (!mounted) return;
    restartToGate(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 80),
              const Icon(Icons.music_note_rounded, color: kRed, size: 56),
              const SizedBox(height: 16),
              const Text('M音乐',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('连接你的 mmusic 音乐服务',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
              const SizedBox(height: 40),
              TextField(
                controller: _ctrl,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  labelText: '服务器地址',
                  hintText: 'http://服务器IP:8033 或 https://你的域名:端口',
                  prefixIcon: const Icon(Icons.dns_rounded),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onSubmitted: (_) => _save(),
              ),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(_error,
                    style: const TextStyle(color: kRed, fontSize: 13)),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: kRed,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(23)),
                  ),
                  onPressed: _busy ? null : _save,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('连接服务器', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

