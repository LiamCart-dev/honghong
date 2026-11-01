/// 按月龄的哭声相关阶段（#30）。只放纯逻辑：时间窗口、日龄计算、重叠排序、压制钩子。
/// 给家长看的文案和来源在 `features/stage/stage_copy.dart`，便于单独审阅。
library;

/// 4 个阶段。**声明顺序就是重叠时的显示优先级**（越靠前越优先）：
/// 猛长期窗口最窄、最具体 > 哭闹高峰期 > 出牙期 > 睡眠模式变化。
enum CryStage { growthSpurt, cryingPeak, teething, sleepChange }

/// 日龄闭区间 [fromDay, toDay]。出生当天为第 0 天。
class AgeWindow {
  const AgeWindow(this.fromDay, this.toDay) : assert(fromDay <= toDay);
  final int fromDay;
  final int toDay;
  bool contains(int ageDays) => ageDays >= fromDay && ageDays <= toDay;
  @override
  String toString() => '[$fromDay, $toDay]';
}

/// 满 n 个月的第一天（按平均月长 30.4375 天向上取整）：3→92，4→122，5→153，6→183，12→366。
int monthStartDay(int months) => (months * 30.4375).ceil();

/// 各阶段的日龄窗口（v1 范围，Liam 2026-10-20 确认，见 #30）：
/// - 猛长期：只用 AAP 的两段，7–10 天、3–6 周（21–42 天）；
/// - 哭闹高峰期：约 2 周起（14 天），到 4 个月前（3–4 个月缓解）；
/// - 出牙期：4–12 个月（"约 6 个月起，4–12 个月开始都正常"）；
/// - 睡眠模式变化：3–5 个月（WS/T 579 "从3个月～5个月起睡眠逐渐规律"），以及 6–12 个月（学新本领、分离焦虑）。
/// 满 12 个月后不再提示。
final Map<CryStage, List<AgeWindow>> stageWindows = {
  CryStage.growthSpurt: const [AgeWindow(7, 10), AgeWindow(21, 42)],
  CryStage.cryingPeak: [AgeWindow(14, monthStartDay(4) - 1)],
  CryStage.teething: [AgeWindow(monthStartDay(4), monthStartDay(12) - 1)],
  CryStage.sleepChange: [
    AgeWindow(monthStartDay(3), monthStartDay(5) - 1),
    AgeWindow(monthStartDay(6), monthStartDay(12) - 1),
  ],
};

/// 日龄：按设备本地日历日计算（与时区、夏令时、几点出生无关）。[at] 早于生日时返回 null。
/// 两个参数不管带什么时区（比如云端同步来的 UTC 时间），都先转成本地时间再取年月日（#35）。
int? ageInDays(DateTime birthDate, DateTime at) {
  final bl = birthDate.toLocal();
  final al = at.toLocal();
  final b = DateTime.utc(bl.year, bl.month, bl.day);
  final a = DateTime.utc(al.year, al.month, al.day);
  final d = a.difference(b).inDays;
  return d < 0 ? null : d;
}

/// 命中的阶段，按优先级排序（可能为空）。
List<CryStage> stagesForAge(int ageDays) => [
  for (final s in CryStage.values)
    if (stageWindows[s]!.any((w) => w.contains(ageDays))) s,
];

/// 一次提示：[stages] 非空、按优先级排序；[primary] 是一行提示里第一个名字。
class StageTip {
  const StageTip({required this.ageDays, required this.stages}) : assert(stages.length > 0);
  final int ageDays;
  final List<CryStage> stages;
  CryStage get primary => stages.first;
}

/// 压制钩子：以后 #28 的"可能不舒服，建议就医"横幅出现时，阶段提示不显示，
/// 避免家长把发烧等情况当成"正常阶段"（比如以为发烧是出牙）。
/// 实现这个接口并加进 `stageTipSuppressorsProvider` 即可，结果页不用改。
abstract interface class StageTipSuppressor {
  /// [at]：这次哭声发生的时间。
  bool suppresses(DateTime at);
}

/// 一次哭声对应的阶段提示；没有命中、生日在未来或被压制时返回 null。
StageTip? stageTipFor({
  required DateTime birthDate,
  required DateTime at,
  Iterable<StageTipSuppressor> suppressors = const [],
}) {
  final days = ageInDays(birthDate, at);
  if (days == null) return null;
  final stages = stagesForAge(days);
  if (stages.isEmpty) return null;
  if (suppressors.any((s) => s.suppresses(at))) return null;
  return StageTip(ageDays: days, stages: stages);
}
