// #35：ageInDays 收到 UTC 时间时要按设备本地日历日算。
// CI 的机器时区是 UTC，在进程里直接测发现不了问题，所以在 TZ=Asia/Shanghai 的子进程里跑探针。
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/domain/stages/cry_stage.dart';

void main() {
  test('北京时间（子进程 TZ=Asia/Shanghai）：0–8 点的 UTC 输入、日期边界、UTC 生日、跨月跨年', () async {
    final dart = Platform.environment['FLUTTER_ROOT'] != null ? '${Platform.environment['FLUTTER_ROOT']}/bin/dart' : 'dart';
    final r = await Process.run(dart, ['run', 'test/tz/age_in_days_probe.dart'], environment: {'TZ': 'Asia/Shanghai'});
    expect(r.exitCode, 0, reason: '${r.stdout}\n${r.stderr}');
    final line = (r.stdout as String).trim().split('\n').last;
    final m = jsonDecode(line) as Map<String, dynamic>;
    expect(m['offsetHours'], 8, reason: '子进程没有切到北京时间');
    expect(m, {
      'offsetHours': 8,
      'utc_0000': 7,
      'utc_0300': 7,
      'utc_0730': 7,
      'utc_0759': 7,
      'utc_0800': 7,
      'utc_prev_2359': 6,
      'local_0730': 7,
      'utcBirth_utcAt_0730': 7,
      'parsedZ': 7,
      'birthDay_0030': 0,
      'beforeBirth_2300': null,
      'crossMonth': 1,
      'crossYear': 1,
    });
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('本机时区下：同一时刻传本地时间和 UTC 时间结果一样（一天 24 小时每 15 分钟）', () {
    final birth = DateTime(2026, 9, 1);
    for (var minutes = 0; minutes < 24 * 60; minutes += 15) {
      final at = DateTime(2026, 9, 8).add(Duration(minutes: minutes));
      expect(ageInDays(birth, at.toUtc()), ageInDays(birth, at), reason: '$at');
      expect(ageInDays(birth.toUtc(), at.toUtc()), ageInDays(birth, at), reason: '$at');
    }
  });
}
