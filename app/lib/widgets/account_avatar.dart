import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

import '../constants/app_dimensions.dart';
import '../models/asset_account.dart';

/// 账户图标：SVG 优先，空路径降级为默认图标。
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

  @override
  Widget build(BuildContext context) {
    final iconColor = color ?? Theme.of(context).primaryColor;
    if (account.iconPath.isNotEmpty) {
      return SvgPicture.asset(
        account.iconPath,
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
