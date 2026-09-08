import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/api.dart';
import '../../core/models.dart';
import 'song_list_page.dart';

class BoardsPage extends StatefulWidget {
  const BoardsPage({super.key});

  @override
  State<BoardsPage> createState() => _BoardsPageState();
}

class _BoardsPageState extends State<BoardsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: zyptSources.length, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('排行榜'),
        bottom: TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          labelColor: kRed,
          unselectedLabelColor: Colors.grey.shade600,
          indicatorColor: kRed,
          indicatorSize: TabBarIndicatorSize.label,
          tabAlignment: TabAlignment.start,
          tabs: [for (final s in zyptSources) Tab(text: zyptName(s))],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [for (final s in zyptSources) _BoardList(source: s)],
      ),
    );
  }
}

class _BoardList extends StatefulWidget {
  final String source;
  const _BoardList({required this.source});

  @override
  State<_BoardList> createState() => _BoardListState();
}

class _BoardListState extends State<_BoardList>
    with AutomaticKeepAliveClientMixin {
  List<Board>? _boards;
  String _error = '';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _boards = null;
      _error = '';
    });
    try {
      final boards = await api.boards(widget.source);
      if (!mounted) return;
      setState(() => _boards = boards);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _boards = [];
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final boards = _boards;
    if (boards == null) {
      return const Center(child: CircularProgressIndicator(color: kRed));
    }
    if (boards.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error.isEmpty ? '该平台暂无榜单' : '加载失败',
                style: TextStyle(color: Colors.grey.shade500)),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: boards.length,
      itemBuilder: (context, i) {
        final b = boards[i];
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
                gradient: LinearGradient(
                  colors: [
                    kRed.withOpacity(0.55 + (i % 5) * 0.09),
                    kRed,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  b.name.isNotEmpty ? b.name.substring(0, 1) : '榜',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
            title: Text(b.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w500)),
            trailing:
                const Icon(Icons.chevron_right_rounded, color: Colors.grey),
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => SongListPage(
                  title: b.name,
                  showIndex: true,
                  loader: () => api.boardSongs(widget.source, b.bangid),
                ),
              ));
            },
          ),
        );
      },
    );
  }
}
