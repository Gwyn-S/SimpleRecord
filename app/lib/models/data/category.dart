import 'package:flutter/material.dart';

class Category {
  final IconData icon;
  final String name;

  const Category({required this.icon, required this.name});
}

const expenseCategories = [
  Category(icon: Icons.restaurant_outlined, name: '餐饮'),
  Category(icon: Icons.directions_bus_outlined, name: '交通'),
  Category(icon: Icons.checkroom_outlined, name: '服饰'),
  Category(icon: Icons.apple_outlined, name: '水果'),
  Category(icon: Icons.local_parking_outlined, name: '停车'),
  Category(icon: Icons.fastfood_outlined, name: '零食'),
  Category(icon: Icons.eco_outlined, name: '买菜'),
  Category(icon: Icons.phone_android_outlined, name: '通讯'),
  Category(icon: Icons.cleaning_services_outlined, name: '日用品'),
  Category(icon: Icons.movie_outlined, name: '娱乐'),
  Category(icon: Icons.smoking_rooms_outlined, name: '烟酒'),
  Category(icon: Icons.face_outlined, name: '美容'),
  Category(icon: Icons.diamond_outlined, name: '珠宝'),
  Category(icon: Icons.local_shipping_outlined, name: '快递'),
  Category(icon: Icons.local_hospital_outlined, name: '医药'),
  Category(icon: Icons.security_outlined, name: '保险'),
  Category(icon: Icons.trending_up_outlined, name: '投资'),
  Category(icon: Icons.menu_book_outlined, name: '学习'),
  Category(icon: Icons.weekend_outlined, name: '家居'),
  Category(icon: Icons.tv_outlined, name: '电器'),
  Category(icon: Icons.photo_camera_outlined, name: '数码'),
  Category(icon: Icons.android, name: 'APP'),
  Category(icon: Icons.home_outlined, name: '住房'),
  Category(icon: Icons.water_drop_outlined, name: '水燃电'),
  Category(icon: Icons.build_outlined, name: '维修'),
  Category(icon: Icons.local_gas_station_outlined, name: '加油'),
  Category(icon: Icons.add_road_outlined, name: '桥路费'),
  Category(icon: Icons.mail_outlined, name: '发红包'),
  Category(icon: Icons.card_giftcard_outlined, name: '送礼'),
  Category(icon: Icons.child_care_outlined, name: '孩子'),
  Category(icon: Icons.elderly_outlined, name: '老人'),
  Category(icon: Icons.pets_outlined, name: '宠物'),
  Category(icon: Icons.sports_esports_outlined, name: '游戏'),
  Category(icon: Icons.fitness_center_outlined, name: '健身'),
  Category(icon: Icons.redo_outlined, name: '还款'),
  Category(icon: Icons.content_cut_outlined, name: '理发'),
];

const incomeCategories = [
  Category(icon: Icons.work_outlined, name: '工资'),
  Category(icon: Icons.access_time_outlined, name: '兼职'),
  Category(icon: Icons.cottage_outlined, name: '生活费'),
  Category(icon: Icons.mail_outlined, name: '收红包'),
  Category(icon: Icons.military_tech_outlined, name: '奖金'),
  Category(icon: Icons.trending_up_outlined, name: '投资'),
  Category(icon: Icons.receipt_long_outlined, name: '报销'),
  Category(icon: Icons.currency_exchange_outlined, name: '借款'),
  Category(icon: Icons.undo_outlined, name: '退款'),
  Category(icon: Icons.diamond_outlined, name: '零钱通'),
  Category(icon: Icons.savings_outlined, name: '余额宝'),
];