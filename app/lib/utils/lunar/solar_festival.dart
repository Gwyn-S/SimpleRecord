/// 公历节日封装
class SolarFestival {
  /// 公历节日表
  static const Map<String, String> S_FESTIVAL = {
    '1-1': '元旦',
    '2-14': '情人',
    '3-8': '妇女',
    '3-12': '植树',
    '4-1': '愚人',
    '5-1': '劳动',
    '5-4': '青年',
    '6-1': '儿童',
    '7-1': '建党',
    '8-1': '建军',
    '9-10': '教师',
    '10-1': '国庆',
  };

  /// 获得公历节日
  /// [month] 公历月
  /// [day] 公历日
  /// 返回节日名称，若无节日则返回null
  static String? getFestivals(int month, int day) {
    return S_FESTIVAL['$month-$day'];
  }
}
