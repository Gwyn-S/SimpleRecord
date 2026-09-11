import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

import '../../services/core/author_service.dart';

/// 打包进 App 的默认头像，无自定义头像/下载中/下载失败时兜底显示。
const String defaultAvatarAsset = 'assets/icons/default_avatar.svg';

/// 作者头像：优先本地磁盘缓存（避免重复网络下载），无缓存时下载；
/// 无头像 / 下载中 / 下载失败统一显示 [defaultAvatarAsset]。
class AuthorAvatar extends StatefulWidget {
  const AuthorAvatar({super.key, this.url, this.size = 14, this.cornerRadius});

  /// 头像 URL；为空表示未设置头像，直接显示默认头像。
  final String? url;
  final double size;

  /// 圆角半径；为 null 时全圆（ClipOval），设值时用小圆角矩形（ClipRRect）。
  final double? cornerRadius;

  @override
  State<AuthorAvatar> createState() => _AuthorAvatarState();
}

class _AuthorAvatarState extends State<AuthorAvatar> {
  String? _localPath;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    // 首帧前同步查缓存，命中则首帧即显示真实头像，不闪默认。
    final url = widget.url;
    if (url != null && url.isNotEmpty) {
      final cached = AuthorService.instance.cachedAvatarPathSync(url);
      if (cached != null) {
        _localPath = cached;
        _done = true;
        return;
      }
    }
    _load();
  }

  @override
  void didUpdateWidget(covariant AuthorAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _localPath = null;
      _done = false;
      final url = widget.url;
      if (url != null && url.isNotEmpty) {
        final cached = AuthorService.instance.cachedAvatarPathSync(url);
        if (cached != null) {
          _localPath = cached;
          _done = true;
          return;
        }
      }
      _load();
    }
  }

  Future<void> _load() async {
    final url = widget.url;
    if (url == null || url.isEmpty) {
      if (mounted) setState(() => _done = true);
      return;
    }
    final path = await AuthorService.instance.avatarFileForUrl(url);
    if (!mounted) return;
    setState(() {
      _localPath = path;
      _done = true;
    });
  }

  Widget _clip(Widget child) {
    final r = widget.cornerRadius;
    if (r != null) return ClipRRect(borderRadius: BorderRadius.circular(r), child: child);
    return ClipOval(child: child);
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final url = widget.url;
    if (url == null || url.isEmpty) return _fallback(size);
    return _clip(
      _localPath != null
          ? Image.file(
              File(_localPath!),
              width: size,
              height: size,
              fit: BoxFit.cover,
            )
          : _done
          ? Image.network(
              url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _fallback(size),
            )
          // 下载中，先用默认头像兜底，避免空白。
          : _fallback(size),
    );
  }

  Widget _fallback(double size) {
    return _clip(
      SvgPicture.asset(
        defaultAvatarAsset,
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
}
