import 'package:shared_preferences/shared_preferences.dart';

/// 全局设置(服务器地址、登录凭证、音质偏好、音源模式)
class Settings {
  static const String defaultServerUrl = '';
  late SharedPreferences _sp;

  Future<void> init() async {
    _sp = await SharedPreferences.getInstance();
  }

  String get serverUrl => _sp.getString('serverUrl') ?? defaultServerUrl;
  Future<void> setServerUrl(String v) async {
    var url = v.trim();
    if (url.isEmpty) return;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    await _sp.setString('serverUrl', url);
  }

  /// 音源模式:`server`(连 NAS) / `embedded`(App 内置插件,不依赖服务端)。
  ///
  /// 默认仍是 `server` —— 内置源要先导入插件才有内容,不能把老用户静默切过去
  /// 变成"打开是空的"。
  String get sourceMode => _sp.getString('sourceMode') ?? 'server';
  Future<void> setSourceMode(String v) => _sp.setString('sourceMode', v);

  /// 形如 `auth=xxxx` 的 Cookie。内置源模式下可能是空的(本来就不需要登录)。
  String get authCookie => _sp.getString('authCookie') ?? '';
  Future<void> setAuthCookie(String v) => _sp.setString('authCookie', v);

  String get username => _sp.getString('username') ?? '';
  Future<void> setUsername(String v) => _sp.setString('username', v);

  /// 128 / 192 / 320 / 999
  String get quality => _sp.getString('quality') ?? '320';
  Future<void> setQuality(String v) => _sp.setString('quality', v);

  /// 「我喜欢」在内置源模式下落本地。同一个键存服务端那份,互不干扰。
  String get localFavorites => _sp.getString('localFavorites') ?? '[]';
  Future<void> setLocalFavorites(String v) =>
      _sp.setString('localFavorites', v);

  Future<void> clearAuth() async {
    await _sp.remove('authCookie');
  }
}

final settings = Settings();
