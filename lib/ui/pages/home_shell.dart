import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/globals.dart';
import '../widgets/mini_player.dart';
import 'boards.dart';
import 'discover.dart';
import 'mine.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    favorites.load();
    // 播放失败提示
    musicHandler.errorN.addListener(_onPlayError);
  }

  @override
  void dispose() {
    musicHandler.errorN.removeListener(_onPlayError);
    super.dispose();
  }

  void _onPlayError() {
    final msg = musicHandler.errorN.value;
    if (msg.isEmpty || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: const [
          DiscoverPage(),
          BoardsPage(),
          MinePage(),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          BottomNavigationBar(
            currentIndex: _tab,
            onTap: (i) => setState(() => _tab = i),
            selectedItemColor: kRed,
            unselectedItemColor: Colors.grey.shade500,
            backgroundColor: Colors.white,
            type: BottomNavigationBarType.fixed,
            selectedFontSize: 11,
            unselectedFontSize: 11,
            items: const [
              BottomNavigationBarItem(
                  icon: Icon(Icons.language_rounded), label: '发现'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.leaderboard_rounded), label: '榜单'),
              BottomNavigationBarItem(
                  icon: Icon(Icons.person_rounded), label: '我的'),
            ],
          ),
        ],
      ),
    );
  }
}
