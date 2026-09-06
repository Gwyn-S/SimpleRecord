import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../services/theme_service.dart';
import 'asset_account_form_page.dart';

/// 二级选择页选项。
class AssetCategoryOption {
  final String name;
  final String? iconPath;
  final Color? iconColor;
  final bool nameEditable;

  const AssetCategoryOption({
    required this.name,
    this.iconPath,
    this.iconColor,
    this.nameEditable = false,
  });
}

/// 通用二级选择页，覆盖储蓄卡/信用卡/网络支付/投资。
class AssetCategorySelectPage extends StatelessWidget {
  final String categoryName;
  final String nameLabel;
  final bool showCardField;
  final List<AssetCategoryOption> options;

  const AssetCategorySelectPage({
    super.key,
    required this.categoryName,
    required this.nameLabel,
    required this.showCardField,
    required this.options,
  });

  @override
  Widget build(BuildContext context) {
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    return Scaffold(
      appBar: AppBar(
        title: const Text('选择分类'),
        backgroundColor: themeColor,
        foregroundColor: colorTextOnPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '',
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: spacingS),
        itemCount: options.length,
        separatorBuilder: (_, _) => Container(height: 1, color: colorDivider),
        itemBuilder: (context, index) {
          final option = options[index];
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AddAssetAccountFormPage(
                  title: '添加$categoryName',
                  categoryName: categoryName,
                  nameLabel: nameLabel,
                  presetName: option.name,
                  presetIconPath: option.iconPath ?? '',
                  nameEditable: option.nameEditable,
                  showCardField: showCardField,
                  emptyNameFallback: option.name,
                ),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: spacingL,
                vertical: spacingXS,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: sizeIconContainer,
                    height: sizeIconContainer,
                    child: option.iconPath != null
                        ? SvgPicture.asset(
                            option.iconPath!,
                            width: iconSizeXLarge,
                            height: iconSizeXLarge,
                            fit: BoxFit.contain,
                            colorFilter: option.iconColor != null
                                ? ColorFilter.mode(
                                    option.iconColor!,
                                    BlendMode.srcIn,
                                  )
                                : null,
                          )
                        : null,
                  ),
                  const SizedBox(width: spacingL),
                  Text(option.name, style: textPickerItem),
                  const Spacer(),
                  const Icon(
                    Icons.chevron_right,
                    size: iconSizeDefault,
                    color: colorTextSecondary,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
