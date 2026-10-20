/// 按月龄的清醒时长和"提醒哄睡"判断（#38）。纯 Dart，只放逻辑；给家长看的文案在
/// `features/soothe/soothe_copy.dart`。
///
/// 数字来源（育儿指南 2026-10-20 已核对原文，见 #38 审定文案 A2）：
/// Raising Children Network《Tired signs in babies and toddlers》
/// - 0–3 个月：可能醒 1–1.5 小时就困了，有的宝宝能醒 2 小时左右；
/// - 3–6 个月：可能醒 1.5–3 小时会困；
/// - 6–12 个月：可能醒 2–3 小时会困；
/// - 12 个月以上：第一版不提醒。
/// 不用"0–1 个月 45–60 分钟"（育儿指南确认，没有权威来源）。
library;

import '../stages/cry_stage.dart' show ageInDays, monthStartDay;

/// 月龄档。边界和 #30 一致：满 n 个月的第一天 = [monthStartDay]（3 → 第 92 天，6 → 第 183 天，12 → 第 366 天）。
enum WakeBand { months0to3, months3to6, months6to12 }

/// 一档的清醒时长范围。提醒在 [min]（范围下限）出现；超过 [max] 的 2 倍就不再提醒（记录可能不准，不猜）。
class WakeWindow {
  const WakeWindow(this.min, this.max);
  final Duration min;
  final Duration max;

  /// 超过这个时长就不提醒（[max] × 2）
  Duration get staleAfter => max * 2;
}

/// 各档的范围。0–3 个月取"1–1.5 小时"作为范围（"有的宝宝能醒 2 小时左右"只放在文案里），
/// 这样"超过上限 2 倍"= 3 小时，比按 2 小时算更早停止提醒（更保守）。
const Map<WakeBand, WakeWindow> wakeWindows = {
  WakeBand.months0to3: WakeWindow(Duration(minutes: 60), Duration(minutes: 90)),
  WakeBand.months3to6: WakeWindow(Duration(minutes: 90), Duration(minutes: 180)),
  WakeBand.months6to12: WakeWindow(Duration(minutes: 120), Duration(minutes: 180)),
};

/// 日龄所在的档；满 12 个月（第 366 天起）或日龄为负时返回 null。
WakeBand? wakeBandForAgeDays(int ageDays) {
  if (ageDays < 0) return null;
  if (ageDays < monthStartDay(3)) return WakeBand.months0to3;
  if (ageDays < monthStartDay(6)) return WakeBand.months3to6;
  if (ageDays < monthStartDay(12)) return WakeBand.months6to12;
  return null;
}

/// 按生日和当前时间算档（按本地日历日，与 #30 相同）
WakeBand? wakeBandFor(DateTime birthDate, DateTime now) {
  final d = ageInDays(birthDate, now);
  return d == null ? null : wakeBandForAgeDays(d);
}

/// 夜里不提醒的时段：21:00（含）到 06:00（不含），按本地时间（Liam 2026-10-20 确认）
const quietFromHour = 21;
const quietToHour = 6;

bool inQuietHours(DateTime localTime) => localTime.hour >= quietFromHour || localTime.hour < quietToHour;

/// 压制钩子：以后 #28 有"最近发烧 / 用药"等生病记录时，不显示哄睡提醒，
/// 结果页的「开始哄睡」换成就医提示。做法和 #30 的 `StageTipSuppressor` 一样：
/// 实现这个接口，加进 `sleepReminderSuppressorsProvider` 即可。
abstract interface class SleepReminderSuppressor {
  /// [at]：判断的时间（首页提醒 = 现在；结果页 = 这次哭声的时间）
  bool suppresses(DateTime at);
}

/// 不提醒的原因（按判断顺序；方便测试和排查）
enum ReminderBlock {
  /// 满 12 个月或生日在未来
  outOfAgeRange,

  /// 正在睡觉计时
  asleep,

  /// 还没有任何已结束的睡眠记录
  noSleepRecord,

  /// 21:00–06:00
  quietHours,

  /// 本次醒着期间点过「还不困」
  dismissed,

  /// #28 等压制
  suppressed,

  /// 醒着的时间还没到下限
  tooEarly,

  /// 醒着的时间超过上限 2 倍（记录可能不准）
  stale,
}

class SleepReminderDecision {
  const SleepReminderDecision._({this.block, this.awake, this.band, this.wakeAt});

  const SleepReminderDecision.show({required Duration awake, required WakeBand band, required DateTime wakeAt})
    : this._(awake: awake, band: band, wakeAt: wakeAt);

  const SleepReminderDecision.blocked(ReminderBlock block, {Duration? awake, WakeBand? band, DateTime? wakeAt})
    : this._(block: block, awake: awake, band: band, wakeAt: wakeAt);

  /// null = 显示提醒
  final ReminderBlock? block;
  final Duration? awake;
  final WakeBand? band;

  /// 这次醒来的时间（= 最近一次睡眠的结束时间）；「还不困」按它记
  final DateTime? wakeAt;

  bool get show => block == null;

  @override
  String toString() => show ? 'show(awake: $awake, band: $band)' : 'blocked($block)';
}

/// 判断首页要不要出现哄睡提醒卡。
///
/// - [lastSleepEnd]：最近一次已结束睡眠的结束时间（含家人同步来的）；没有就传 null；
/// - [sleeping]：有正在进行的睡觉计时；
/// - [dismissedWakeAt]：点「还不困」时记下的那次醒来时间；和 [lastSleepEnd] 相同说明本次醒着期间已经点过。
SleepReminderDecision evaluateSleepReminder({
  required DateTime birthDate,
  required DateTime now,
  required DateTime? lastSleepEnd,
  required bool sleeping,
  DateTime? dismissedWakeAt,
  Iterable<SleepReminderSuppressor> suppressors = const [],
}) {
  final band = wakeBandFor(birthDate, now);
  if (band == null) return const SleepReminderDecision.blocked(ReminderBlock.outOfAgeRange);
  if (sleeping) return SleepReminderDecision.blocked(ReminderBlock.asleep, band: band);
  if (lastSleepEnd == null) return SleepReminderDecision.blocked(ReminderBlock.noSleepRecord, band: band);
  final awake = now.difference(lastSleepEnd);
  SleepReminderDecision blocked(ReminderBlock b) => SleepReminderDecision.blocked(b, awake: awake, band: band, wakeAt: lastSleepEnd);
  if (inQuietHours(now)) return blocked(ReminderBlock.quietHours);
  if (dismissedWakeAt != null && dismissedWakeAt.isAtSameMomentAs(lastSleepEnd)) return blocked(ReminderBlock.dismissed);
  if (suppressors.any((s) => s.suppresses(now))) return blocked(ReminderBlock.suppressed);
  final w = wakeWindows[band]!;
  if (awake < w.min) return blocked(ReminderBlock.tooEarly);
  if (awake > w.staleAfter) return blocked(ReminderBlock.stale);
  return SleepReminderDecision.show(awake: awake, band: band, wakeAt: lastSleepEnd);
}

/// 下一次需要重新判断的时间（到下限、超过 2 倍上限、进入/离开夜间时段），给界面定时刷新用。
/// 没有需要等待的时间点时返回 null。
DateTime? nextReminderCheck({required DateTime now, required DateTime? lastSleepEnd, required WakeBand? band}) {
  final candidates = <DateTime>[];
  if (lastSleepEnd != null && band != null) {
    final w = wakeWindows[band]!;
    candidates.add(lastSleepEnd.add(w.min));
    candidates.add(lastSleepEnd.add(w.staleAfter).add(const Duration(seconds: 1)));
  }
  final today = DateTime(now.year, now.month, now.day);
  candidates.add(today.add(const Duration(hours: quietToHour)));
  candidates.add(today.add(const Duration(hours: quietFromHour)));
  candidates.add(today.add(const Duration(days: 1, hours: quietToHour)));
  final future = candidates.where((t) => t.isAfter(now)).toList()..sort();
  return future.isEmpty ? null : future.first;
}

/// 标题里的"约 {X}"：按半小时向下取整（不夸大醒着的时间），例如 60–89 分钟 → "1 小时"，90–119 分钟 → "1.5 小时"。
/// 不到 1 小时时按分钟（正常不会出现：最早 60 分钟才提醒）。
String formatAwakeApprox(Duration awake) {
  final m = awake.inMinutes;
  if (m < 60) return '$m 分钟';
  final halves = m ~/ 30; // 2 = 1 小时，3 = 1.5 小时
  return halves.isEven ? '${halves ~/ 2} 小时' : '${halves ~/ 2}.5 小时';
}
