/// 应用版本号的**唯一来源**。
///
/// 为什么要单独一个文件：版本号原本散落在 `pubspec.yaml`、设置页硬编码的
/// "v1.0.13"、以及 JS 宿主环境里。三处各自漂移过（设置页那句已经落后两个版本），
/// 而插件能把 `env.appVersion` 读出去做判断，报错版本比不报还糟。
///
/// 改版本时**同时**改 `pubspec.yaml` 与这里 —— 有一条单测会盯着它们是否一致。
library;

const String kAppVersion = '1.0.15';

/// 发给插件看的宿主标识（MusicFree 官方取值是 `android` / `ios`）。
const String kPluginPlatform = 'android';
