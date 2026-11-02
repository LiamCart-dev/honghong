// 导出健康记录审核表（阈值 / 急症 / 文案 / 待确认）：
//   cd app && dart run tool/export_health_review.dart > ../docs/health/health-review.md
import 'package:honghong/domain/health/health.dart';
import 'package:honghong/domain/stages/cry_stage.dart' show monthStartDay;

void main() {
  final c = kHealthConfig;
  final b = StringBuffer()
    ..writeln('# 哄哄「健康记录」配置审核表（#1 / PR-A）')
    ..writeln()
    ..writeln('> 由 `app/lib/domain/health/health_config.dart` 导出。改配置请改源文件，不要只改本 md。')
    ..writeln('>')
    ..writeln('> 生成：`cd app && dart run tool/export_health_review.dart > ../docs/health/health-review.md`')
    ..writeln()
    ..writeln('## 发烧阈值与部位')
    ..writeln()
    ..writeln('| 档位 | 阈值（℃） | 对应部位 |')
    ..writeln('|---|---|---|');
  for (final e in c.feverC.entries) {
    final sites = c.siteTier.entries
        .where((x) => x.value == e.key)
        .map((x) => x.key.name)
        .join(', ');
    b.writeln('| ${e.key.name} | ${e.value ?? "（关闭）"} | $sites |');
  }
  b
    ..writeln()
    ..writeln('## 急症 / 建议规则（配置值）')
    ..writeln()
    ..writeln('| 码 | 条件 | 配置 |')
    ..writeln('|---|---|---|')
    ..writeln(
      '| U1 | 未满 ${c.urgentUnderAgeMonths} 个月（日龄 < ${monthStartDay(c.urgentUnderAgeMonths ?? 3)}）+ 窗口内发烧 | urgentUnderAgeMonths=${c.urgentUnderAgeMonths} |',
    )
    ..writeln(
      '| U2 | 满 3 未满 6 个月 + 读数 ≥ ${c.highFeverCUnder6mo}℃ | TODO(#1-review) highFeverCUnder6mo |',
    )
    ..writeln(
      '| U3 | 任何月龄 + 读数 ≥ ${c.anyAgeVeryHighC}℃ | TODO(#1-review) anyAgeVeryHighC |',
    )
    ..writeln(
      '| U4 | 未满 3 个月 + 窗口内**最近一条** < ${c.lowTempCUnder3mo}℃ | lowTempCUnder3mo（设计稿 v3；Issue 仍标 Liam 未表态） |',
    )
    ..writeln('| U5 | 症状窗口内命中急症集合任一 | dangerSymptoms（6） |')
    ..writeln(
      '| U7 | 同一次发烧跨度 ≥ ${c.feverEscalateAfter?.inHours}h | TODO(#1-review) feverEscalateAfter |',
    )
    ..writeln('| A1 | 窗口内发烧 | feverC + feverWindow |')
    ..writeln('| A2 | 窗口内普通症状 | symptomWindow |')
    ..writeln('| A3 | ${c.medicationWindow.inHours}h 内药品（补充剂不算） | medicationWindow |')
    ..writeln()
    ..writeln('## 窗口与横幅')
    ..writeln()
    ..writeln('| 项 | 值 |')
    ..writeln('|---|---|')
    ..writeln('| feverWindow | ${c.feverWindow} |')
    ..writeln('| medicationWindow | ${c.medicationWindow} |')
    ..writeln('| symptomWindow | ${c.symptomWindow} |')
    ..writeln('| feverEpisodeLookback | ${c.feverEpisodeLookback} |')
    ..writeln('| feverEpisodeGap | ${c.feverEpisodeGap} |')
    ..writeln('| homeBannerRetain | ${c.homeBannerRetain} |')
    ..writeln('| homeBannerOnlyUrgent | ${c.homeBannerOnlyUrgent} |')
    ..writeln('| recordableC | ${c.recordableC} |')
    ..writeln('| fahrenheitGuess | ${c.fahrenheitGuess} |')
    ..writeln()
    ..writeln('## 症状清单（${c.symptoms.length}）与急症（${c.dangerSymptoms.length}）')
    ..writeln()
    ..writeln('| 症状 | 急症？ | 文案 |')
    ..writeln('|---|---|---|');
  for (final s in c.symptoms) {
    final danger = c.dangerSymptoms.contains(s) ? '是' : '';
    b.writeln('| ${s.name} | $danger | ${c.copy.symptomLabels[s]} |');
  }
  b
    ..writeln()
    ..writeln('## 横幅 / 面板文案摘要')
    ..writeln()
    ..writeln('- bannerTitleUrgent: ${c.copy.bannerTitleUrgent}')
    ..writeln('- bannerTitleAdvise: ${c.copy.bannerTitleAdvise}')
    ..writeln('- bannerBodyUrgent: ${c.copy.bannerBodyUrgent}')
    ..writeln('- bannerBodyAdvise: ${c.copy.bannerBodyAdvise}')
    ..writeln('- bannerDisclaimer: ${c.copy.bannerDisclaimer}')
    ..writeln('- panelFeverAxillary: ${c.copy.panelFeverAxillary}')
    ..writeln('- panelFeverRectal: ${c.copy.panelFeverRectal}')
    ..writeln('- panelUrgentUnder3mo: ${c.copy.panelUrgentUnder3mo}')
    ..writeln('- panelUrgentHigh39Under6mo: ${c.copy.panelUrgentHigh39Under6mo}')
    ..writeln('- panelUrgentHigh40: ${c.copy.panelUrgentHigh40}')
    ..writeln('- panelLowTempUnder3mo: ${c.copy.panelLowTempUnder3mo}')
    ..writeln('- dangerGroupTitle: ${c.copy.dangerGroupTitle}')
    ..writeln('- stageEmergencyLine: ${c.copy.stageEmergencyLine}')
    ..writeln()
    ..writeln('## 阶段提示复用（HealthStageLegacyCopy，字面冻结至 PR-H）')
    ..writeln()
    ..writeln('| 键 | 文案 |')
    ..writeln('|---|---|')
    ..writeln('| stageEmergencyLine | ${HealthStageLegacyCopy.stageEmergencyLine} |')
    ..writeln('| cryingPeakFeverSeeDoctor | ${HealthStageLegacyCopy.cryingPeakFeverSeeDoctor} |')
    ..writeln('| teethingKeyFact | ${HealthStageLegacyCopy.teethingKeyFact} |')
    ..writeln('| teethingFeverSeeDoctor | ${HealthStageLegacyCopy.teethingFeverSeeDoctor} |')
    ..writeln('| growthSpurtFeverSeeDoctor | ${HealthStageLegacyCopy.growthSpurtFeverSeeDoctor} |')
    ..writeln()
    ..writeln('## 待确认 / pendingReview（ADR-0009：非空则正式渠道隐藏功能）')
    ..writeln();
  for (final n in c.pendingReviewNotes) {
    b.writeln('- $n');
  }
  b
    ..writeln()
    ..writeln('## 渠道门禁')
    ..writeln()
    ..writeln('- 版本名后缀 `-dev` / `-ci`，或 `--dart-define=HH_CHANNEL=dev|ci|stable`')
    ..writeln('- `isHealthFeatureVisible`：有 pending 时仅 dev/ci 可见')
    ..writeln('- 角标文案：`${c.copy.pendingReviewBadge}`')
    ..writeln();
  // ignore: avoid_print
  print(b.toString());
}
