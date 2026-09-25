import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/globals.dart';
import '../widgets/mini_player.dart';
import '../widgets/playback_failure_bar.dart';
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
          // 播放失败时在这里常驻一条可重试的提示。
          // (原来是监听 musicHandler.errorN 弹一个 2 秒的 SnackBar,失败一旦发生在
          //  用户没看屏幕的时候就会错过,已改成常驻组件。)
          const PlaybackFailureBar(),
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
