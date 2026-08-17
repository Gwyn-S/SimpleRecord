import 'dart:ui';

class AssetAccountCategory {
  final dynamic icon;
  final String? iconPath;
  final String name;
  final Color color;

  const AssetAccountCategory({this.icon, this.iconPath, required this.name, required this.color});
}

/// 计入负债的分类：余额作为欠款额单独统计，净资产 = 资产 − 负债。
const _debtCategoryNames = {'信用卡', '负债'};

/// 银行名称 → 图标路径，供页面和服务共用。
const bankIconMap = {
  '工商银行': 'assets/icons/icbc.svg',
  '建设银行': 'assets/icons/ccb.svg',
  '农业银行': 'assets/icons/abc.svg',
  '中国银行': 'assets/icons/boc.svg',
  '招商银行': 'assets/icons/cmb.svg',
  '交通银行': 'assets/icons/comm_bank.svg',
  '中信银行': 'assets/icons/citic.svg',
  '浦发银行': 'assets/icons/spdb.svg',
  '广发银行': 'assets/icons/cgb.svg',
};

final assetAccountCategories = [
  const AssetAccountCategory(iconPath: 'assets/icons/cash.svg', name: '现金', color: Color(0xFFE53935)),
  const AssetAccountCategory(iconPath: 'assets/icons/savings_card.svg', name: '储蓄卡', color: Color(0xFF43A047)),
  const AssetAccountCategory(iconPath: 'assets/icons/credit_card.svg', name: '信用卡', color: Color(0xFFFDD835)),
  const AssetAccountCategory(iconPath: 'assets/icons/online_banking.svg', name: '网络账户', color: Color(0xFF1E88E5)),
  const AssetAccountCategory(iconPath: 'assets/icons/investment.svg', name: '投资', color: Color(0xFFFB8C00)),
  const AssetAccountCategory(iconPath: 'assets/icons/total_debt.svg', name: '负债', color: Color(0xFF8E24AA)),
  const AssetAccountCategory(iconPath: 'assets/icons/bonds.svg', name: '债券', color: Color(0xFF66BB6A)),
  const AssetAccountCategory(iconPath: 'assets/icons/assets.svg', name: '自定义资产', color: Color(0xFF546E7A)),
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

  String get displayName => cardLast4.isNotEmpty ? '$name($cardLast4)' : name;

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
