class AssetAccountCategory {
  final dynamic icon;
  final String? iconPath;
  final String name;

  const AssetAccountCategory({this.icon, this.iconPath, required this.name});
}

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

  AssetAccount({
    required this.id,
    required this.categoryName,
    required this.name,
    this.balanceCents = 0,
  });

  AssetAccountCategory? get category {
    for (final c in assetAccountCategories) {
      if (c.name == categoryName) return c;
    }
    return null;
  }

  Map<String, dynamic> toDbMap() => {
        'id': id,
        'category_name': categoryName,
        'name': name,
        'balance_cents': balanceCents,
      };

  factory AssetAccount.fromDbMap(Map<String, dynamic> map) => AssetAccount(
        id: map['id'] as String,
        categoryName: map['category_name'] as String,
        name: map['name'] as String,
        balanceCents: map['balance_cents'] as int,
      );
}
