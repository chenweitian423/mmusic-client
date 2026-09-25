// 测试用的最小 MusicFree 插件 —— **完全自己写的**，不含任何第三方代码。
//
// 为什么需要一个自建插件而不是拿真插件测：真插件是插件作者的 jsjiami 混淆产物，
// 既不能进仓库，也不能拿来做"契约断言"（它变了测试就红，还说不清是谁的错）。
// 这个 fixture 把**实测到的真实契约**逐条钉住：
//   · search 返回 {isEnd, data:[…]}（不是文档里写的裸数组）
//   · getMediaSource 只认官方音质词表 low/standard/high/super
//   · 上游拿不到音源时给的是**占位地址**（中文文案塞在 URL 路径里）
//   · 顶层 require 两个真依赖（he / dayjs），用来验证依赖落地与懒编译
// 插件作者「科技长青」的元力插件在真机上的行为与本 fixture 一致（见
// mmusic-embedded-spike/README.md §3），所以它能当回归基线。
var he = require('he');
var dayjs = require('dayjs');

module.exports = {
  platform: '测试源',
  version: '0.0.1',
  author: 'M音乐 fixture',
  supportedSearchType: ['music', 'sheet'],

  search: async function (query, page, type) {
    if (type === 'sheet') {
      return { isEnd: false, data: [{ id: 'sheet-1', title: '测试歌单', artist: '某人' }] };
    }
    // 故意带上 HTML 实体，验证 he 真的被 require 进来了（没进来这一步就抛错）
    var title = he.decode('晴天 &amp; 测试');
    return {
      isEnd: false,
      data: [
        {
          id: 'song-1',
          title: title,
          artist: '周杰伦',
          album: '叶惠美',
          artwork: 'https://img.example.com/x.jpg',
          duration: 269
        },
        {
          id: 'song-2',
          title: '会员歌曲',
          artist: '某人',
          album: '',
          artwork: '',
          duration: 100
        }
      ]
    };
  },

  getMediaSource: async function (song, quality) {
    // 非官方词表 → 模拟真实插件的行为：拼出一个坏 URL（酷我宽容版）
    if (['low', 'standard', 'high', 'super'].indexOf(quality) < 0) {
      return { url: 'https://car-er.kuwo.cn/level=undefined&quality=' + quality };
    }
    if (song.id === 'song-2') {
      // 上游拿不到音源时回占位地址（中文塞在路径里），http 开头、长度正常
      return {
        url: 'https://sjy6.stream.qqmusic.qq.com/获取音频失败,好像没有这个音质哦~,也可能是会员过期了~'
      };
    }
    // dayjs 用来证明第二个依赖也真的可用
    return {
      url: 'https://media.example.com/' + song.id + '.mp3?level=' + quality + '&t=' + dayjs(0).valueOf()
    };
  },

  getLyric: async function (song) {
    return { rawLrc: '[00:01.00]' + song.title };
  },

  getTopLists: async function () {
    return [
      { id: 'hot', title: '热歌榜', description: '每天更新' },
      { id: 'new', title: '新歌榜' }
    ];
  },

  getTopListDetail: async function (topListItem, page) {
    var prefix = topListItem && topListItem.id ? topListItem.id : 'unknown';
    return { isEnd: true, data: [{ id: prefix + '-1', title: '榜单第一首', duration: 200 }] };
  },

  getMusicSheetInfo: async function (sheet, page) {
    var list = [{ id: 'sheet-song-1', title: '歌单第一首', duration: 180 }];
    if (page > 1) list = [];
    return { isEnd: page > 1, musicList: list };
  },

  // 用来验证"插件抛错时信封仍是 ok:false 而不是把 Dart 侧炸掉"
  boom: async function () {
    throw new Error('故意的错误');
  }
};
