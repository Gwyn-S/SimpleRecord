import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../constants/app_colors.dart';
import '../constants/app_dimensions.dart';
import '../constants/app_text_styles.dart';
import '../services/theme_service.dart';
import '../models/asset_account.dart';
import 'asset_account_form_page.dart';
import 'asset_category_select_page.dart';

class AddAssetAccountPage extends StatefulWidget {
  const AddAssetAccountPage({super.key});

  @override
  State<AddAssetAccountPage> createState() => _AddAssetAccountPageState();
}

class _AddAssetAccountPageState extends State<AddAssetAccountPage> {
  Widget _buildEntry(int index) {
    switch (index) {
      case 0:
        return AddAssetAccountFormPage(
          title: '添加现金',
          categoryName: '现金',
          nameLabel: '名称',
          nameEditable: true,
          emptyNameFallback: '现金',
          presetIconPath: 'assets/icons/cash.svg',
        );
      case 1:
        return AssetCategorySelectPage(
          categoryName: '储蓄卡',
          nameLabel: '所在银行',
          showCardField: true,
          options: [
            for (final e in bankIconMap.entries)
              AssetCategoryOption(name: e.key, iconPath: e.value),
            const AssetCategoryOption(
              name: '其他银行',
              iconPath: 'assets/icons/savings_card.svg',
              nameEditable: true,
            ),
          ],
        );
      case 2:
        return AssetCategorySelectPage(
          categoryName: '信用卡',
          nameLabel: '所在银行',
          showCardField: true,
          options: [
            const AssetCategoryOption(
              name: '蚂蚁花呗',
              iconPath: 'assets/icons/huabei.svg',
            ),
            const AssetCategoryOption(
              name: '京东白条',
              iconPath: 'assets/icons/jd_baitiao.svg',
            ),
            for (final e in bankIconMap.entries)
              AssetCategoryOption(name: e.key, iconPath: e.value),
            const AssetCategoryOption(
              name: '其他银行',
              iconPath: 'assets/icons/credit_card.svg',
              nameEditable: true,
            ),
          ],
        );
      case 3:
        return const AssetCategorySelectPage(
          categoryName: '网络账户',
          nameLabel: '名称',
          showCardField: false,
          options: [
            AssetCategoryOption(
              name: '微信',
              iconPath: 'assets/icons/wechat.svg',
            ),
            AssetCategoryOption(
              name: '支付宝',
              iconPath: 'assets/icons/alipay.svg',
            ),
            AssetCategoryOption(
              name: '其他类型',
              iconPath: 'assets/icons/online_banking.svg',
              nameEditable: true,
            ),
          ],
        );
      case 4:
        return const AssetCategorySelectPage(
          categoryName: '投资',
          nameLabel: '名称',
          showCardField: false,
          options: [
            AssetCategoryOption(
              name: '股票',
              iconPath: 'assets/icons/stocks.svg',
              iconColor: colorAssetInvestIcon,
            ),
            AssetCategoryOption(
              name: '基金',
              iconPath: 'assets/icons/funds.svg',
              iconColor: colorAssetInvestIcon,
            ),
            AssetCategoryOption(
              name: '其他投资',
              iconPath: 'assets/icons/investment.svg',
              iconColor: colorAssetInvestIcon,
              nameEditable: true,
            ),
          ],
        );
      case 5:
        return AddAssetAccountFormPage(
          title: '添加负债',
          categoryName: '负债',
          nameLabel: '名称',
          nameEditable: true,
          emptyNameFallback: '负债',
          presetIconPath: 'assets/icons/total_debt.svg',
        );
      case 6:
        return AddAssetAccountFormPage(
          title: '添加债券',
          categoryName: '债券',
          nameLabel: '名称',
          nameEditable: true,
          emptyNameFallback: '债券',
          presetIconPath: 'assets/icons/bonds.svg',
        );
      case 7:
        return AddAssetAccountFormPage(
          title: '添加自定义资产',
          categoryName: '自定义资产',
          nameLabel: '名称',
          nameEditable: true,
          emptyNameFallback: '自定义资产',
          presetIconPath: 'assets/icons/assets.svg',
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: AppBar(
          backgroundColor: Theme.of(
            context,
          ).extension<AppThemeColors>()!.primary,
          foregroundColor: colorTextOnPrimary,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: '',
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('添加账户'),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: spacingS),
        itemCount: assetAccountCategories.length,
        separatorBuilder: (_, _) => Container(height: 1, color: colorDivider),
        itemBuilder: (context, index) {
          final cat = assetAccountCategories[index];
          final color = cat.color;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => _buildEntry(index)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: spacingL,
                vertical: spacingXS,
              ),
              child: Row(
                children: [
                  Container(
                    width: sizeIconContainer,
                    height: sizeIconContainer,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: cat.iconPath != null
                        ? SvgPicture.asset(
                            cat.iconPath!,
                            width: iconSizeSmall,
                            height: iconSizeSmall,
                            fit: BoxFit.contain,
                            colorFilter: ColorFilter.mode(
                              color,
                              BlendMode.srcIn,
                            ),
                          )
                        : Icon(
                            cat.icon ?? Icons.account_balance_wallet,
                            size: iconSizeSmall,
                            color: color,
                          ),
                  ),
                  const SizedBox(width: spacingL),
                  Text(cat.name, style: textPickerItem),
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
