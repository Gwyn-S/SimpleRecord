import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_dimensions.dart';
import '../../constants/app_text_styles.dart';
import '../../services/core/theme_service.dart';
import '../../models/data/asset_account.dart';
import '../../services/cloud/supabase_service.dart';
import '../../utils/log.dart';
import '../../utils/toast.dart';
import '../../widgets/data/show_vault_action_sheet.dart';
import 'asset_account_form_page.dart';
import 'asset_category_select_page.dart';
import 'vault_join_page.dart';

class AddAssetAccountPage extends StatefulWidget {
  const AddAssetAccountPage({super.key});

  @override
  State<AddAssetAccountPage> createState() => _AddAssetAccountPageState();
}

class _AddAssetAccountPageState extends State<AddAssetAccountPage> {
  /// 小金库入口：先弹「新建 / 加入」选择，再进入对应页面。
  Future<void> _openVaultEntry() async {
    final ctx = context;
    final action = await showVaultActionSheet(ctx);
    if (!ctx.mounted) return;
    switch (action) {
      case VaultAction.create:
        await Navigator.push(
          ctx,
          MaterialPageRoute(
            builder: (_) => AddAssetAccountFormPage(
              title: '添加小金库',
              categoryName: '小金库',
              nameLabel: '名称',
              nameEditable: true,
              emptyNameFallback: '小金库',
              presetIconPath: 'assets/icons/vault_manage.svg',
              onCloudCreate: _createVaultOnCloud,
            ),
          ),
        );
      case VaultAction.join:
        await Navigator.push(
          ctx,
          MaterialPageRoute(builder: (_) => const VaultJoinPage()),
        );
      case null:
        break;
    }
  }

  /// 新建小金库：先建云端金库房间，成功返回邀请码（本地落库由表单页接管）；
  /// 失败返回 null，本地不插入。
  Future<String?> _createVaultOnCloud(
    BuildContext context,
    AssetAccount account,
  ) async {
    final supabase = SupabaseManager.instance;
    if (!await supabase.ensureSignedIn()) {
      if (context.mounted) showToast(context, '云端创建失败：请先登录账号');
      return null;
    }
    for (var i = 0; i < 5; i++) {
      final invite = _generateInviteCode();
      try {
        final code = await supabase.createVault(
          vaultId: account.id,
          name: account.name,
          inviteCode: invite,
          remark: account.remark,
        );
        if (code == null) {
          if (context.mounted) showToast(context, '创建${account.name}失败');
          return null;
        }
        if (context.mounted) showToast(context, '创建${account.name}成功');
        return code;
      } catch (e) {
        if (e.toString().contains('invite_code_taken')) continue;
        if (e.toString().contains('vault_id_taken')) {
          if (context.mounted) showToast(context, '创建${account.name}失败');
          return null;
        }
        if (context.mounted) showToast(context, '创建${account.name}失败');
        appLog('[vault] createVault failed: $e');
        return null;
      }
    }
    if (context.mounted) showToast(context, '创建${account.name}失败');
    return null;
  }

  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    return List.generate(6, (_) => chars[rnd.nextInt(chars.length)]).join();
  }

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
          final isCash = cat.name == '现金';
          // 分类图标配色：现金白底绿图标；储蓄卡~投资黄底白图标；
          // 负债红底、债券蓝底、自定义资产紫底（均白图标）
          final bgColor = switch (cat.name) {
            '现金' => colorBackgroundCard,
            '储蓄卡' || '信用卡' || '网络账户' || '投资' => colorAssetInvestIcon,
            '负债' => const Color(0xFFF44336),
            '债券' => const Color(0xFF2196F3),
            '自定义资产' => const Color(0xFF9C27B0),
            '小金库' => const Color(0xFFF9A825),
            _ => color.withValues(alpha: 0.12),
          };
          final iconColor = isCash ? colorIncome : colorTextOnPrimary;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (cat.name == '小金库') {
                _openVaultEntry();
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => _buildEntry(index)),
                );
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: spacingL,
                vertical: spacingXS,
              ),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: bgColor,
                      shape: BoxShape.circle,
                    ),
                    child: cat.iconPath != null
                        ? SvgPicture.asset(
                            cat.iconPath!,
                            width: 24,
                            height: 24,
                            fit: BoxFit.contain,
                            colorFilter: ColorFilter.mode(
                              iconColor,
                              BlendMode.srcIn,
                            ),
                          )
                        : Icon(
                            cat.icon ?? Icons.account_balance_wallet,
                            size: 24,
                            color: iconColor,
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
