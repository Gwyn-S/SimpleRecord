import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../constants/app_colors.dart';
import '../../constants/app_dimensions.dart';
import '../../constants/app_text_styles.dart';
import '../../models/data/asset_account.dart';
import '../../services/core/theme_service.dart';
import '../common/account_avatar.dart';

/// 选择「不关联账户」时由底部弹层返回的标记；区别于取消（返回 null）。
const Object noAccountSelection = Object();

Future<Object?> showAccountPicker(
  BuildContext context, {
  required List<AssetAccount> accounts,
  String? selectedId,
}) {
  return showModalBottomSheet<Object?>(
    context: context,
    backgroundColor: colorBackgroundCard,
    builder: (ctx) =>
        _AccountPickerSheet(accounts: accounts, selectedId: selectedId),
  );
}

class _AccountPickerSheet extends StatelessWidget {
  final List<AssetAccount> accounts;
  final String? selectedId;

  const _AccountPickerSheet({required this.accounts, required this.selectedId});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                spacingL,
                spacingM,
                spacingL,
                spacingS,
              ),
              child: Row(
                children: [
                  const Text('选择账户', style: textTitleBold),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.all(spacingS),
                      child: Text(
                        '取消',
                        style: TextStyle(
                          fontSize: 16,
                          color: colorTextSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: colorDivider),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  _buildItem(
                    context,
                    iconPath: 'assets/icons/assets.svg',
                    title: '无账户',
                    subtitle: null,
                    selected: selectedId == null,
                    onTap: () => Navigator.pop(context, noAccountSelection),
                  ),
                  if (accounts.isEmpty)
                    const SizedBox.shrink()
                  else
                    ...accounts.map(
                      (a) => _buildItem(
                        context,
                        account: a,
                        title: a.name,
                        subtitle: a.categoryName,
                        selected: a.id == selectedId,
                        onTap: () => Navigator.pop(context, a),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItem(
    BuildContext context, {
    IconData? icon,
    String? iconPath,
    AssetAccount? account,
    required String title,
    required String? subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: spacingL, vertical: 10),
        child: Row(
          children: [
            account != null
                ? AccountAvatar(
                    account: account,
                    size: iconSizeXLarge,
                    color: themeColor,
                  )
                : iconPath != null
                ? SvgPicture.asset(
                    iconPath,
                    width: iconSizeXLarge,
                    height: iconSizeXLarge,
                    fit: BoxFit.contain,
                    colorFilter: ColorFilter.mode(
                      themeColor,
                      BlendMode.srcIn,
                    ),
                  )
                : Icon(icon ?? Icons.account_balance_wallet,
                    size: iconSizeXLarge,
                    color: themeColor,
                  ),
            const SizedBox(width: spacingM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: textListItem),
                  if (subtitle != null) Text(subtitle, style: textItemSub),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check, size: iconSizeDefault, color: themeColor),
          ],
        ),
      ),
    );
  }
}
