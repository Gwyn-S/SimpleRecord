import 'lunar_info.dart';
import 'solar_terms.dart';
import 'lunar_festival.dart';
import 'solar_festival.dart';

/// 农历日期工具，最大支持到2099年
class ChineseDate {
  static const List<String> DAY_NAME = ['一', '二', '三', '四', '五', '六', '七', '八', '九', '十'];
  static const List<String> MONTH_NAME = ['一', '二', '三', '四', '五', '六', '七', '八', '九', '十', '十一', '十二'];
  static const List<String> MONTH_NAME_TRADITIONAL = ['正', '二', '三', '四', '五', '六', '七', '八', '九', '寒', '冬', '腊'];

  /// 农历年
  late final int chineseYear;

  /// 农历月，闰N月这个值就是N+1
  late final int month;

  /// 当前农历月份是否为闰月
  late final bool isLeapMonth;

  /// 农历日
  late final int day;

  /// 公历年
  late final int gregorianYear;

  /// 公历月，从1开始
  late final int gregorianMonthBase1;

  /// 公历日
  late final int gregorianDay;

  /// 通过公历日期构造
  ChineseDate(DateTime date) {
    gregorianYear = date.year;
    gregorianMonthBase1 = date.month;
    gregorianDay = date.day;

    // 求出和1900年1月31日相差的天数
    int offset = date.difference(DateTime(1900, 1, 31)).inDays;

    // 计算农历年份
    int daysOfYear;
    int iYear;
    iYear = LunarInfo.BASE_YEAR;
    while (iYear <= LunarInfo.MAX_YEAR) {
      daysOfYear = LunarInfo.yearDays(iYear);
      if (offset < daysOfYear) {
        break;
      }
      offset -= daysOfYear;
      iYear++;
    }
    chineseYear = iYear;

    // 计算农历月份
    int leapMonth = LunarInfo.leapMonth(chineseYear);
    int monthNum;
    int daysOfMonth;
    bool hasLeapMonth = false;
    monthNum = 1;
    while (monthNum < 13) {
      if (leapMonth > 0 && monthNum == leapMonth + 1) {
        daysOfMonth = LunarInfo.leapDays(chineseYear);
        hasLeapMonth = true;
      } else {
        daysOfMonth = LunarInfo.monthDays(
          chineseYear,
          hasLeapMonth ? monthNum - 1 : monthNum,
        );
      }
      if (offset < daysOfMonth) {
        break;
      }
      offset -= daysOfMonth;
      monthNum++;
    }
    isLeapMonth = leapMonth > 0 && monthNum == leapMonth + 1;
    if (hasLeapMonth && !isLeapMonth) {
      monthNum--;
    }
    month = monthNum;
    day = offset + 1;
  }

  /// 获得农历月份（中文，例如二月，十二月，或者闰一月）
  String getChineseMonth() {
    return getChineseMonthName();
  }

  /// 获得农历月称呼（中文，例如二月，腊月，或者闰正月）
  String getChineseMonthName() {
    return getChineseMonthNameInternal(isLeapMonth, isLeapMonth ? month - 1 : month, true);
  }

  /// 获得农历日（例如初一，初二，三十）
  String getChineseDay() {
    List<String> chineseTen = ['初', '十', '廿', '卅'];
    int n = (day % 10 == 0) ? 9 : day % 10 - 1;
    if (day > 30) {
      return '';
    }
    switch (day) {
      case 10:
        return '初十';
      case 20:
        return '二十';
      case 30:
        return '三十';
      default:
        return '${chineseTen[day ~/ 10]}${DAY_NAME[n]}';
    }
  }

  /// 获得农历节日
  String? getLunarFestivals() {
    return LunarFestival.getFestivals(chineseYear, month, day);
  }

  /// 获得公历节日
  String? getSolarFestivals() {
    return SolarFestival.getFestivals(gregorianMonthBase1, gregorianDay);
  }

  /// 获得节气
  String getTerm() {
    return SolarTerms.getTermFromDate(gregorianYear, gregorianMonthBase1, gregorianDay);
  }

  /// 获取农历月份名称（内部方法）
  static String getChineseMonthNameInternal(bool isLeapMonth, int month, bool isTraditional) {
    return (isLeapMonth ? '闰' : '') +
        (isTraditional ? MONTH_NAME_TRADITIONAL : MONTH_NAME)[month - 1] +
        '月';
  }
}
