import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/domain/stages/cry_stage.dart';
import 'package:honghong/features/stage/stage_copy.dart';

/// 给家长看的文字（不含来源标题和英文原文引文）
List<String> _texts(StageCopy c) => [
  c.name,
  c.when,
  c.summary,
  ...c.signs,
  ...c.tips,
  if (c.keyFact != null) c.keyFact!,
  ...c.seeDoctor,
];

void main() {
  test('4 个阶段都有文案', () {
    expect(stageCopy.keys.toSet(), CryStage.values.toSet());
  });

  test('一句话说明和一行提示都说"可能"', () {
    for (final c in stageCopy.values) {
      expect(c.summary, contains('可能'), reason: c.name);
    }
    expect(stageTipLine([CryStage.teething]), '这周宝宝可能在出牙期');
    expect(stageTipLine([CryStage.growthSpurt, CryStage.cryingPeak]), '这周宝宝可能在猛长期，也可能在哭闹高峰期');
    expect(stageTipSub, contains('每个宝宝不一样'));
  });

  test('统一提示：每个宝宝不一样、早产按矫正月龄、不能替代医生', () {
    final all = stageCommonNotes.join();
    expect(all, contains('每个宝宝不一样'));
    expect(all, contains('早产宝宝请按矫正月龄理解'));
    expect(all, contains('不能替代医生'));
  });

  test('每个阶段都有就医信号和至少一个 https 来源（含引文、日期）', () {
    for (final c in stageCopy.values) {
      expect(c.seeDoctor, isNotEmpty, reason: c.name);
      expect(c.sources, isNotEmpty, reason: c.name);
      for (final s in c.sources) {
        expect(Uri.parse(s.url).scheme, 'https', reason: s.url);
        expect(Uri.parse(s.url).host, isNotEmpty);
        expect(s.quote, isNotEmpty);
        expect(s.org, isNotEmpty);
        expect(s.date, isNotEmpty);
      }
    }
  });

  test('哭闹高峰期：不说肠绞痛，必须"绝不能摇晃宝宝"，就医信号齐全', () {
    final c = stageCopy[CryStage.cryingPeak]!;
    expect(c.name, '哭闹高峰期');
    for (final t in _texts(c)) {
      expect(t, isNot(contains('绞痛')));
    }
    expect(c.keyFact, contains('绝不能摇晃宝宝'));
    final doc = c.seeDoctor.join();
    for (final w in ['发烧', '呕吐', '血', '精神差', '哭声', '体重不长', '4 个月以后']) {
      expect(doc, contains(w));
    }
  });

  test('出牙期：说明出牙不会引起 ≥38℃ 发烧，不提腹泻', () {
    final c = stageCopy[CryStage.teething]!;
    expect(c.when, '约 6 个月起（4–12 个月开始都正常）');
    expect(c.keyFact, allOf(contains('不会引起'), contains('38℃')));
    for (final t in _texts(c)) {
      expect(t, isNot(contains('腹泻')));
      expect(t, isNot(contains('拉肚子')));
    }
  });

  test('猛长期：只用 7–10 天、3–6 周，不提 3/4/6/9 个月', () {
    final c = stageCopy[CryStage.growthSpurt]!;
    expect(c.when, allOf(contains('7–10 天'), contains('3–6 周')));
    expect(c.summary, contains('部分宝宝可能出现几天的猛吃期'));
    final all = [..._texts(c), for (final s in c.sources) s.quote].join();
    expect(all, isNot(contains('个月')));
    expect(all, isNot(contains('month')));
    final doc = c.seeDoctor.join();
    for (final w in ['尿', '体重不长', '哭闹']) {
      expect(doc, contains(w));
    }
  });

  test('睡眠模式变化期：任何地方都不用"倒退"，引用 WS/T 579', () {
    for (final c in stageCopy.values) {
      for (final t in [..._texts(c), for (final s in c.sources) '${s.title}${s.quote}']) {
        expect(t, isNot(contains('倒退')));
        expect(t.toLowerCase(), isNot(contains('regression')));
      }
    }
    final c = stageCopy[CryStage.sleepChange]!;
    expect(c.sources.any((s) => s.title.contains('WS/T 579')), isTrue);
    expect(c.seeDoctor.join(), contains('WS/T 579'));
  });
}
