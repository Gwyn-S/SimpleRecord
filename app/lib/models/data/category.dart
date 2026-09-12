import 'package:flutter/material.dart';

/// 图标名 -> IconData 映射表，用于数据库分类数据解析与展示。
const Map<String, IconData> categoryIconMap = {
  'restaurant_outlined': Icons.restaurant_outlined,
  'directions_bus_outlined': Icons.directions_bus_outlined,
  'checkroom_outlined': Icons.checkroom_outlined,
  'apple_outlined': Icons.apple_outlined,
  'local_parking_outlined': Icons.local_parking_outlined,
  'fastfood_outlined': Icons.fastfood_outlined,
  'eco_outlined': Icons.eco_outlined,
  'phone_android_outlined': Icons.phone_android_outlined,
  'cleaning_services_outlined': Icons.cleaning_services_outlined,
  'movie_outlined': Icons.movie_outlined,
  'smoking_rooms_outlined': Icons.smoking_rooms_outlined,
  'face_outlined': Icons.face_outlined,
  'diamond_outlined': Icons.diamond_outlined,
  'local_shipping_outlined': Icons.local_shipping_outlined,
  'local_hospital_outlined': Icons.local_hospital_outlined,
  'security_outlined': Icons.security_outlined,
  'trending_up_outlined': Icons.trending_up_outlined,
  'menu_book_outlined': Icons.menu_book_outlined,
  'weekend_outlined': Icons.weekend_outlined,
  'tv_outlined': Icons.tv_outlined,
  'photo_camera_outlined': Icons.photo_camera_outlined,
  'android': Icons.android,
  'home_outlined': Icons.home_outlined,
  'water_drop_outlined': Icons.water_drop_outlined,
  'build_outlined': Icons.build_outlined,
  'local_gas_station_outlined': Icons.local_gas_station_outlined,
  'add_road_outlined': Icons.add_road_outlined,
  'mail_outlined': Icons.mail_outlined,
  'card_giftcard_outlined': Icons.card_giftcard_outlined,
  'child_care_outlined': Icons.child_care_outlined,
  'elderly_outlined': Icons.elderly_outlined,
  'pets_outlined': Icons.pets_outlined,
  'sports_esports_outlined': Icons.sports_esports_outlined,
  'fitness_center_outlined': Icons.fitness_center_outlined,
  'redo_outlined': Icons.redo_outlined,
  'content_cut_outlined': Icons.content_cut_outlined,
  'work_outlined': Icons.work_outlined,
  'access_time_outlined': Icons.access_time_outlined,
  'cottage_outlined': Icons.cottage_outlined,
  'military_tech_outlined': Icons.military_tech_outlined,
  'receipt_long_outlined': Icons.receipt_long_outlined,
  'currency_exchange_outlined': Icons.currency_exchange_outlined,
  'undo_outlined': Icons.undo_outlined,
  'savings_outlined': Icons.savings_outlined,
  'settings_outlined': Icons.settings_outlined,
  'flight_outlined': Icons.flight_outlined,
  'train_outlined': Icons.train_outlined,
  'directions_car_outlined': Icons.directions_car_outlined,
  'two_wheeler_outlined': Icons.two_wheeler_outlined,
  'shopping_cart_outlined': Icons.shopping_cart_outlined,
  'shopping_bag_outlined': Icons.shopping_bag_outlined,
  'storefront_outlined': Icons.storefront_outlined,
  'point_of_sale_outlined': Icons.point_of_sale_outlined,
  'coffee_outlined': Icons.coffee_outlined,
  'liquor_outlined': Icons.liquor_outlined,
  'cake_outlined': Icons.cake_outlined,
  'icecream_outlined': Icons.icecream_outlined,
  'umbrella_outlined': Icons.umbrella_outlined,
  'beach_access_outlined': Icons.beach_access_outlined,
  'celebration_outlined': Icons.celebration_outlined,
  'school_outlined': Icons.school_outlined,
  'medical_services_outlined': Icons.medical_services_outlined,
  'laptop_outlined': Icons.laptop_outlined,
  'devices_outlined': Icons.devices_outlined,
  'headphones_outlined': Icons.headphones_outlined,
  'watch_outlined': Icons.watch_outlined,
  'camera_outlined': Icons.camera_outlined,
  'light_outlined': Icons.light_outlined,
  'bed_outlined': Icons.bed_outlined,
  'chair_outlined': Icons.chair_outlined,
  'table_restaurant_outlined': Icons.table_restaurant_outlined,
  'account_balance_outlined': Icons.account_balance_outlined,
  'payments_outlined': Icons.payments_outlined,
  'credit_card_outlined': Icons.credit_card_outlined,
  'account_balance_wallet_outlined': Icons.account_balance_wallet_outlined,
  'attach_money_outlined': Icons.attach_money_outlined,
  'currency_bitcoin_outlined': Icons.currency_bitcoin_outlined,
};

class Category {
  final String? ledgerId;
  final String name;
  final bool isExpense;
  final String iconName;
  final int sortOrder;

  const Category({
    this.ledgerId,
    required this.name,
    required this.isExpense,
    required this.iconName,
    this.sortOrder = 0,
  });

  IconData get icon => categoryIconMap[iconName] ?? Icons.help_outline;

  Category copyWith({String? name, String? iconName, int? sortOrder}) {
    return Category(
      ledgerId: ledgerId,
      name: name ?? this.name,
      isExpense: isExpense,
      iconName: iconName ?? this.iconName,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  Map<String, dynamic> toDbMap() => {
    'ledger_id': ledgerId,
    'name': name,
    'is_expense': isExpense ? 1 : 0,
    'icon_name': iconName,
    'sort_order': sortOrder,
  };

  factory Category.fromDbMap(Map<String, dynamic> map) => Category(
    ledgerId: map['ledger_id'] as String?,
    name: map['name'] as String,
    isExpense: map['is_expense'] == 1,
    iconName: map['icon_name'] as String,
    sortOrder: map['sort_order'] as int? ?? 0,
  );
}

/// 默认分类种子（首次建库写入数据库）。
const List<Category> defaultExpenseCategorySeeds = [
  Category(name: '餐饮', isExpense: true, iconName: 'restaurant_outlined', sortOrder: 0),
  Category(name: '交通', isExpense: true, iconName: 'directions_bus_outlined', sortOrder: 1),
  Category(name: '服饰', isExpense: true, iconName: 'checkroom_outlined', sortOrder: 2),
  Category(name: '水果', isExpense: true, iconName: 'apple_outlined', sortOrder: 3),
  Category(name: '停车', isExpense: true, iconName: 'local_parking_outlined', sortOrder: 4),
  Category(name: '零食', isExpense: true, iconName: 'fastfood_outlined', sortOrder: 5),
  Category(name: '买菜', isExpense: true, iconName: 'eco_outlined', sortOrder: 6),
  Category(name: '通讯', isExpense: true, iconName: 'phone_android_outlined', sortOrder: 7),
  Category(name: '日用品', isExpense: true, iconName: 'cleaning_services_outlined', sortOrder: 8),
  Category(name: '娱乐', isExpense: true, iconName: 'movie_outlined', sortOrder: 9),
  Category(name: '烟酒', isExpense: true, iconName: 'smoking_rooms_outlined', sortOrder: 10),
  Category(name: '美容', isExpense: true, iconName: 'face_outlined', sortOrder: 11),
  Category(name: '珠宝', isExpense: true, iconName: 'diamond_outlined', sortOrder: 12),
  Category(name: '快递', isExpense: true, iconName: 'local_shipping_outlined', sortOrder: 13),
  Category(name: '医药', isExpense: true, iconName: 'local_hospital_outlined', sortOrder: 14),
  Category(name: '保险', isExpense: true, iconName: 'security_outlined', sortOrder: 15),
  Category(name: '投资', isExpense: true, iconName: 'trending_up_outlined', sortOrder: 16),
  Category(name: '学习', isExpense: true, iconName: 'menu_book_outlined', sortOrder: 17),
  Category(name: '家居', isExpense: true, iconName: 'weekend_outlined', sortOrder: 18),
  Category(name: '电器', isExpense: true, iconName: 'tv_outlined', sortOrder: 19),
  Category(name: '数码', isExpense: true, iconName: 'photo_camera_outlined', sortOrder: 20),
  Category(name: 'APP', isExpense: true, iconName: 'android', sortOrder: 21),
  Category(name: '住房', isExpense: true, iconName: 'home_outlined', sortOrder: 22),
  Category(name: '水燃电', isExpense: true, iconName: 'water_drop_outlined', sortOrder: 23),
  Category(name: '维修', isExpense: true, iconName: 'build_outlined', sortOrder: 24),
  Category(name: '加油', isExpense: true, iconName: 'local_gas_station_outlined', sortOrder: 25),
  Category(name: '桥路费', isExpense: true, iconName: 'add_road_outlined', sortOrder: 26),
  Category(name: '发红包', isExpense: true, iconName: 'mail_outlined', sortOrder: 27),
  Category(name: '送礼', isExpense: true, iconName: 'card_giftcard_outlined', sortOrder: 28),
  Category(name: '孩子', isExpense: true, iconName: 'child_care_outlined', sortOrder: 29),
  Category(name: '老人', isExpense: true, iconName: 'elderly_outlined', sortOrder: 30),
  Category(name: '宠物', isExpense: true, iconName: 'pets_outlined', sortOrder: 31),
  Category(name: '游戏', isExpense: true, iconName: 'sports_esports_outlined', sortOrder: 32),
  Category(name: '健身', isExpense: true, iconName: 'fitness_center_outlined', sortOrder: 33),
  Category(name: '还款', isExpense: true, iconName: 'redo_outlined', sortOrder: 34),
  Category(name: '理发', isExpense: true, iconName: 'content_cut_outlined', sortOrder: 35),
];

const List<Category> defaultIncomeCategorySeeds = [
  Category(name: '工资', isExpense: false, iconName: 'work_outlined', sortOrder: 0),
  Category(name: '兼职', isExpense: false, iconName: 'access_time_outlined', sortOrder: 1),
  Category(name: '生活费', isExpense: false, iconName: 'cottage_outlined', sortOrder: 2),
  Category(name: '收红包', isExpense: false, iconName: 'mail_outlined', sortOrder: 3),
  Category(name: '奖金', isExpense: false, iconName: 'military_tech_outlined', sortOrder: 4),
  Category(name: '投资', isExpense: false, iconName: 'trending_up_outlined', sortOrder: 5),
  Category(name: '报销', isExpense: false, iconName: 'receipt_long_outlined', sortOrder: 6),
  Category(name: '借款', isExpense: false, iconName: 'currency_exchange_outlined', sortOrder: 7),
  Category(name: '退款', isExpense: false, iconName: 'undo_outlined', sortOrder: 8),
  Category(name: '零钱通', isExpense: false, iconName: 'diamond_outlined', sortOrder: 9),
  Category(name: '余额宝', isExpense: false, iconName: 'savings_outlined', sortOrder: 10),
];

/// 运行时分类缓存：启动时由 category_service 填充，页面引用点不变。
List<Category> expenseCategories = [];
List<Category> incomeCategories = [];