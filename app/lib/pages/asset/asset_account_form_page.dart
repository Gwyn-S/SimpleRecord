import 'package:flutter/material.dart';
import '../../constants/app_colors.dart';
import '../../constants/app_dimensions.dart';
import '../../constants/app_text_styles.dart';
import '../../models/data/asset_account.dart';
import '../../services/data/asset_account_service.dart';
import '../../services/core/theme_service.dart';
import '../../utils/formatters.dart';
import '../../utils/id.dart';

/// 通用账户表单页，覆盖现金/负债/债券/自定义资产（直接表单）与
/// 储蓄卡/信用卡/网络支付/投资（二级页跳转后的三级表单）。
class AddAssetAccountFormPage extends StatefulWidget {
  final String title;
  final String categoryName;
  final String nameLabel;
  final String? presetName;
  final String presetIconPath;
  final AssetAccount? existingAccount;
  final bool nameEditable;
  final bool showCardField;
  final String emptyNameFallback;

  const AddAssetAccountFormPage({
    super.key,
    required this.title,
    required this.categoryName,
    required this.nameLabel,
    required this.nameEditable,
    this.presetName,
    this.presetIconPath = '',
    this.existingAccount,
    this.showCardField = false,
    this.emptyNameFallback = '',
  });

  @override
  State<AddAssetAccountFormPage> createState() =>
      _AddAssetAccountFormPageState();
}

class _AddAssetAccountFormPageState extends State<AddAssetAccountFormPage> {
  final _nameController = TextEditingController();
  final _cardController = TextEditingController();
  final _remarkController = TextEditingController();
  final _balanceController = TextEditingController(text: '0');

  @override
  void initState() {
    super.initState();
    final e = widget.existingAccount;
    if (e == null) return;
    if (widget.nameEditable) _nameController.text = e.name;
    _cardController.text = e.cardLast4;
    _remarkController.text = e.remark;
    _balanceController.text = formatAmount(e.balanceCents);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cardController.dispose();
    _remarkController.dispose();
    _balanceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = widget.nameEditable
        ? (_nameController.text.trim().isEmpty
              ? widget.emptyNameFallback
              : _nameController.text.trim())
        : widget.presetName!;
    final balanceText = _balanceController.text.trim();
    final balanceCents =
        balanceText.isEmpty || double.tryParse(balanceText) == null
        ? 0
        : yuanToCents(balanceText);
    final account = AssetAccount(
      id: widget.existingAccount?.id ?? genId(),
      categoryName: widget.categoryName,
      name: name,
      balanceCents: balanceCents,
      // 期初只在新建时定为“当前余额”，编辑保持既有期初不变。
      openingBalanceCents:
          widget.existingAccount?.openingBalanceCents ?? balanceCents,
      remark: _remarkController.text.trim(),
      cardLast4: _cardController.text.trim(),
      iconPath: widget.presetIconPath,
    );
    if (widget.existingAccount != null) {
      await updateAssetAccount(account);
    } else {
      await insertAssetAccount(account);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = Theme.of(context).extension<AppThemeColors>()!.primary;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: themeColor,
        foregroundColor: colorTextOnPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: '',
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: spacingL,
              vertical: spacingM,
            ),
            child: _buildField(
              widget.nameLabel,
              widget.nameEditable
                  ? TextField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    )
                  : Text(widget.presetName!, style: textBody),
            ),
          ),
          const Divider(
            height: 1,
            thickness: borderWidthThin,
            color: colorDivider,
          ),
          if (widget.showCardField) ...[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: spacingL,
                vertical: spacingM,
              ),
              child: _buildField(
                '卡号(后四位)',
                TextField(
                  controller: _cardController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                    hintText: '非必填',
                    hintStyle: textHint,
                  ),
                ),
              ),
            ),
            const Divider(
              height: 1,
              thickness: borderWidthThin,
              color: colorDivider,
            ),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: spacingL,
              vertical: spacingM,
            ),
            child: _buildField(
              '备注',
              TextField(
                controller: _remarkController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                  hintText: '非必填',
                  hintStyle: textHint,
                ),
              ),
            ),
          ),
          const Divider(
            height: 1,
            thickness: borderWidthThin,
            color: colorDivider,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: spacingL,
              vertical: spacingM,
            ),
            child: _buildField(
              '余额',
              TextField(
                controller: _balanceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ),
          const Divider(
            height: 1,
            thickness: borderWidthThin,
            color: colorDivider,
          ),
          Padding(
            padding: const EdgeInsets.all(spacingL),
            child: SizedBox(
              height: 44,
              child: FilledButton(
                onPressed: () {
                  FocusManager.instance.primaryFocus?.unfocus();
                  _save();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: themeColor,
                  foregroundColor: colorTextOnPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(radiusXS),
                  ),
                ),
                child: const Text('保存'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField(String label, Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          children: [
            Text(label, style: textBody),
            const Spacer(),
            SizedBox(width: constraints.maxWidth * 0.5, child: child),
          ],
        );
      },
    );
  }
}
