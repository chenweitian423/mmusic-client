// 缺关键方法的"插件" —— 用来验证导入时会被当场拒掉。
// 现实里这对应"用户把一个不是 MusicFree 插件的 .js（比如某个库）当插件导进来"。
module.exports = {
  platform: '不是插件的插件',
  version: '0.0.1',
  hello: function () {
    return 'hi';
  }
};
