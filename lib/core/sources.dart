/// 音源的**总入口**：UI 一律通过 `musicSource` 取数据。
///
/// 只有这一个地方知道"当前是哪种模式"，其余代码都不知道也不需要知道。
library;

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'embedded/embedded_source.dart';
import 'music_source.dart';
import 'settings.dart';

final ServerSource serverSource = ServerSource();
final EmbeddedSource embeddedSource = EmbeddedSource();

/// 模式变化的通知（启动闸门要据此重新判断"要不要连服务器/登录"）。
final ValueNotifier<SourceKind> sourceKindN =
    ValueNotifier<SourceKind>(SourceKind.server);

/// 当前生效的音源。**所有业务代码都从这里取数据。**
MusicSource get musicSource =>
    settings.sourceMode == 'embedded' ? embeddedSource : serverSource;

bool get isEmbeddedMode => settings.sourceMode == 'embedded';

/// 切换到另一种音源模式。
///
/// 切过去要顺手做两件事，否则会留下"看起来切了其实没切"的假象：
///  ① 重建 dio（服务端地址/登录态只在 [Api.configure] 里装配）；
///  ② 把上一次的跨插件告警清掉（它属于上一个模式的搜索结果）。
Future<void> setSourceMode(SourceKind kind) async {
  final mode = kind == SourceKind.embedded ? 'embedded' : 'server';
  await settings.setSourceMode(mode);
  api.configure();
  embeddedSource.lastIssues.value = const [];
  sourceKindN.value = kind;
}

/// 启动时把通知器的初值对齐到已存的设置（main 里调用一次）。
void syncSourceKind() {
  sourceKindN.value = settings.sourceMode == 'embedded'
      ? SourceKind.embedded
      : SourceKind.server;
}
