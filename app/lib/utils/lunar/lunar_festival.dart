// ignore_for_file: constant_identifier_names

import 'lunar_info.dart';

/// 农历节日封装
class LunarFestival {
  /// 农历节日表
  static const Map<String, String> L_FESTIVAL = {
    '1-1': '春节',
    '1-15': '元宵',
    '5-5': '端午',
    '7-7': '七夕',
    '7-15': '中元',
    '8-15': '中秋',
    '9-9': '重阳',
    '10-15': '下元',
    '12-8': '腊八',
    '12-23': '小年',
    '12-30': '除夕',
  };

  /// 获得农历节日
  /// [year] 农历年
  /// [month] 农历月
  /// [day] 农历日
  /// 返回节日名称，若无节日则返回null
  static String? getFestivals(int year, int month, int day) {
    // 除夕判断：如果12月是小月，则29为除夕，否则30为除夕
    if (month == 12 && day == 29) {
      if (29 == LunarInfo.monthDays(year, month)) {
        day++;
      }
    }
    return L_FESTIVAL['$month-$day'];
  }
}
