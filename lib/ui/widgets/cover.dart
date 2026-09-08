import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/api.dart';

/// 封面图:先直连原始 URL,失败再走服务端 /proxy-image 代理(防盗链)
class Cover extends StatelessWidget {
  final String url;
  final double size;
  final double radius;

  const Cover(this.url, {super.key, this.size = 48, this.radius = 6});

  @override
  Widget build(BuildContext context) {
    Widget placeholder = Container(
      width: size,
      height: size,
      color: const Color(0xFFE8E8EC),
      child: Icon(Icons.music_note_rounded,
          color: Colors.grey.shade400, size: size * 0.5),
    );
    Widget child;
    if (!url.startsWith('http')) {
      child = placeholder;
    } else {
      child = CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, __) => placeholder,
        errorWidget: (_, __, ___) => CachedNetworkImage(
          imageUrl: api.proxyImage(url),
          httpHeaders: api.imageHeaders,
          width: size,
          height: size,
          fit: BoxFit.cover,
          placeholder: (_, __) => placeholder,
          errorWidget: (_, __, ___) => placeholder,
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(width: size, height: size, child: child),
    );
  }
}
