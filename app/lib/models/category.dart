import 'package:flutter/material.dart';

class Category {
  final IconData icon;
  final String name;

  const Category({required this.icon, required this.name});
}

const expenseCategories = [
  Category(icon: Icons.restaurant_outlined, name: '餐饮'),
  Category(icon: Icons.fastfood_outlined, name: '零食'),
  Category(icon: Icons.directions_bus_outlined, name: '交通'),
  Category(icon: Icons.shopping_bag_outlined, name: '购物'),
  Category(icon: Icons.shopping_basket_outlined, name: '日用品'),
  Category(icon: Icons.home_outlined, name: '住房'),
  Category(icon: Icons.bolt_outlined, name: '水电燃气'),
  Category(icon: Icons.local_hospital_outlined, name: '医疗'),
  Category(icon: Icons.school_outlined, name: '教育'),
  Category(icon: Icons.phone_android_outlined, name: '通讯'),
  Category(icon: Icons.sports_esports_outlined, name: '娱乐'),
  Category(icon: Icons.fitness_center_outlined, name: '运动健身'),
  Category(icon: Icons.face_outlined, name: '美妆'),
  Category(icon: Icons.pets_outlined, name: '宠物'),
  Category(icon: Icons.card_giftcard_outlined, name: '人情'),
  Category(icon: Icons.devices_other_outlined, name: '数码'),
  Category(icon: Icons.checkroom_outlined, name: '服饰'),
  Category(icon: Icons.menu_book_outlined, name: '书籍'),
  Category(icon: Icons.local_cafe_outlined, name: '咖啡'),
  Category(icon: Icons.eco_outlined, name: '水果蔬菜'),
  Category(icon: Icons.directions_car_outlined, name: '养车'),
  Category(icon: Icons.construction_outlined, name: '装修'),
  Category(icon: Icons.local_shipping_outlined, name: '快递'),
  Category(icon: Icons.photo_camera_outlined, name: '摄影'),
  Category(icon: Icons.local_activity_outlined, name: '电影'),
  Category(icon: Icons.volunteer_activism_outlined, name: '捐赠'),
  Category(icon: Icons.local_bar_outlined, name: '烟酒'),
  Category(icon: Icons.child_care_outlined, name: '母婴'),
  Category(icon: Icons.content_cut_outlined, name: '理发'),
  Category(icon: Icons.security_outlined, name: '保险'),
  Category(icon: Icons.music_note_outlined, name: '音乐'),
  Category(icon: Icons.cleaning_services_outlined, name: '生活服务'),
  Category(icon: Icons.confirmation_number_outlined, name: '门票'),
  Category(icon: Icons.flight_outlined, name: '旅行'),
  Category(icon: Icons.more_horiz, name: '其他'),
];

const incomeCategories = [
  Category(icon: Icons.work_outlined, name: '工资'),
  Category(icon: Icons.trending_up_outlined, name: '理财'),
  Category(icon: Icons.card_giftcard_outlined, name: '红包'),
  Category(icon: Icons.monetization_on_outlined, name: '奖金'),
  Category(icon: Icons.store_outlined, name: '生意'),
  Category(icon: Icons.account_balance_outlined, name: '利息'),
  Category(icon: Icons.handyman_outlined, name: '兼职'),
  Category(icon: Icons.receipt_long_outlined, name: '报销'),
  Category(icon: Icons.edit_note_outlined, name: '稿费'),
  Category(icon: Icons.house_outlined, name: '租金'),
  Category(icon: Icons.undo_outlined, name: '退款'),
  Category(icon: Icons.emoji_events_outlined, name: '中奖'),
  Category(icon: Icons.sell_outlined, name: '卖闲置'),
  Category(icon: Icons.more_horiz, name: '其他'),
];
