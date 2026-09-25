/// 内置源里的一个插件（元数据 + 索引项）。
///
/// 为什么 id 用**源码的 SHA256** 而不是文件名：
///  * 与服务端语义一致（AGENTS §8.2：插件 hash = 插件源码文本的 SHA256），
///    同一份插件在 NAS 模式和内置源模式下会得到同一个 id，对账时不会错位；
///  * 文件名会重复（作者就叫 `qq.js`），hash 不会；
///  * 改一个字节 hash 就变 —— 这正是"插件到底换没换"最可靠的判据。
///
/// 插件**源码本身**不放在这里（也不放在 SharedPreferences 里）：它落在
/// 应用私有目录的 `<hash>.js`，这个类只承载索引与展示所需的元数据。
library;

class EmbeddedPlugin {
  /// 源码 SHA256（64 位十六进制）。
  final String hash;

  /// 插件自报的平台名，如「元力KW」。
  final String platform;
  final String version;
  final String author;

  /// 插件自报的更新地址（多数插件为空）。
  final String srcUrl;

  /// 导入渠道：`builtin`（随安装包）/ `url` / `paste`。
  final String origin;

  /// 导入时用的来源描述（URL 原文 / 「粘贴」），只用于展示。
  final String originDetail;

  /// 是否参与搜索与取直链。停用的插件仍留在列表里。
  final bool enabled;

  /// 用户在列表里的排序（小的在前）。
  final int order;

  final int importedAt;

  /// 插件声明的可搜索类型：`music` / `sheet` / `album` / `artist`。
  final List<String> supportedSearchType;

  /// 加载时实际 `require()` 到的模块名（依赖扫描/落库的结果，排障用）。
  final List<String> requiredModules;

  /// 源码字节数（列表里显示，也用于粗判"导入的是不是个正经插件"）。
  final int byteSize;

  const EmbeddedPlugin({
    required this.hash,
    required this.platform,
    this.version = '',
    this.author = '',
    this.srcUrl = '',
    this.origin = 'url',
    this.originDetail = '',
    this.enabled = true,
    this.order = 0,
    required this.importedAt,
    this.supportedSearchType = const ['music'],
    this.requiredModules = const [],
    this.byteSize = 0,
  });

  String get shortHash => hash.length > 10 ? hash.substring(0, 10) : hash;

  /// 列表标题：优先平台名，没有就退回 hash 前缀（别显示成空白行）。
  String get displayName => platform.isNotEmpty ? platform : '未命名插件 $shortHash';

  bool supports(String type) => supportedSearchType.contains(type);

  EmbeddedPlugin copyWith({
    String? platform,
    String? version,
    String? author,
    String? srcUrl,
    String? origin,
    String? originDetail,
    bool? enabled,
    int? order,
    List<String>? supportedSearchType,
    List<String>? requiredModules,
    int? byteSize,
  }) {
    return EmbeddedPlugin(
      hash: hash,
      platform: platform ?? this.platform,
      version: version ?? this.version,
      author: author ?? this.author,
      srcUrl: srcUrl ?? this.srcUrl,
      origin: origin ?? this.origin,
      originDetail: originDetail ?? this.originDetail,
      enabled: enabled ?? this.enabled,
      order: order ?? this.order,
      importedAt: importedAt,
      supportedSearchType: supportedSearchType ?? this.supportedSearchType,
      requiredModules: requiredModules ?? this.requiredModules,
      byteSize: byteSize ?? this.byteSize,
    );
  }

  Map<String, dynamic> toJson() => {
        'hash': hash,
        'platform': platform,
        'version': version,
        'author': author,
        'srcUrl': srcUrl,
        'origin': origin,
        'originDetail': originDetail,
        'enabled': enabled,
        'order': order,
        'importedAt': importedAt,
        'supportedSearchType': supportedSearchType,
        'requiredModules': requiredModules,
        'byteSize': byteSize,
      };

  factory EmbeddedPlugin.fromJson(Map<String, dynamic> j) => EmbeddedPlugin(
        hash: _s(j['hash']),
        platform: _s(j['platform']),
        version: _s(j['version']),
        author: _s(j['author']),
        srcUrl: _s(j['srcUrl']),
        origin: _s(j['origin']).isEmpty ? 'url' : _s(j['origin']),
        originDetail: _s(j['originDetail']),
        enabled: j['enabled'] != false,
        order: int.tryParse(_s(j['order'])) ?? 0,
        importedAt: int.tryParse(_s(j['importedAt'])) ?? 0,
        supportedSearchType:
            _list(j['supportedSearchType'], fallback: ['music']),
        requiredModules: _list(j['requiredModules']),
        byteSize: int.tryParse(_s(j['byteSize'])) ?? 0,
      );
}

/// 插件在引擎里**加载成功后**回报的元数据。
class PluginMeta {
  final String platform;
  final String version;
  final String author;
  final String srcUrl;
  final List<String> methods;
  final List<String> supportedSearchType;
  final List<String> requiredModules;

  const PluginMeta({
    required this.platform,
    required this.version,
    required this.author,
    required this.srcUrl,
    required this.methods,
    required this.supportedSearchType,
    required this.requiredModules,
  });

  static const empty = PluginMeta(
    platform: '',
    version: '',
    author: '',
    srcUrl: '',
    methods: [],
    supportedSearchType: ['music'],
    requiredModules: [],
  );

  factory PluginMeta.fromJson(Map<String, dynamic> j) => PluginMeta(
        platform: _s(j['platform']),
        version: _s(j['version']),
        author: _s(j['author']),
        srcUrl: _s(j['srcUrl']),
        methods: _list(j['methods']),
        supportedSearchType:
            _list(j['supportedSearchType'], fallback: ['music']),
        requiredModules: _list(j['requiredModules']),
      );

  /// 必填方法：缺了它们插件基本没法用（`getMediaSource` 是能不能播的关键）。
  List<String> get missingCritical {
    const need = ['search', 'getMediaSource'];
    return [
      for (final m in need)
        if (!methods.contains(m)) m,
    ];
  }
}

String _s(dynamic v) => v == null ? '' : v.toString();

List<String> _list(dynamic v, {List<String> fallback = const []}) {
  if (v is List) {
    final out = [for (final e in v) e.toString()];
    return out.isEmpty ? fallback : out;
  }
  if (v is String && v.isNotEmpty) return [v];
  return fallback;
}
