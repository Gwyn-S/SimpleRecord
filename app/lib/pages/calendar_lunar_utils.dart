import 'package:lunar/lunar.dart';

class LunarInfo {
  final String text;
  final bool isFestival;
  const LunarInfo({required this.text, required this.isFestival});
}

const _solarFestivals = {
  0x0101: '元旦', 0x020E: '情人', 0x0308: '妇女', 0x030C: '植树',
  0x0401: '愚人', 0x0501: '劳动', 0x0504: '青年', 0x0601: '儿童',
  0x0701: '建党', 0x0801: '建军', 0x090A: '教师', 0x0A01: '国庆',
  0x0C19: '圣诞',
};

String solarFest(DateTime date) => _solarFestivals[(date.month << 8) | date.day] ?? '';

LunarInfo lunarInfo(DateTime date) {
  final lunar = Lunar.fromDate(date);
  final festivalList = lunar.getFestivals();
  final jieQi = lunar.getJieQi();
  final festivalStr = festivalList.isNotEmpty ? festivalList.first : '';
  final lunarText = festivalStr.isNotEmpty
      ? festivalStr
      : jieQi.isNotEmpty
          ? jieQi
          : lunar.getDay() == 1
              ? '${lunar.getMonthInChinese()}月'
              : lunar.getDayInChinese();
  return LunarInfo(
    text: lunarText,
    isFestival: festivalStr.isNotEmpty || jieQi.isNotEmpty,
  );
}
