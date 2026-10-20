import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/domain/soothe/wake_window.dart';

class _Sick implements SleepReminderSuppressor {
  _Sick(this.until);
  final DateTime until;
  @override
  bool suppresses(DateTime at) => at.isBefore(until);
}

void main() {
  // 出生 2026-09-08；2026-10-20 是第 42 天（0–3 个月）
  final birth = DateTime(2026, 9, 8);
  final noon = DateTime(2026, 10, 20, 12);

  SleepReminderDecision eval({
    DateTime? now,
    Duration? awake = const Duration(minutes: 62),
    bool sleeping = false,
    DateTime? dismissed,
    Iterable<SleepReminderSuppressor> suppressors = const [],
    DateTime? birthDate,
  }) {
    final n = now ?? noon;
    return evaluateSleepReminder(
      birthDate: birthDate ?? birth,
      now: n,
      lastSleepEnd: awake == null ? null : n.subtract(awake),
      sleeping: sleeping,
      dismissedWakeAt: dismissed,
      suppressors: suppressors,
    );
  }

  group('月龄档（边界和 #30 一致：第 92 / 183 / 366 天）', () {
    test('日龄 → 档', () {
      expect(wakeBandForAgeDays(0), WakeBand.months0to3);
      expect(wakeBandForAgeDays(91), WakeBand.months0to3);
      expect(wakeBandForAgeDays(92), WakeBand.months3to6);
      expect(wakeBandForAgeDays(182), WakeBand.months3to6);
      expect(wakeBandForAgeDays(183), WakeBand.months6to12);
      expect(wakeBandForAgeDays(365), WakeBand.months6to12);
      expect(wakeBandForAgeDays(366), isNull, reason: '满 12 个月不提醒');
      expect(wakeBandForAgeDays(-1), isNull);
    });

    test('范围：0–3 个月 1–1.5 小时，3–6 个月 1.5–3 小时，6–12 个月 2–3 小时（不用 45 分钟）', () {
      expect(wakeWindows[WakeBand.months0to3]!.min, const Duration(hours: 1));
      expect(wakeWindows[WakeBand.months0to3]!.max, const Duration(minutes: 90));
      expect(wakeWindows[WakeBand.months3to6]!.min, const Duration(minutes: 90));
      expect(wakeWindows[WakeBand.months3to6]!.max, const Duration(hours: 3));
      expect(wakeWindows[WakeBand.months6to12]!.min, const Duration(hours: 2));
      expect(wakeWindows[WakeBand.months6to12]!.max, const Duration(hours: 3));
      for (final w in wakeWindows.values) {
        expect(w.min, greaterThanOrEqualTo(const Duration(hours: 1)));
        expect(w.staleAfter, w.max * 2);
      }
    });
  });

  group('清醒时长计算', () {
    test('达到下限才提醒：59 分钟不提醒，60 分钟提醒', () {
      expect(eval(awake: const Duration(minutes: 59)).block, ReminderBlock.tooEarly);
      final d = eval(awake: const Duration(minutes: 60));
      expect(d.show, isTrue);
      expect(d.awake, const Duration(minutes: 60));
      expect(d.band, WakeBand.months0to3);
      expect(d.wakeAt, noon.subtract(const Duration(minutes: 60)));
    });

    test('按月龄换下限：4 个月 90 分钟、8 个月 2 小时', () {
      final fourMonths = DateTime(2026, 6, 15); // 第 127 天
      expect(eval(birthDate: fourMonths, awake: const Duration(minutes: 89)).block, ReminderBlock.tooEarly);
      expect(eval(birthDate: fourMonths, awake: const Duration(minutes: 90)).show, isTrue);
      final eightMonths = DateTime(2026, 2, 20);
      expect(eval(birthDate: eightMonths, awake: const Duration(minutes: 119)).block, ReminderBlock.tooEarly);
      expect(eval(birthDate: eightMonths, awake: const Duration(minutes: 120)).show, isTrue);
    });

    test('清醒时长 = 现在 − 最近一次睡眠的结束时间', () {
      final end = DateTime(2026, 10, 20, 10, 30);
      final d = evaluateSleepReminder(birthDate: birth, now: noon, lastSleepEnd: end, sleeping: false);
      expect(d.awake, const Duration(minutes: 90));
    });

    test('标题里的"约 X"按半小时向下取整', () {
      expect(formatAwakeApprox(const Duration(minutes: 60)), '1 小时');
      expect(formatAwakeApprox(const Duration(minutes: 89)), '1 小时');
      expect(formatAwakeApprox(const Duration(minutes: 90)), '1.5 小时');
      expect(formatAwakeApprox(const Duration(minutes: 125)), '2 小时');
      expect(formatAwakeApprox(const Duration(minutes: 150)), '2.5 小时');
      expect(formatAwakeApprox(const Duration(minutes: 45)), '45 分钟');
    });
  });

  group('不提醒的情况', () {
    test('正在睡觉计时', () {
      expect(eval(sleeping: true).block, ReminderBlock.asleep);
    });

    test('没有睡眠记录', () {
      expect(eval(awake: null).block, ReminderBlock.noSleepRecord);
    });

    test('超过上限 2 倍：0–3 个月 3 小时以上、6–12 个月 6 小时以上', () {
      expect(eval(awake: const Duration(hours: 3)).show, isTrue);
      expect(eval(awake: const Duration(hours: 3, minutes: 1)).block, ReminderBlock.stale);
      final eightMonths = DateTime(2026, 2, 20);
      expect(eval(birthDate: eightMonths, awake: const Duration(hours: 6)).show, isTrue);
      expect(eval(birthDate: eightMonths, awake: const Duration(hours: 6, minutes: 1)).block, ReminderBlock.stale);
    });

    test('21:00–06:00 不提醒（20:59 提醒，21:00 和 05:59 不提醒，06:00 提醒）', () {
      DateTime at(int h, int m) => DateTime(2026, 10, 20, h, m);
      expect(eval(now: at(20, 59)).show, isTrue);
      expect(eval(now: at(21, 0)).block, ReminderBlock.quietHours);
      expect(eval(now: at(23, 30)).block, ReminderBlock.quietHours);
      expect(eval(now: at(0, 0)).block, ReminderBlock.quietHours);
      expect(eval(now: at(5, 59)).block, ReminderBlock.quietHours);
      expect(eval(now: at(6, 0)).show, isTrue);
      expect(inQuietHours(at(21, 0)), isTrue);
      expect(inQuietHours(at(6, 0)), isFalse);
    });

    test('「还不困」：本次醒着期间不再提醒；再睡一觉醒来后照常提醒', () {
      final wake = noon.subtract(const Duration(minutes: 70));
      expect(eval(awake: const Duration(minutes: 70), dismissed: wake).block, ReminderBlock.dismissed);
      expect(
        eval(awake: const Duration(minutes: 80), dismissed: wake).block,
        isNot(ReminderBlock.dismissed),
        reason: '醒来时间变了 = 新的一次醒着',
      );
    });

    test('#28 压制钩子：生病记录期间不提醒，过了照常', () {
      expect(eval(suppressors: [_Sick(noon.add(const Duration(hours: 1)))]).block, ReminderBlock.suppressed);
      expect(eval(suppressors: [_Sick(noon.subtract(const Duration(hours: 1)))]).show, isTrue);
    });

    test('满 12 个月、生日在未来', () {
      expect(eval(birthDate: DateTime(2025, 10, 1)).block, ReminderBlock.outOfAgeRange);
      expect(eval(birthDate: DateTime(2026, 11, 1)).block, ReminderBlock.outOfAgeRange);
    });

    test('正在睡觉优先于其他原因（夜里正在睡也算 asleep）', () {
      expect(eval(now: DateTime(2026, 10, 20, 22), sleeping: true).block, ReminderBlock.asleep);
    });
  });

  group('下一次重新判断的时间', () {
    test('到下限的那一刻', () {
      final end = DateTime(2026, 10, 20, 11, 30);
      expect(nextReminderCheck(now: noon, lastSleepEnd: end, band: WakeBand.months0to3), DateTime(2026, 10, 20, 12, 30));
    });

    test('已经显示时：下一个时间点是超过 2 倍上限', () {
      final end = DateTime(2026, 10, 20, 10, 30);
      expect(nextReminderCheck(now: noon, lastSleepEnd: end, band: WakeBand.months0to3), DateTime(2026, 10, 20, 13, 30, 1));
    });

    test('夜间时段的开始和结束', () {
      expect(nextReminderCheck(now: DateTime(2026, 10, 20, 20), lastSleepEnd: null, band: null), DateTime(2026, 10, 20, 21));
      expect(nextReminderCheck(now: DateTime(2026, 10, 20, 22), lastSleepEnd: null, band: null), DateTime(2026, 10, 21, 6));
      expect(nextReminderCheck(now: DateTime(2026, 10, 21, 2), lastSleepEnd: null, band: null), DateTime(2026, 10, 21, 6));
    });
  });
}
