import 'package:flutter/material.dart';

class Category {
  final IconData icon;
  final String name;

  const Category({required this.icon, required this.name});
}

const expenseCategories = [
  Category(icon: Icons.restaurant, name: '餐饮'),
  Category(icon: Icons.directions_bus, name: '交通'),
  Category(icon: Icons.shopping_bag, name: '购物'),
  Category(icon: Icons.home, name: '住房'),
  Category(icon: Icons.local_hospital, name: '医疗'),
  Category(icon: Icons.school, name: '教育'),
  Category(icon: Icons.sports_esports, name: '娱乐'),
  Category(icon: Icons.pets, name: '宠物'),
  Category(icon: Icons.card_giftcard, name: '人情'),
  Category(icon: Icons.devices_other, name: '数码'),
  Category(icon: Icons.checkroom, name: '服饰'),
  Category(icon: Icons.more_horiz, name: '其他'),
];

const incomeCategories = [
  Category(icon: Icons.work, name: '工资'),
  Category(icon: Icons.trending_up, name: '理财'),
  Category(icon: Icons.card_giftcard, name: '红包'),
  Category(icon: Icons.monetization_on, name: '奖金'),
  Category(icon: Icons.store, name: '生意'),
  Category(icon: Icons.account_balance, name: '利息'),
  Category(icon: Icons.more_horiz, name: '其他'),
];
