/// #1 健康记录：医疗阈值、窗口、症状/急症清单、文案与阶段提示里复用的急症相关句子。
/// 所有医疗数值和医疗文案只放这里（验收：扫描 lib/ 里 ℃ / 「请尽快就医」等只允许本目录）。
///
/// TODO(#1-review)：标了「保守取舍」的 U2/U3/U7 公开发布前请儿科医生确认（ADR-0006）。
/// TODO(#1)：Issue 正文仍把 U4（＜36℃）列为「Liam 未明确表态」；本 PR 按设计稿 v3 / 审核表实现，
/// 若 Liam 否决可改配置关闭（`lowTempCUnder3mo` 置 null）。
library;

import 'package:honghong/domain/health/health_models.dart';
import 'package:honghong/domain/stages/cry_stage.dart' show monthStartDay;

/// 阶段提示（stage_copy）里与发烧/急症相关、**显示文字一个字不改**的句子；集中到此便于 PR-H 统一改。
/// PR-A 只迁引用，不改口径；PR-H 再按最终阈值改文案。
abstract final class HealthStageLegacyCopy {
  /// 每个阶段说明末尾固定急症提示（审阅第 1 条 / 审核 5.16）。
  static const stageEmergencyLine =
      '出现这些情况请立即就医：3 个月以下宝宝体温 ≥38℃；呼吸急促或费力、口唇发紫；抽搐；拒奶或吃奶明显变差；精神很差、叫不醒。';

  /// 哭闹高峰期 · 就医信号（审 7）
  static const cryingPeakFeverSeeDoctor = '体温 ≥38℃（3 个月以下要立即就医）';

  /// 出牙期 · 关键事实
  static const teethingKeyFact = '出牙不会引起 38℃ 及以上的发烧。体温 ≥38℃ 时不要当成出牙，请及时就医。';

  /// 出牙期 · 就医信号
  static const teethingFeverSeeDoctor = '体温 ≥38℃';

  /// 猛长期 · 就医信号（审 5）
  static const growthSpurtFeverSeeDoctor = '体温 ≥38℃，或者吃奶无力、精神差';
}

/// 界面与横幅用文案（审核第 5 节）。仍可含待 UI 接线的句子。
class HealthCopy {
  const HealthCopy({
    required this.bannerTitleUrgent,
    required this.bannerTitleAdvise,
    required this.bannerBodyUrgent,
    required this.bannerBodyAdvise,
    required this.bannerDisclaimer,
    required this.panelFeverAxillary,
    required this.panelFeverRectal,
    required this.panelUrgentUnder3mo,
    required this.panelUrgentHigh39Under6mo,
    required this.panelUrgentHigh40,
    required this.panelLowTempUnder3mo,
    required this.panelLowTempHint,
    required this.siteHint,
    required this.recordableOutOfRange,
    required this.fahrenheitGuessHint,
    required this.medSubtitle,
    required this.medDoseHint,
    required this.medSupplementHint,
    required this.emptyHealthRecords,
    required this.dangerGroupTitle,
    required this.dangerGroupSubtitle,
    required this.pendingReviewBadge,
    required this.stageEmergencyLine,
    required this.symptomLabels,
    required this.predictorWhyFeverAndMed,
    required this.predictorWhyFever,
    required this.predictorWhyMed,
  });

  final String bannerTitleUrgent;
  final String bannerTitleAdvise;
  final String bannerBodyUrgent;
  final String bannerBodyAdvise;
  final String bannerDisclaimer;
  final String panelFeverAxillary;
  final String panelFeverRectal;
  final String panelUrgentUnder3mo;
  final String panelUrgentHigh39Under6mo;
  final String panelUrgentHigh40;
  final String panelLowTempUnder3mo;
  final String panelLowTempHint;
  final String siteHint;
  final String recordableOutOfRange;
  final String fahrenheitGuessHint;
  final String medSubtitle;
  final String medDoseHint;
  final String medSupplementHint;
  final String emptyHealthRecords;
  final String dangerGroupTitle;
  final String dangerGroupSubtitle;
  final String pendingReviewBadge;
  final String stageEmergencyLine;
  final Map<Symptom, String> symptomLabels;

  /// rule-2「为什么这么猜」：近期发烧 + 用药（审核 5.19）。
  final String predictorWhyFeverAndMed;

  /// rule-2：仅近期发烧。
  final String predictorWhyFever;

  /// rule-2：仅近期用药（不含补充剂）。
  final String predictorWhyMed;

  /// 按实际命中组合选「为什么这么猜」文案。
  String predictorWhy({required bool fever, required bool med}) {
    if (fever && med) return predictorWhyFeverAndMed;
    if (fever) return predictorWhyFever;
    return predictorWhyMed;
  }
}

/// 健康记录集中配置。测试可注入假配置（阈值用变量 t，测 t−0.1 / t）。
class HealthConfig {
  const HealthConfig({
    required this.feverC,
    required this.siteTier,
    required this.urgentUnderAgeMonths,
    required this.highFeverCUnder6mo,
    required this.anyAgeVeryHighC,
    required this.lowTempCUnder3mo,
    required this.feverWindow,
    required this.medicationWindow,
    required this.symptomWindow,
    required this.feverEpisodeLookback,
    required this.feverEpisodeGap,
    required this.feverEscalateAfter,
    required this.homeBannerRetain,
    required this.homeBannerOnlyUrgent,
    required this.recordableC,
    required this.fahrenheitGuess,
    required this.symptoms,
    required this.dangerSymptoms,
    required this.copy,
    required this.pendingReviewNotes,
    this.uncomfortableBoost = 1.2,
    this.otherDampWhenUncomfortable = 0.85,
  });

  /// 发烧阈值（℃）。null = 该档规则不触发。
  final Map<FeverTier, double?> feverC;

  /// 部位 → 档位。未映射的部位不参与发烧判断。
  final Map<TempSite, FeverTier?> siteTier;

  /// 未满该月龄 + 发烧 → U1「请尽快就医」。null = 不启用。
  final int? urgentUnderAgeMonths;

  /// TODO(#1-review) U2：满 3 未满 6 个月，读数 ≥ 此值 → 请尽快（保守取舍）。
  final double? highFeverCUnder6mo;

  /// TODO(#1-review) U3：任何月龄，读数 ≥ 此值 → 请尽快（保守取舍）。
  final double? anyAgeVeryHighC;

  /// U4：未满 3 个月，窗口内**最近一条**读数 < 此值 → 请尽快。null = 关闭。
  final double? lowTempCUnder3mo;

  final Duration? feverWindow;
  final Duration medicationWindow;
  final Duration? symptomWindow;

  /// 计算同一次发烧最长回看（审核：7 天）。
  final Duration feverEpisodeLookback;

  /// 相邻发烧读数间隔 ≤ 此值算同一次。
  final Duration feverEpisodeGap;

  /// TODO(#1-review) U7：同一次发烧持续 ≥ 此值升级请尽快（保守取舍）。
  final Duration? feverEscalateAfter;

  /// 首页「请尽快就医」横幅保留时长（ADR-0008）；UI 在后续 PR。
  final Duration homeBannerRetain;

  /// 首页横幅只在 urgent 时显示（Liam 2026-10-20）。
  final bool homeBannerOnlyUrgent;

  final ({double lo, double hi})? recordableC;
  final ({double lo, double hi})? fahrenheitGuess;

  /// 症状面板顺序（11 项）。
  final List<Symptom> symptoms;

  /// 选中即 U5 / 急症框。
  final Set<Symptom> dangerSymptoms;

  final HealthCopy copy;

  /// 仍待确认/占位说明；非空时正式渠道隐藏功能（ADR-0009）。
  final List<String> pendingReviewNotes;

  /// rule-2：命中近期发烧/用药时给「不舒服」(CryCause.diaper) 的原始分加值。
  final double uncomfortableBoost;

  /// rule-2：命中时其他原因的原始分乘数（温和压低；1 = 不压）。
  final double otherDampWhenUncomfortable;

  List<String> get pendingReview => List.unmodifiable(pendingReviewNotes);

  bool get hasPendingReview => pendingReviewNotes.isNotEmpty;

  /// 日龄是否未满 [months] 个自然月（与 [monthStartDay] 一致）。
  bool underAgeMonths(int ageDays, int months) => ageDays < monthStartDay(months);

  bool atLeastAgeMonths(int ageDays, int months) => ageDays >= monthStartDay(months);

  FeverTier? tierFor(TempSite site) => siteTier[site];

  /// 该读数是否达到对应部位的发烧阈值；阈值为 null 时不触发。
  bool isFeverReading(TempReading r) {
    final tier = tierFor(r.site);
    if (tier == null) return false;
    final t = feverC[tier];
    if (t == null) return false;
    return r.celsius >= t;
  }
}

/// 审核已定 + 设计稿 v3 现行默认配置。
const kHealthConfig = HealthConfig(
  feverC: {
    FeverTier.axillary: 37.5,
    FeverTier.rectal: 38.0,
  },
  siteTier: {
    TempSite.armpit: FeverTier.axillary,
    TempSite.rectal: FeverTier.rectal,
  },
  urgentUnderAgeMonths: 3,
  // TODO(#1-review) 保守取舍，待儿科确认
  highFeverCUnder6mo: 39.0,
  // TODO(#1-review) 保守取舍，待儿科确认
  anyAgeVeryHighC: 40.0,
  lowTempCUnder3mo: 36.0,
  feverWindow: Duration(hours: 24),
  medicationWindow: Duration(hours: 24),
  symptomWindow: Duration(hours: 24),
  feverEpisodeLookback: Duration(days: 7),
  feverEpisodeGap: Duration(hours: 24),
  // TODO(#1-review) 保守取舍，待儿科确认
  feverEscalateAfter: Duration(hours: 72),
  homeBannerRetain: Duration(hours: 24),
  homeBannerOnlyUrgent: true,
  recordableC: (lo: 34.0, hi: 42.5),
  fahrenheitGuess: (lo: 93.0, hi: 108.5),
  symptoms: [ // 设计稿 12 项（含「其他」）；计划文案「11」未计其他
    // 普通组
    Symptom.cough,
    Symptom.runnyNose,
    Symptom.vomit,
    Symptom.diarrhea,
    Symptom.rash,
    Symptom.other,
    // 急症组（审核措辞）
    Symptom.breathingHard,
    Symptom.lowEnergy,
    Symptom.poorFeeding,
    Symptom.seizure,
    Symptom.nonBlanchingRash,
    Symptom.biliousOrBloodyVomit,
  ],
  dangerSymptoms: {
    Symptom.breathingHard,
    Symptom.lowEnergy,
    Symptom.poorFeeding,
    Symptom.seizure,
    Symptom.nonBlanchingRash,
    Symptom.biliousOrBloodyVomit,
  },
  copy: HealthCopy(
    bannerTitleUrgent: '请尽快就医',
    bannerTitleAdvise: '可能不舒服，建议就医',
    bannerBodyUrgent:
        '请现在就带宝宝去医院，不用等哭声分析的结果。路上可以打开「健康记录」给医生看。',
    bannerBodyAdvise:
        '宝宝可能不舒服，建议带宝宝去看医生，把这里记的体温、用药和症状给医生看。如果宝宝情况变差，请立即就医。',
    bannerDisclaimer: '这是根据你记的体温、用药和症状给的提示，不是诊断。拿不准时，以医生的判断为准。',
    panelFeverAxillary: '腋温 37.5℃ 及以上，宝宝可能在发烧。建议带宝宝去看医生。',
    panelFeverRectal: '肛温 38℃ 及以上，宝宝可能在发烧。建议带宝宝去看医生。',
    panelUrgentUnder3mo: '宝宝不到 3 个月，可能在发烧。这么小的宝宝发烧，请现在就带去医院，不要在家观察。',
    panelUrgentHigh39Under6mo: '宝宝不到 6 个月，体温 39℃ 及以上。请尽快带宝宝去医院。',
    panelUrgentHigh40: '体温 40℃ 及以上。请尽快带宝宝去医院。',
    panelLowTempUnder3mo:
        '体温低于 36℃。小宝宝体温偏低也要当心：先给宝宝保暖，过一会儿再量一次；还是低于 36℃，请尽快带去医院。',
    panelLowTempHint: '读数偏低，可能没量准。请过一会儿再量一次。',
    siteHint: '腋温和肛温的发烧标准不一样，请选这次量的部位。',
    recordableOutOfRange: '超出可记录范围（34.0–42.5℃），请再量一次或检查读数',
    fahrenheitGuessHint: '看起来像华氏度（℉）。换算后约 37.0℃。',
    medSubtitle: '只做记录，不给用药建议',
    medDoseHint: '填这次实际给的量，可以不填，最多 20 字',
    medSupplementHint:
        '维生素 D 这类每天吃的补充剂选「补充剂」，不会触发就医提示。治病用的药（包括中成药）请选「药品」。',
    emptyHealthRecords:
        '宝宝发烧、用药或不舒服时，在首页点「体温」「用药」「症状」记一笔；忘了当时记，可以把时间改成当时。',
    dangerGroupTitle: '这些情况要马上去医院',
    dangerGroupSubtitle: '选了任意一项，会马上提示就医',
    pendingReviewBadge: '文案待审核',
    stageEmergencyLine: HealthStageLegacyCopy.stageEmergencyLine,
    symptomLabels: {
      Symptom.cough: '咳嗽',
      Symptom.runnyNose: '流鼻涕',
      Symptom.vomit: '呕吐',
      Symptom.diarrhea: '腹泻',
      Symptom.rash: '皮疹',
      Symptom.other: '其他',
      Symptom.breathingHard: '呼吸急、费力，或嘴唇发紫',
      Symptom.lowEnergy: '精神很差、叫不醒',
      Symptom.poorFeeding: '拒奶或吃奶明显变少',
      Symptom.seizure: '抽搐',
      Symptom.nonBlanchingRash: '皮疹按压不褪色',
      Symptom.biliousOrBloodyVomit: '吐绿色或带血，或吃什么吐什么',
    },
    predictorWhyFeverAndMed: '最近记录了体温和用药，结合宝宝以往的反馈综合判断。',
    predictorWhyFever: '最近记录了体温，结合宝宝以往的反馈综合判断。',
    predictorWhyMed: '最近记录了用药，结合宝宝以往的反馈综合判断。',
  ),
  pendingReviewNotes: [
    // 有值但公开发布前要儿科确认 → 正式渠道仍隐藏功能（ADR-0009）
    'U2 满 3 未满 6 个月 ≥39℃（保守取舍，待儿科确认）TODO(#1-review)',
    'U3 任何月龄 ≥40℃（保守取舍，待儿科确认）TODO(#1-review)',
    'U7 同一次发烧 ≥72 小时升级（保守取舍，待儿科确认）TODO(#1-review)',
    'U4 未满 3 个月最近读数 <36℃：按设计稿 v3/审核实现，Issue #1 仍标「Liam 未明确表态」TODO(#1)',
  ],
);
