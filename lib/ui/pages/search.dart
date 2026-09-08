import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/search_history.dart';
import '../widgets/song_tile.dart';

class _SourceOption {
  final String label;
  final String? zypt; // zypt 源代码
  final String? pluginHash; // 插件 hash
  const _SourceOption(this.label, {this.zypt, this.pluginHash});
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();

  List<_SourceOption> _options = const [_SourceOption('默认')];
  int _optIndex = 0;

  List<Song> _results = [];
  bool _searching = false;
  bool _loadingMore = false;
  bool _noMore = false;
  bool _searched = false;
  int _page = 1;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadSources();
    _scroll.addListener(() {
      if (_scroll.position.pixels >
          _scroll.position.maxScrollExtent - 300) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadSources() async {
    final opts = <_SourceOption>[const _SourceOption('默认')];
    try {
      final plugins = await api.plugins();
      for (final p in plugins) {
        if (p.hash.isNotEmpty) {
          opts.add(_SourceOption(p.platform, pluginHash: p.hash));
        }
      }
    } catch (_) {}
    for (final code in zyptSources) {
      opts.add(_SourceOption(zyptName(code), zypt: code));
    }
    if (mounted) setState(() => _options = opts);
  }

  Future<void> _search() async {
    final q = _ctrl.text.trim();
    if (q.isEmpty) return;
    FocusScope.of(context).unfocus();
    await searchHistory.add(q);
    setState(() {
      _searching = true;
      _searched = true;
      _results = [];
      _page = 1;
      _noMore = false;
      _error = '';
    });
    try {
      final opt = _options[_optIndex];
      final r = await api.search(q,
          page: 1, source: opt.zypt, pluginHash: opt.pluginHash);
      if (!mounted) return;
      setState(() {
        _results = r;
        _searching = false;
        _noMore = r.isEmpty;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _noMore || _searching || _results.isEmpty) return;
    final q = _ctrl.text.trim();
    if (q.isEmpty) return;
    _loadingMore = true;
    try {
      final opt = _options[_optIndex];
      final r = await api.search(q,
          page: _page + 1, source: opt.zypt, pluginHash: opt.pluginHash);
      if (!mounted) return;
      setState(() {
        _page += 1;
        if (r.isEmpty) {
          _noMore = true;
        } else {
          // 去重追加
          final keys = _results.map((e) => e.key).toSet();
          _results = [
            ..._results,
            ...r.where((e) => !keys.contains(e.key)),
          ];
        }
      });
    } catch (_) {
      _noMore = true;
    } finally {
      _loadingMore = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        titleSpacing: 0,
        title: Container(
          height: 38,
          margin: const EdgeInsets.only(right: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF2F3F5),
            borderRadius: BorderRadius.circular(19),
          ),
          child: TextField(
            controller: _ctrl,
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              hintText: '搜索歌曲、歌手',
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 9),
            ),
            style: const TextStyle(fontSize: 14),
            onSubmitted: (_) => _search(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _search,
            child: const Text('搜索',
                style: TextStyle(color: kRed, fontSize: 15)),
          ),
        ],
      ),
      body: Column(
        children: [
          ValueListenableBuilder<List<String>>(
            valueListenable: searchHistory.terms,
            builder: (context, history, _) {
              if (history.isEmpty) return const SizedBox.shrink();
              return Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('搜索历史',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade600)),
                        const Spacer(),
                        TextButton(
                          onPressed: () => searchHistory.clear(),
                          child: const Text('清空',
                              style: TextStyle(color: kRed, fontSize: 12)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 32,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: history.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, i) {
                          final term = history[i];
                          return ActionChip(
                            label: Text(term,
                                style: const TextStyle(fontSize: 12)),
                            backgroundColor: const Color(0xFFF2F3F5),
                            labelPadding:
                                const EdgeInsets.symmetric(horizontal: 4),
                            onPressed: () {
                              _ctrl.text = term;
                              _ctrl.selection = TextSelection.fromPosition(
                                  TextPosition(offset: term.length));
                              _search();
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          // 音源选择
          SizedBox(
            height: 44,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _options.length,
              itemBuilder: (context, i) {
                final selected = i == _optIndex;
                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 7),
                  child: ChoiceChip(
                    label: Text(_options[i].label,
                        style: TextStyle(
                            fontSize: 12,
                            color: selected ? kRed : Colors.black54)),
                    selected: selected,
                    selectedColor: kRed.withOpacity(0.1),
                    backgroundColor: const Color(0xFFF2F3F5),
                    showCheckmark: false,
                    side: BorderSide(
                        color: selected ? kRed : Colors.transparent,
                        width: 0.8),
                    onSelected: (_) {
                      setState(() => _optIndex = i);
                      if (_searched) _search();
                    },
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_searching) {
      return const Center(child: CircularProgressIndicator(color: kRed));
    }
    if (_error.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _search, child: const Text('重试')),
          ],
        ),
      );
    }
    if (!_searched) {
      return Center(
        child: Text('输入关键词开始搜索',
            style: TextStyle(color: Colors.grey.shade400)),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child:
            Text('没有找到相关歌曲', style: TextStyle(color: Colors.grey.shade500)),
      );
    }
    return ListView.builder(
      controller: _scroll,
      itemCount: _results.length + 1,
      itemBuilder: (context, i) {
        if (i == _results.length) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: _noMore
                  ? Text('没有更多了',
                      style: TextStyle(
                          color: Colors.grey.shade400, fontSize: 12))
                  : const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: kRed)),
            ),
          );
        }
        return SongTile(
          song: _results[i],
          listContext: _results,
          index: i,
        );
      },
    );
  }
}
