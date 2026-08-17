import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

import '../constants/app_dimensions.dart';
import '../models/asset_account.dart';

/// 账户图标：优先 SVG，降级为分类 Icon。
class AccountAvatar extends StatelessWidget {
  final AssetAccount account;
  final double size;
  final Color? color;

  const AccountAvatar({
    super.key,
    required this.account,
    this.size = iconSizeDefault,
    this.color,
  });

  /// 解析后的图标路径（account 自定义 > 分类默认）。
  String get _iconPath {
    if (account.iconPath.isNotEmpty) return account.iconPath;
    return account.category?.iconPath ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = color ?? Theme.of(context).primaryColor;
    if (_iconPath.isNotEmpty) {
      return SvgPicture.asset(
        _iconPath,
        width: size,
        height: size,
        fit: BoxFit.contain,
      );
    }
    return Icon(
      account.category?.icon ?? Icons.account_balance_wallet,
      size: size,
      color: iconColor,
    );
  }
}
