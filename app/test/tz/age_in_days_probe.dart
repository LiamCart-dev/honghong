// #35 回归测试用的探针：由 test/stage_tz_test.dart 在 TZ=Asia/Shanghai 的子进程里运行。
// 文件名不以 _test 结尾，flutter test 不会把它当测试直接跑。
import 'dart:convert';
import 'dart:io';

import 'package:honghong/domain/stages/cry_stage.dart';

void main() {
  // 下面的 DateTime(...) 都是进程本地时间（北京时间）
  final birth = DateTime(2026, 9, 1);
  int? utcAt(int d, int h, int m) => ageInDays(birth, DateTime(2026, 9, d, h, m).toUtc());
  print(
    jsonEncode({
      'offsetHours': DateTime(2026, 9, 8).timeZoneOffset.inHours,
      // 北京 0–8 点，UTC 输入：都应该是第 7 天
      'utc_0000': utcAt(8, 0, 0),
      'utc_0300': utcAt(8, 3, 0),
      'utc_0730': utcAt(8, 7, 30),
      'utc_0759': utcAt(8, 7, 59),
      'utc_0800': utcAt(8, 8, 0),
      // 日期边界：前一天 23:59 是第 6 天
      'utc_prev_2359': utcAt(7, 23, 59),
      // 本地输入（原来就对）
      'local_0730': ageInDays(birth, DateTime(2026, 9, 8, 7, 30)),
      // 生日也是 UTC：北京 2026-09-01 00:00 = 2026-08-31T16:00Z
      'utcBirth_utcAt_0730': ageInDays(birth.toUtc(), DateTime(2026, 9, 8, 7, 30).toUtc()),
      'parsedZ': ageInDays(DateTime.parse('2026-08-31T16:00:00Z'), DateTime.parse('2026-09-07T23:30:00Z')),
      // 出生当天北京 00:30（UTC 是前一天 16:30）→ 第 0 天；出生前一天北京 23:00 → null
      'birthDay_0030': ageInDays(birth, DateTime(2026, 9, 1, 0, 30).toUtc()),
      'beforeBirth_2300': ageInDays(birth, DateTime(2026, 8, 31, 23, 0).toUtc()),
      // 跨月、跨年
      'crossMonth': ageInDays(DateTime(2026, 9, 30), DateTime(2026, 10, 1, 2, 0).toUtc()),
      'crossYear': ageInDays(DateTime(2026, 12, 31), DateTime(2027, 1, 1, 7, 59).toUtc()),
    }),
  );
}
