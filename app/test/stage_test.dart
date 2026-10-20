import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/domain/stages/cry_stage.dart';

class _Fixed implements StageTipSuppressor {
  _Fixed(this.on);
  final bool on;
  final seen = <DateTime>[];
  @override
  bool suppresses(DateTime at) {
    seen.add(at);
    return on;
  }
}

void main() {
  group('日龄', () {
    test('出生当天是第 0 天，按日历日算，与几点无关', () {
      final birth = DateTime(2026, 9, 1, 23, 50);
      expect(ageInDays(birth, DateTime(2026, 9, 1, 23, 59)), 0);
      expect(ageInDays(birth, DateTime(2026, 9, 2, 0, 1)), 1);
      expect(ageInDays(birth, DateTime(2026, 9, 8, 12)), 7);
    });
    test('跨月、跨年、闰年', () {
      expect(ageInDays(DateTime(2027, 12, 31), DateTime(2028, 1, 1)), 1);
      expect(ageInDays(DateTime(2028, 2, 28), DateTime(2028, 3, 1)), 2); // 2028 是闰年
      expect(ageInDays(DateTime(2026, 10, 20), DateTime(2027, 10, 20)), 365);
    });
    test('生日在未来返回 null', () {
      expect(ageInDays(DateTime(2026, 10, 21), DateTime(2026, 10, 20, 23)), isNull);
    });
    test('满月第一天', () {
      expect([3, 4, 5, 6, 12].map(monthStartDay), [92, 122, 153, 183, 366]);
    });
  });

  group('各阶段窗口边界', () {
    void expectWindow(CryStage s, List<(int, bool)> cases) {
      for (final (d, inside) in cases) {
        expect(stagesForAge(d).contains(s), inside, reason: '$s 第 $d 天');
      }
    }

    test('猛长期：只有 7–10 天、21–42 天', () {
      expectWindow(CryStage.growthSpurt, [
        (6, false), (7, true), (10, true), (11, false),
        (20, false), (21, true), (42, true), (43, false),
        (92, false), (183, false), (275, false), // 不提 3/6/9 个月
      ]);
    });
    test('哭闹高峰期：14 天到 4 个月前', () {
      expectWindow(CryStage.cryingPeak, [(13, false), (14, true), (49, true), (121, true), (122, false)]);
    });
    test('出牙期：4–12 个月', () {
      expectWindow(CryStage.teething, [(121, false), (122, true), (183, true), (365, true), (366, false)]);
    });
    test('睡眠模式变化期：3–5 个月、6–12 个月，中间 5–6 个月不提示', () {
      expectWindow(CryStage.sleepChange, [
        (91, false),
        (92, true),
        (152, true),
        (153, false),
        (182, false),
        (183, true),
        (365, true),
        (366, false),
      ]);
    });
    test('0–6 天、11–13 天、满 12 个月后都没有提示', () {
      for (final d in [0, 6, 11, 13, 366, 500]) {
        expect(stagesForAge(d), isEmpty, reason: '第 $d 天');
      }
    });
  });

  group('重叠时的优先级', () {
    test('猛长期 > 哭闹高峰期', () {
      expect(stagesForAge(21), [CryStage.growthSpurt, CryStage.cryingPeak]);
      expect(stagesForAge(42), [CryStage.growthSpurt, CryStage.cryingPeak]);
      expect(stagesForAge(43), [CryStage.cryingPeak]);
    });
    test('哭闹高峰期 > 睡眠模式变化期', () {
      expect(stagesForAge(100), [CryStage.cryingPeak, CryStage.sleepChange]);
    });
    test('出牙期 > 睡眠模式变化期', () {
      expect(stagesForAge(130), [CryStage.teething, CryStage.sleepChange]);
      expect(stagesForAge(200), [CryStage.teething, CryStage.sleepChange]);
      expect(stagesForAge(160), [CryStage.teething]);
    });
    test('任何一天最多同时命中两个阶段', () {
      for (var d = 0; d <= 400; d++) {
        expect(stagesForAge(d).length, lessThanOrEqualTo(2), reason: '第 $d 天');
      }
    });
    test('StageTip.primary 是优先级最高的', () {
      final t = stageTipFor(birthDate: DateTime(2026, 9, 1), at: DateTime(2026, 9, 25))!;
      expect(t.ageDays, 24);
      expect(t.primary, CryStage.growthSpurt);
      expect(t.stages, [CryStage.growthSpurt, CryStage.cryingPeak]);
    });
  });

  group('压制钩子（给 #28 就医横幅用）', () {
    final birth = DateTime(2026, 9, 1);
    final at = DateTime(2026, 10, 20, 3); // 第 49 天：只命中哭闹高峰期
    test('没有压制时正常给提示', () {
      expect(stageTipFor(birthDate: birth, at: at)?.primary, CryStage.cryingPeak);
      expect(stageTipFor(birthDate: birth, at: at, suppressors: [_Fixed(false)]), isNotNull);
    });
    test('任一压制器返回 true 就不显示，并把哭声时间传给它', () {
      final s = _Fixed(true);
      expect(stageTipFor(birthDate: birth, at: at, suppressors: [_Fixed(false), s]), isNull);
      expect(s.seen, [at]);
    });
    test('没命中阶段时不必调用压制器', () {
      final s = _Fixed(true);
      expect(stageTipFor(birthDate: birth, at: DateTime(2026, 9, 3), suppressors: [s]), isNull);
      expect(s.seen, isEmpty);
    });
    test('生日在未来时没有提示', () {
      expect(stageTipFor(birthDate: DateTime(2027, 1, 1), at: at), isNull);
    });
  });
}
