// 在 `flutter create` 生成的工程上打平台补丁:
//   - Android: 权限、后台播放服务(audio_service)、明文 HTTP、应用名、MainActivity
//   - iOS: UIBackgroundModes(后台音频)、ATS 允许 HTTP、应用名
// 用法: dart tool/patch_platform.dart <工程目录>
import 'dart:io';

void main(List<String> args) {
  final root = args.isNotEmpty ? args[0] : '.';

  patchManifest('$root/android/app/src/main/AndroidManifest.xml');
  patchMainActivity('$root/android/app/src/main/kotlin');
  patchInfoPlist('$root/ios/Runner/Info.plist');

  stdout.writeln('平台补丁完成');
}

void patchManifest(String path) {
  final f = File(path);
  if (!f.existsSync()) {
    stdout.writeln('跳过(不存在): $path');
    return;
  }
  var t = f.readAsStringSync();

  const perms = '''
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
''';

  if (!t.contains('android.permission.WAKE_LOCK')) {
    t = t.replaceFirst('<application', '$perms    <application');
  }

  if (!t.contains('usesCleartextTraffic')) {
    t = t.replaceFirst('<application', '<application\n        android:usesCleartextTraffic="true"');
  }

  t = t.replaceFirst(
      'android:label="mmusic_client"', 'android:label="M音乐"');

  const service = '''
        <service android:name="com.ryanheise.audioservice.AudioService"
            android:foregroundServiceType="mediaPlayback"
            android:exported="true">
            <intent-filter>
                <action android:name="android.media.browse.MediaBrowserService" />
            </intent-filter>
        </service>
        <receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MEDIA_BUTTON" />
            </intent-filter>
        </receiver>
''';

  if (!t.contains('com.ryanheise.audioservice.AudioService')) {
    t = t.replaceFirst('</application>', '$service    </application>');
  }

  f.writeAsStringSync(t);
  stdout.writeln('已补丁: $path');
}

void patchMainActivity(String kotlinRoot) {
  final dir = Directory(kotlinRoot);
  if (!dir.existsSync()) {
    stdout.writeln('跳过(不存在): $kotlinRoot');
    return;
  }
  for (final e in dir.listSync(recursive: true)) {
    if (e is File && e.path.endsWith('MainActivity.kt')) {
      var t = e.readAsStringSync();
      t = t.replaceFirst('import io.flutter.embedding.android.FlutterActivity',
          'import com.ryanheise.audioservice.AudioServiceActivity');
      t = t.replaceFirst(': FlutterActivity()', ': AudioServiceActivity()');
      e.writeAsStringSync(t);
      stdout.writeln('已补丁: ${e.path}');
      return;
    }
  }
  stdout.writeln('警告: 未找到 MainActivity.kt');
}

void patchInfoPlist(String path) {
  final f = File(path);
  if (!f.existsSync()) {
    stdout.writeln('跳过(不存在): $path');
    return;
  }
  var t = f.readAsStringSync();

  if (!t.contains('UIBackgroundModes')) {
    const extra = '''
	<key>UIBackgroundModes</key>
	<array>
		<string>audio</string>
	</array>
	<key>NSAppTransportSecurity</key>
	<dict>
		<key>NSAllowsArbitraryLoads</key>
		<true/>
	</dict>
''';
    final idx = t.lastIndexOf('</dict>');
    if (idx >= 0) {
      t = t.substring(0, idx) + extra + t.substring(idx);
    }
  }

  // 应用显示名
  t = t.replaceFirst('<string>Mmusic Client</string>', '<string>M音乐</string>');
  t = t.replaceFirst('<string>mmusic_client</string>', '<string>M音乐</string>');

  f.writeAsStringSync(t);
  stdout.writeln('已补丁: $path');
}
