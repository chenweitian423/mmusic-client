import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/embedded/embedded_plugin.dart';
import '../../core/embedded/embedded_source.dart';
import '../../core/embedded/plugin_store.dart';
import '../../core/embedded/runtime_pool.dart';
import '../../core/music_source.dart';
import '../../core/sources.dart';

/// 插件管理：列表 / 导入（URL 或多行 URL）/ 粘贴源码 / 自检 / 启停 / 删除。
///
/// 为什么"自检"是一等公民：内置源最大的风险不是"插件装不上"（装不上会当场报错），
/// 而是**装上了但某个插件悄悄不给数据** —— 比如上游只回占位地址（会员歌曲），
/// 界面上看着是"搜到歌了但点了播不了"。自检把「装载 → 搜索 → 取直链」三步的
/// 耗时与结果一次性摆出来，把这类问题从"猜"变成"看"。
class PluginsPage extends StatefulWidget {
  const PluginsPage({super.key});

  @override
  State<PluginsPage> createState() => _PluginsPageState();
}

class _PluginsPageState extends State<PluginsPage> {
  final Map<String, List<EngineCheck>> _checks = {};
  final Set<String> _busy = {};
  String _engineProbe = '';

  @override
  void initState() {
    super.initState();
    _probeEngine();
    pluginStore.plugins.addListener(_refresh);
  }

  @override
  void dispose() {
    pluginStore.plugins.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  /// 引擎自检：用一个临时运行时问清"这台设备上 QuickJS 的能力齐不齐"。
  ///
  /// 真机上最值得确认的就是这件事 —— 引擎能力与容器不一致时，插件在容器里能跑、
  /// 装到手机上跑不了，而且错误会很隐晦（堆栈只有混淆列号）。
  Future<void> _probeEngine() async {
    try {
      final text = await _engineProbeText();
      if (mounted) setState(() => _engineProbe = text);
    } catch (e) {
      if (mounted) setState(() => _engineProbe = '自检失败：$e');
    }
  }

  Future<String> _engineProbeText() async {
    final list = pluginStore.plugins.value;
    if (list.isEmpty) return '（还没有插件，导入一个后这里会显示引擎能力）';
    final code = await pluginStore.code(list.first.hash);
    return runtimePool.use<String>(
      list.first,
      () async => code,
      (rt) async => rt.probe(),
    );
  }

  // ---------- 导入 ----------

  Future<void> _importFromUrls() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('从 URL 导入'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '一行一个地址，可一次导入多个。\n'
                '若返回 418/403，说明站点在做访问控制（作者的分发站就是这样），'
                '改用「粘贴代码」。',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                maxLines: 5,
                minLines: 3,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'https://example.com/kw.js',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('导入')),
        ],
      ),
    );
    final text = ctrl.text;
    ctrl.dispose();
    if (ok != true || text.trim().isEmpty) return;

    final results = await pluginStore.importFromUrls(text);
    if (!mounted) return;
    final okCount = results.where((r) => r.plugin != null).length;
    final lines = [
      for (final r in results)
        r.plugin != null
            ? '✅ ${r.plugin!.displayName}（${r.plugin!.shortHash}）'
            : '❌ ${r.target}\n    ${r.error}',
    ];
    _showReport('导入结果：成功 $okCount / ${results.length}', lines);
  }

  Future<void> _importFromPaste() async {
    final ctrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('粘贴插件源码'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('把插件文件内容整段粘进来。',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: '备注名（可留空）',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: ctrl,
                maxLines: 6,
                minLines: 4,
                decoration: const InputDecoration(
                  hintText: '// 插件源码…',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('导入')),
        ],
      ),
    );
    final text = ctrl.text;
    final name = nameCtrl.text;
    ctrl.dispose();
    nameCtrl.dispose();
    if (ok != true || text.trim().isEmpty) return;

    try {
      final p = await pluginStore.importFromCode(
        text,
        origin: 'paste',
        originDetail: name.trim(),
      );
      _toast('已导入 ${p.displayName}');
    } catch (e) {
      _showReport('导入失败', _splitDetail(e));
    }
  }

  void _showReport(String title, List<String> lines) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final l in lines)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: SelectableText(l,
                        style: const TextStyle(fontSize: 12, height: 1.4)),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('知道了')),
        ],
      ),
    );
  }

  List<String> _splitDetail(Object e) {
    final s = e.toString();
    return s.split('\n');
  }

  // ---------- 操作 ----------

  Future<void> _selfTest(EmbeddedPlugin p) async {
    setState(() => _busy.add(p.hash));
    try {
      final checks = await embeddedSource.selfTest(p);
      if (mounted) setState(() => _checks[p.hash] = checks);
    } catch (e) {
      _toast('自检失败：$e');
    } finally {
      if (mounted) setState(() => _busy.remove(p.hash));
    }
  }

  Future<void> _reload(EmbeddedPlugin p) async {
    setState(() => _busy.add(p.hash));
    try {
      runtimePool.evict(p.hash);
      final meta = await pluginStore.reloadMeta(p.hash);
      _toast('已重新装载：${meta.platform} v${meta.version}');
    } catch (e) {
      _showReport('重新装载失败', _splitDetail(e));
    } finally {
      if (mounted) setState(() => _busy.remove(p.hash));
    }
  }

  Future<void> _delete(EmbeddedPlugin p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除插件'),
        content: Text('确定删除「${p.displayName}」吗？之后再要用需要重新导入。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除', style: TextStyle(color: kRed))),
        ],
      ),
    );
    if (ok != true) return;
    runtimePool.evict(p.hash);
    _checks.remove(p.hash);
    await pluginStore.remove(p.hash);
    _toast('已删除');
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final list = pluginStore.plugins.value;
    return Scaffold(
      appBar: AppBar(
        title: const Text('插件管理'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.add_rounded),
            onSelected: (v) {
              if (v == 'url') _importFromUrls();
              if (v == 'paste') _importFromPaste();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'url', child: Text('从 URL 导入')),
              PopupMenuItem(value: 'paste', child: Text('粘贴源码导入')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        color: kRed,
        onRefresh: () async {
          await _probeEngine();
          if (mounted) setState(() {});
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            _modeCard(),
            const SizedBox(height: 12),
            _engineCard(),
            const SizedBox(height: 12),
            if (list.isEmpty)
              _emptyCard()
            else
              for (final p in list) ...[
                _pluginCard(p),
                const SizedBox(height: 12),
              ],
            const SizedBox(height: 8),
            Text(
              '说明：插件源码只存在本机（应用私有目录），不随安装包分发、也不上传任何服务器。\n'
              '插件 id = 源码 SHA256，改一个字节就换一个 id。',
              style: TextStyle(
                  fontSize: 11, color: Colors.grey.shade500, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modeCard() {
    final embedded = isEmbeddedMode;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: embedded ? kRed.withValues(alpha: 0.06) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: embedded ? kRed.withValues(alpha: 0.3) : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(embedded ? Icons.phone_android_rounded : Icons.dns_rounded,
              color: kRed),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('当前音源：${musicSource.label}',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(
                  embedded
                      ? '插件在本机跑，不依赖 NAS。'
                      : '正在使用 NAS 服务端，插件列表来自服务器（这里管理的是本机插件）。',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          if (!embedded)
            TextButton(
              onPressed: () async {
                await setSourceMode(SourceKind.embedded);
                if (mounted) setState(() {});
              },
              child: const Text('切到内置源'),
            ),
        ],
      ),
    );
  }

  Widget _engineCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('JS 引擎自检',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          SelectableText(
            _engineProbe.isEmpty ? '（检查中…）' : _engineProbe,
            style: TextStyle(
                fontSize: 11, color: Colors.grey.shade600, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _emptyCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(Icons.extension_outlined, size: 44, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Text('还没有导入插件',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text('点右上角「+」从 URL 导入，或粘贴插件源码。',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(height: 16),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kRed),
            onPressed: _importFromUrls,
            child: const Text('从 URL 导入'),
          ),
        ],
      ),
    );
  }

  Widget _pluginCard(EmbeddedPlugin p) {
    RuntimeStat? stat;
    for (final s in runtimePool.stats()) {
      if (s.hash == p.hash) {
        stat = s;
        break;
      }
    }
    final err = stat?.lastError;
    final checks = _checks[p.hash];
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(p.displayName,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 6),
                        if (p.version.isNotEmpty)
                          Text('v${p.version}',
                              style: TextStyle(
                                  fontSize: 11, color: Colors.grey.shade500)),
                        if (stat?.alive == true) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: kRed.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('已装载',
                                style: TextStyle(fontSize: 9, color: kRed)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${p.shortHash} · ${(p.byteSize / 1024).toStringAsFixed(0)}KB · '
                      '${_originLabel(p)}'
                      '${p.requiredModules.isEmpty ? '' : ' · 依赖 ${p.requiredModules.join('/')}'}',
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
              Switch(
                value: p.enabled,
                activeColor: kRed,
                onChanged: (v) async {
                  if (!v) runtimePool.evict(p.hash);
                  await pluginStore.setEnabled(p.hash, v);
                },
              ),
            ],
          ),
          if (err != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFDECEC),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _shorten(err),
                style: const TextStyle(fontSize: 11, color: Color(0xFF8A1F1F)),
              ),
            ),
          ],
          if (checks != null) ...[
            const SizedBox(height: 8),
            for (final c in checks)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  '${c.ok ? '✅' : '❌'} ${c.name}  ${c.cost}'
                  '${c.note == null ? '' : '  ${c.note}'}',
                  style: TextStyle(
                    fontSize: 11,
                    color:
                        c.ok ? Colors.grey.shade700 : const Color(0xFF8A1F1F),
                  ),
                ),
              ),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              TextButton.icon(
                onPressed: _busy.contains(p.hash) ? null : () => _selfTest(p),
                icon: _busy.contains(p.hash)
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: kRed),
                      )
                    : const Icon(Icons.science_rounded, size: 18),
                label: const Text('自检', style: TextStyle(fontSize: 13)),
              ),
              TextButton(
                onPressed: _busy.contains(p.hash) ? null : () => _reload(p),
                child: const Text('重新装载', style: TextStyle(fontSize: 13)),
              ),
              const Spacer(),
              IconButton(
                tooltip: '删除',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.delete_outline_rounded,
                    size: 20, color: Colors.grey.shade400),
                onPressed: () => _delete(p),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _originLabel(EmbeddedPlugin p) {
    switch (p.origin) {
      case 'builtin':
        return '随包内置';
      case 'paste':
        return p.originDetail.isEmpty ? '粘贴导入' : '粘贴：${p.originDetail}';
      default:
        return 'URL 导入';
    }
  }

  static String _shorten(String s) {
    final nl = s.indexOf('\n');
    var out = nl > 0 ? s.substring(0, nl) : s;
    if (out.length > 160) out = '${out.substring(0, 160)}…';
    return out;
  }
}
