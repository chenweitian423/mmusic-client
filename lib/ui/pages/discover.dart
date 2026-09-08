import 'dart:math';

import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/api.dart';
import '../../core/models.dart';
import '../widgets/cover.dart';
import 'search.dart';
import 'song_list_page.dart';

class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  List<Sheet>? _sheets;
  List<Board>? _boards;
  String _sheetError = '';
  String _keyword = '';

  static const _keywords = ['热门', '流行', '华语', '经典', '治愈', '欧美', '轻音乐'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _sheets = null;
      _boards = null;
      _sheetError = '';
    });
    _keyword = _keywords[Random().nextInt(_keywords.length)];
    // 推荐歌单:找一个支持歌单搜索的插件
    () async {
      try {
        final plugins = await api.plugins();
        final p = plugins.firstWhere(
          (e) => e.searchTypes.contains('sheet'),
          orElse: () => plugins.isNotEmpty
              ? plugins.first
              : PluginInfo(platform: '', hash: '', searchTypes: const []),
        );
        if (p.hash.isEmpty) throw ApiException('服务器没有可用插件');
        final sheets = await api.searchSheets(_keyword, pluginHash: p.hash);
        if (mounted) setState(() => _sheets = sheets);
      } catch (e) {
        if (mounted) {
          setState(() {
            _sheets = [];
            _sheetError = e.toString();
          });
        }
      }
    }();
    // 排行榜预览
    () async {
      try {
        final boards = await api.boards('wy');
        if (mounted) setState(() => _boards = boards.take(6).toList());
      } catch (_) {
        if (mounted) setState(() => _boards = []);
      }
    }();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SafeArea(
        child: RefreshIndicator(
          color: kRed,
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              // 搜索栏
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const SearchPage()));
                  },
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.search_rounded,
                            color: Colors.grey.shade400, size: 20),
                        const SizedBox(width: 8),
                        Text('搜索歌曲、歌手',
                            style: TextStyle(
                                color: Colors.grey.shade400, fontSize: 14)),
                      ],
                    ),
                  ),
                ),
              ),
              // 推荐歌单
              _SectionTitle(title: '推荐歌单 · $_keyword', onRefresh: _load),
              SizedBox(
                height: 170,
                child: _sheets == null
                    ? const Center(
                        child: CircularProgressIndicator(color: kRed))
                    : _sheets!.isEmpty
                        ? Center(
                            child: Text(
                                _sheetError.isEmpty ? '暂无歌单' : '加载失败',
                                style:
                                    TextStyle(color: Colors.grey.shade500)))
                        : ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: _sheets!.length,
                            itemBuilder: (context, i) =>
                                _SheetCard(sheet: _sheets![i]),
                          ),
              ),
              // 排行榜
              const _SectionTitle(title: '热门榜单'),
              if (_boards == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator(color: kRed)),
                )
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      for (final b in _boards!)
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            leading: Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [Color(0xFFFF6B6B), kRed],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.trending_up_rounded,
                                  color: Colors.white),
                            ),
                            title: Text(b.name,
                                style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500)),
                            subtitle: const Text('网易云',
                                style: TextStyle(fontSize: 12)),
                            trailing: const Icon(Icons.chevron_right_rounded,
                                color: Colors.grey),
                            onTap: () {
                              Navigator.of(context).push(MaterialPageRoute(
                                builder: (_) => SongListPage(
                                  title: b.name,
                                  showIndex: true,
                                  loader: () =>
                                      api.boardSongs('wy', b.bangid),
                                ),
                              ));
                            },
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final VoidCallback? onRefresh;
  const _SectionTitle({required this.title, this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
      child: Row(
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const Spacer(),
          if (onRefresh != null)
            GestureDetector(
              onTap: onRefresh,
              child: Icon(Icons.refresh_rounded,
                  size: 18, color: Colors.grey.shade500),
            ),
        ],
      ),
    );
  }
}

class _SheetCard extends StatelessWidget {
  final Sheet sheet;
  const _SheetCard({required this.sheet});

  String get _playCountText {
    final n = int.tryParse(sheet.playCount) ?? 0;
    if (n >= 100000000) return '${(n / 100000000).toStringAsFixed(1)}亿';
    if (n >= 10000) return '${(n / 10000).toStringAsFixed(1)}万';
    return n > 0 ? '$n' : '';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => SongListPage(
            title: sheet.title,
            coverUrl: sheet.artwork,
            subtitle: sheet.artist.isEmpty ? null : 'by ${sheet.artist}',
            loader: () => api.sheetDetail(sheet),
          ),
        ));
      },
      child: Container(
        width: 110,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Cover(sheet.artwork, size: 110, radius: 10),
                if (_playCountText.isNotEmpty)
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black38,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.play_arrow_rounded,
                              color: Colors.white, size: 12),
                          Text(_playCountText,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 10)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(sheet.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, height: 1.3)),
          ],
        ),
      ),
    );
  }
}
