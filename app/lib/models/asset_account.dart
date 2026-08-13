class AssetAccountCategory {
  final dynamic icon;
  final String? iconPath;
  final String name;

  const AssetAccountCategory({this.icon, this.iconPath, required this.name});
}

/// 计入负债的分类：余额作为欠款额单独统计，净资产 = 资产 − 负债。
const _debtCategoryNames = {'信用卡', '负债'};

final assetAccountCategories = [
  const AssetAccountCategory(iconPath: 'assets/icons/cash.svg', name: '现金'),
  const AssetAccountCategory(iconPath: 'assets/icons/online_banking.svg', name: '网络支付'),
  const AssetAccountCategory(iconPath: 'assets/icons/savings_card.svg', name: '储蓄卡'),
  const AssetAccountCategory(iconPath: 'assets/icons/credit_card.svg', name: '信用卡'),
  const AssetAccountCategory(iconPath: 'assets/icons/investment.svg', name: '投资'),
  const AssetAccountCategory(iconPath: 'assets/icons/total_debt.svg', name: '负债'),
  const AssetAccountCategory(iconPath: 'assets/icons/bonds.svg', name: '债券'),
  const AssetAccountCategory(iconPath: 'assets/icons/assets.svg', name: '自定义资产'),
];

class AssetAccount {
  final String id;
  String categoryName;
  String name;
  int balanceCents;
  String remark;
  String cardLast4;
  String iconPath;

  AssetAccount({
    required this.id,
    required this.categoryName,
    required this.name,
    this.balanceCents = 0,
    this.remark = '',
    this.cardLast4 = '',
    this.iconPath = '',
  });

  AssetAccountCategory? get category {
    for (final c in assetAccountCategories) {
      if (c.name == categoryName) return c;
    }
    return null;
  }

  bool get isDebtAccount => _debtCategoryNames.contains(categoryName);

  Map<String, dynamic> toDbMap() => {
        'id': id,
        'category_name': categoryName,
        'name': name,
        'balance_cents': balanceCents,
        'remark': remark,
        'card_last4': cardLast4,
        'icon_path': iconPath,
      };

  factory AssetAccount.fromDbMap(Map<String, dynamic> map) => AssetAccount(
        id: map['id'] as String,
        categoryName: map['category_name'] as String,
        name: map['name'] as String,
        balanceCents: map['balance_cents'] as int,
        remark: (map['remark'] as String?) ?? '',
        cardLast4: (map['card_last4'] as String?) ?? '',
        iconPath: (map['icon_path'] as String?) ?? '',
      );
}
