import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/domain/soothe/wake_window.dart';
import 'package:honghong/features/soothe/soothe_copy.dart';
import 'package:honghong/features/stage/stage_copy.dart' as stage;

/// 仓库里的审定稿副本（#38 评论 6286515825）
final _reviewed = File('../docs/soothe/soothe-copy-reviewed.md').readAsStringSync();

/// 审定稿里「…」引起来的句子
final _quoted = [for (final m in RegExp(r'「([^」]+)」').allMatches(_reviewed)) m.group(1)!];

void expectVerbatim(String s) {
  expect(_quoted.contains(s) || _quoted.any((q) => q.contains(s)), isTrue, reason: '和审定稿不一致：$s');
}

/// App 里所有给家长看的医学 / 安全文案（不含"上一步"这类按钮字）
List<String> get _allSafetyCopy => [
  reminderBody,
  ...wakeRangeCopy.values,
  totalSleepNote,
  ...playerFixedNotes,
  for (final s in sootheSteps) s.body,
  neverShakeLine,
  overwhelmedLine,
  ...safeSleepLines,
  sickNoSootheLine,
  unusualCryLine,
  disclaimerLine,
];

void main() {
  test('审定稿状态是"育儿指南已审"', () {
    expect(_reviewed, contains('育儿指南已审（2026-10-20），按意见修改后可进开发'));
  });

  test('每一句都和审定稿逐字一致（包括加粗位置）', () {
    expectVerbatim(reminderBody);
    expect(_reviewed, contains('「宝宝醒了约 {X}，可能快困了」'));
    expect(reminderTitle(const Duration(minutes: 62)), '宝宝醒了约 1 小时，可能快困了');
    for (final s in wakeRangeCopy.values) {
      expectVerbatim(s);
    }
    expectVerbatim(totalSleepNote);
    for (final s in playerFixedNotes) {
      expectVerbatim(s);
    }
    for (final s in sootheSteps.take(5)) {
      expectVerbatim(s.body);
    }
    expectVerbatim(neverShakeLine);
    expectVerbatim(overwhelmedLine);
    for (final s in safeSleepLines) {
      expectVerbatim(s);
    }
    expectVerbatim(sickNoSootheLine);
    expectVerbatim(unusualCryLine);
    expectVerbatim(disclaimerLine);
    expect(_reviewed, contains('「$reminderStart」/「$reminderNotSleepy」'));
  });

  test('步骤：6 步，顺序和标题与审定稿一致；第 6 步"放回小床"用 C1 两句', () {
    expect(sootheSteps.map((s) => s.title).toList(), ['调暗灯光、安静下来', '包裹（可选）', '轻轻摇、轻拍', '嘘声 / 白噪音', '吸吮', '放回小床']);
    for (var i = 0; i < 5; i++) {
      expect(_reviewed, contains('${i + 1}. **${sootheSteps[i].title}**'));
    }
    expect(sootheSteps[5].body, safeSleepLines.join('\n'));
    expect(sootheSteps[shakeStepIndex].title, '轻轻摇、轻拍');
  });

  test('急症提示直接复用 #30 的 stageEmergencyLine（一字不差）', () {
    expect(identical(sootheEmergencyLine, stage.stageEmergencyLine), isTrue);
    expect(sootheEmergencyLine, contains('3 个月以下宝宝体温 ≥38℃'));
    expect(_reviewed, contains(sootheEmergencyLine));
  });

  test('必带的安全句都在', () {
    final b1 = playerFixedNotes.map(plainCopy).join();
    for (final w in ['音量开小', '不要开到最大', '至少 2 米', '不要放进小床里', '也不要放在床栏上', '默认 30 分钟', '不能代替大人看护']) {
      expect(b1, contains(w));
    }
    expect(plainCopy(neverShakeLine), startsWith('绝不能摇晃宝宝'));
    expect(plainCopy(overwhelmedLine), contains('先把宝宝仰卧放进安全的小床'));
    expect(plainCopy(overwhelmedLine), contains('10–15 分钟后再回去看看宝宝'));
    final c1 = safeSleepLines.map(plainCopy).join();
    for (final w in ['仰卧', '平整、不倾斜', '不放枕头、被子、毛绒玩具', '倾斜的摇椅', '汽车座椅']) {
      expect(c1, contains(w));
    }
    final swaddle = plainCopy(sootheSteps[1].body);
    for (final w in ['腿和髋部要能自由弯曲、向两边张开', '开始想翻身就停止包裹', '只能仰卧放下', '不要用加重的包巾', '太热了']) {
      expect(swaddle, contains(w));
    }
    expect(plainCopy(sickNoSootheLine), contains('不要用哄睡的办法处理哭闹'));
    expect(disclaimerLine, contains('不能替代医生判断'));
    expect(disclaimerLine, contains('不能代替大人看护'));
  });

  test('只说"可能"、带"每个宝宝不一样"；提醒文案先讲困倦信号', () {
    expect(reminderTitle(const Duration(hours: 1)), contains('可能'));
    expect(reminderBody, startsWith('留意困倦信号'));
    expect(reminderBody, contains('每个宝宝不一样'));
    for (final s in wakeRangeCopy.values) {
      expect(s, contains('可能'));
    }
    expect(wakeRangeCopy.keys.toSet(), WakeBand.values.toSet());
  });

  test('禁用说法：不写分贝数、不写 45 分钟、不写药物、不说"睡眠倒退"', () {
    for (final s in _allSafetyCopy) {
      final t = plainCopy(s);
      expect(t, isNot(matches(RegExp(r'\d+\s*(dB|分贝)', caseSensitive: false))), reason: t);
      expect(t, isNot(contains('45')), reason: t);
      expect(t, isNot(matches(RegExp('(药|退烧|布洛芬|对乙酰氨基酚)'))), reason: t);
      expect(t, isNot(contains('睡眠倒退')), reason: t);
      expect(t, isNot(contains('**')), reason: '加粗标记要成对');
    }
  });

  test('加粗标记成对', () {
    for (final s in _allSafetyCopy) {
      expect('**'.allMatches(s).length.isEven, isTrue, reason: s);
    }
  });
}
