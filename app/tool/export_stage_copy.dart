// 把阶段提示文案导出成 markdown 给人审阅：
//   cd app && dart run tool/export_stage_copy.dart > ../stage-copy.md
import 'package:honghong/domain/stages/cry_stage.dart';
import 'package:honghong/features/stage/stage_copy.dart';

void main() {
  final b = StringBuffer()
    ..writeln('# 哄哄「按月龄阶段提示」中文文案（第二稿，已按 2026-10-20 审阅意见修改，#30）')
    ..writeln()
    ..writeln('> 由 `app/lib/features/stage/stage_copy.dart` 导出，请改那个文件，不要改这里。')
    ..writeln()
    ..writeln('## 结果页一行提示')
    ..writeln()
    ..writeln('- 单个阶段：「${stageTipLine([CryStage.cryingPeak])}」')
    ..writeln('- 两个阶段重叠：「${stageTipLine([CryStage.growthSpurt, CryStage.cryingPeak])}」')
    ..writeln('- 小字：「$stageTipSub」')
    ..writeln()
    ..writeln('## 说明面板顶部（醒目）')
    ..writeln()
    ..writeln('> $stagePretermNote')
    ..writeln()
    ..writeln('## 日龄窗口和重叠优先级')
    ..writeln()
    ..writeln('出生当天为第 0 天。重叠时的优先级：猛长期 > 哭闹高峰期 > 出牙期 > 睡眠模式变化期（最多显示两个名字）。')
    ..writeln()
    ..writeln('| 阶段 | 日龄（闭区间） |')
    ..writeln('|---|---|');
  for (final s in CryStage.values) {
    b.writeln('| ${stageCopy[s]!.name} | ${stageWindows[s]!.join('、')} |');
  }
  for (final s in CryStage.values) {
    final c = stageCopy[s]!;
    b
      ..writeln()
      ..writeln('## ${c.name}')
      ..writeln()
      ..writeln('**大致时间**：${c.when}')
      ..writeln()
      ..writeln(c.summary);
    if (c.keyFact != null) {
      b
        ..writeln()
        ..writeln('> ⚠️ **${c.keyFact}**');
    }
    void list(String title, List<String> items) {
      b
        ..writeln()
        ..writeln('**$title**')
        ..writeln();
      for (final i in items) {
        b.writeln('- $i');
      }
    }

    list('可能看到', c.signs);
    list('可以怎么做', c.tips);
    list('出现这些情况请及时就医', c.seeDoctor);
    b
      ..writeln()
      ..writeln('**来源**')
      ..writeln();
    for (final r in c.sources) {
      b.writeln('- ${r.org}：[${r.title}](${r.url})（${r.date}）——「${r.quote}」');
    }
    // 每个阶段一节的末尾：固定急症提示（醒目）
    b
      ..writeln()
      ..writeln('> 🚨 **$stageEmergencyLine**');
  }
  b
    ..writeln()
    ..writeln('## 每个说明面板底部（统一）')
    ..writeln();
  for (final n in stageCommonNotes) {
    b.writeln('- $n');
  }
  // ignore: avoid_print
  print(b.toString());
}
