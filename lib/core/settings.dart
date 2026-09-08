import 'package:shared_preferences/shared_preferences.dart';

/// 全局设置(服务器地址、登录凭证、音质偏好)
class Settings {
  static const String defaultServerUrl = '';
  late SharedPreferences _sp;

  Future<void> init() async {
    _sp = await SharedPreferences.getInstance();
  }

  String get serverUrl =>
      _sp.getString('serverUrl') ?? defaultServerUrl;
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

  /// 形如 "auth=xxxx" 的 Cookie
  String get authCookie => _sp.getString('authCookie') ?? '';
  Future<void> setAuthCookie(String v) => _sp.setString('authCookie', v);

  String get username => _sp.getString('username') ?? '';
  Future<void> setUsername(String v) => _sp.setString('username', v);

  /// 128 / 192 / 320 / 999
  String get quality => _sp.getString('quality') ?? '320';
  Future<void> setQuality(String v) => _sp.setString('quality', v);

  Future<void> clearAuth() async {
    await _sp.remove('authCookie');
  }
}

final settings = Settings();
