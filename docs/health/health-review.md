Running build hooks...Running build hooks...# 哄哄「健康记录」配置审核表（#1 / PR-A）

> 由 `app/lib/domain/health/health_config.dart` 导出。改配置请改源文件，不要只改本 md。
>
> 生成：`cd app && dart run tool/export_health_review.dart > ../docs/health/health-review.md`

## 发烧阈值与部位

| 档位 | 阈值（℃） | 对应部位 |
|---|---|---|
| axillary | 37.5 | armpit |
| rectal | 38.0 | rectal |

## 急症 / 建议规则（配置值）

| 码 | 条件 | 配置 |
|---|---|---|
| U1 | 未满 3 个月（日龄 < 92）+ 窗口内发烧 | urgentUnderAgeMonths=3 |
| U2 | 满 3 未满 6 个月 + 读数 ≥ 39.0℃ | TODO(#1-review) highFeverCUnder6mo |
| U3 | 任何月龄 + 读数 ≥ 40.0℃ | TODO(#1-review) anyAgeVeryHighC |
| U4 | 未满 3 个月 + 窗口内**最近一条** < 36.0℃ | lowTempCUnder3mo（设计稿 v3；Issue 仍标 Liam 未表态） |
| U5 | 症状窗口内命中急症集合任一 | dangerSymptoms（6） |
| U7 | 同一次发烧跨度 ≥ 72h | TODO(#1-review) feverEscalateAfter |
| A1 | 窗口内发烧 | feverC + feverWindow |
| A2 | 窗口内普通症状 | symptomWindow |
| A3 | 24h 内药品（补充剂不算） | medicationWindow |

## 窗口与横幅

| 项 | 值 |
|---|---|
| feverWindow | 24:00:00.000000 |
| medicationWindow | 24:00:00.000000 |
| symptomWindow | 24:00:00.000000 |
| feverEpisodeLookback | 168:00:00.000000 |
| feverEpisodeGap | 24:00:00.000000 |
| homeBannerRetain | 24:00:00.000000 |
| homeBannerOnlyUrgent | true |
| recordableC | (hi: 42.5, lo: 34.0) |
| fahrenheitGuess | (hi: 108.5, lo: 93.0) |

## 症状清单（12）与急症（6）

| 症状 | 急症？ | 文案 |
|---|---|---|
| cough |  | 咳嗽 |
| runnyNose |  | 流鼻涕 |
| vomit |  | 呕吐 |
| diarrhea |  | 腹泻 |
| rash |  | 皮疹 |
| other |  | 其他 |
| breathingHard | 是 | 呼吸急、费力，或嘴唇发紫 |
| lowEnergy | 是 | 精神很差、叫不醒 |
| poorFeeding | 是 | 拒奶或吃奶明显变少 |
| seizure | 是 | 抽搐 |
| nonBlanchingRash | 是 | 皮疹按压不褪色 |
| biliousOrBloodyVomit | 是 | 吐绿色或带血，或吃什么吐什么 |

## 横幅 / 面板文案摘要

- bannerTitleUrgent: 请尽快就医
- bannerTitleAdvise: 可能不舒服，建议就医
- bannerBodyUrgent: 请现在就带宝宝去医院，不用等哭声分析的结果。路上可以打开「健康记录」给医生看。
- bannerBodyAdvise: 宝宝可能不舒服，建议带宝宝去看医生，把这里记的体温、用药和症状给医生看。如果宝宝情况变差，请立即就医。
- bannerDisclaimer: 这是根据你记的体温、用药和症状给的提示，不是诊断。拿不准时，以医生的判断为准。
- panelFeverAxillary: 腋温 37.5℃ 及以上，宝宝可能在发烧。建议带宝宝去看医生。
- panelFeverRectal: 肛温 38℃ 及以上，宝宝可能在发烧。建议带宝宝去看医生。
- panelUrgentUnder3mo: 宝宝不到 3 个月，可能在发烧。这么小的宝宝发烧，请现在就带去医院，不要在家观察。
- panelUrgentHigh39Under6mo: 宝宝不到 6 个月，体温 39℃ 及以上。请尽快带宝宝去医院。
- panelUrgentHigh40: 体温 40℃ 及以上。请尽快带宝宝去医院。
- panelLowTempUnder3mo: 体温低于 36℃。小宝宝体温偏低也要当心：先给宝宝保暖，过一会儿再量一次；还是低于 36℃，请尽快带去医院。
- dangerGroupTitle: 这些情况要马上去医院
- stageEmergencyLine: 出现这些情况请立即就医：3 个月以下宝宝体温 ≥38℃；呼吸急促或费力、口唇发紫；抽搐；拒奶或吃奶明显变差；精神很差、叫不醒。

## 阶段提示复用（HealthStageLegacyCopy，字面冻结至 PR-H）

| 键 | 文案 |
|---|---|
| stageEmergencyLine | 出现这些情况请立即就医：3 个月以下宝宝体温 ≥38℃；呼吸急促或费力、口唇发紫；抽搐；拒奶或吃奶明显变差；精神很差、叫不醒。 |
| cryingPeakFeverSeeDoctor | 体温 ≥38℃（3 个月以下要立即就医） |
| teethingKeyFact | 出牙不会引起 38℃ 及以上的发烧。体温 ≥38℃ 时不要当成出牙，请及时就医。 |
| teethingFeverSeeDoctor | 体温 ≥38℃ |
| growthSpurtFeverSeeDoctor | 体温 ≥38℃，或者吃奶无力、精神差 |

## 待确认 / pendingReview（ADR-0009：非空则正式渠道隐藏功能）

- U2 满 3 未满 6 个月 ≥39℃（保守取舍，待儿科确认）TODO(#1-review)
- U3 任何月龄 ≥40℃（保守取舍，待儿科确认）TODO(#1-review)
- U7 同一次发烧 ≥72 小时升级（保守取舍，待儿科确认）TODO(#1-review)
- U4 未满 3 个月最近读数 <36℃：按设计稿 v3/审核实现，Issue #1 仍标「Liam 未明确表态」TODO(#1)

## 渠道门禁

- 版本名后缀 `-dev` / `-ci`，或 `--dart-define=HH_CHANNEL=dev|ci|stable`
- `isHealthFeatureVisible`：有 pending 时仅 dev/ci 可见
- 角标文案：`文案待审核`


