import 'lunar/chinese_date.dart';
import 'lunar/lunar_festival.dart';
import 'lunar/solar_festival.dart';
import 'lunar/solar_terms.dart';

/// 农历工具类
class LunarUtils {
  static final Map<int, String> _displayCache = {};
  static final Map<int, bool> _festivalCache = {};

  static int _dayKey(DateTime date) =>
      date.year * 10000 + date.month * 100 + date.day;

  static bool _isInRange(DateTime date) =>
      date.year >= 1900 && date.year <= 2099;

  /// 获取农历显示文字（遵循 NCalendar 优先级）
  /// 优先级：替换文字 > 农历节日 > 节气 > 公历节日 > 农历日期
  static String getDisplayText(DateTime date) {
    return _displayCache.putIfAbsent(
      _dayKey(date),
      () => _computeDisplayText(date),
    );
  }

  static String _computeDisplayText(DateTime date) {
    if (!_isInRange(date)) return '';

    final chineseDate = ChineseDate(date);

    // 1. 农历节日
    final lunarFestival = LunarFestival.getFestivals(
      chineseDate.chineseYear,
      chineseDate.month,
      chineseDate.day,
    );
    if (lunarFestival != null) return lunarFestival;

    // 2. 节气
    final solarTerm = SolarTerms.getTermFromDate(
      date.year,
      date.month,
      date.day,
    );
    if (solarTerm.isNotEmpty) return solarTerm;

    // 3. 公历节日
    final solarFestival = SolarFestival.getFestivals(date.month, date.day);
    if (solarFestival != null) return solarFestival;

    // 4. 农历日期
    final day = chineseDate.day;
    if (day == 1) {
      // 初一显示月份名
      return chineseDate.getChineseMonthName();
    }
    return chineseDate.getChineseDay();
  }

  /// 判断是否为节日或节气（用于特殊颜色显示）
  static bool isFestivalOrJieQi(DateTime date) {
    return _festivalCache.putIfAbsent(
      _dayKey(date),
      () => _computeFestivalOrJieQi(date),
    );
  }

  static bool _computeFestivalOrJieQi(DateTime date) {
    if (!_isInRange(date)) return false;

    final chineseDate = ChineseDate(date);

    // 农历节日
    if (LunarFestival.getFestivals(
          chineseDate.chineseYear,
          chineseDate.month,
          chineseDate.day,
        ) !=
        null) {
      return true;
    }

    // 节气
    final solarTerm = SolarTerms.getTermFromDate(
      date.year,
      date.month,
      date.day,
    );
    if (solarTerm.isNotEmpty) return true;

    // 公历节日
    if (SolarFestival.getFestivals(date.month, date.day) != null) return true;

    return false;
  }
}
