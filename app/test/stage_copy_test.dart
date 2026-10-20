import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/domain/stages/cry_stage.dart';
import 'package:honghong/features/stage/stage_copy.dart';

/// 是否在说"出牙导致腹泻"。纠正误解的句子（"不是/不会/没有证据"）不算。
bool claimsTeethingCausesDiarrhea(String text) {
  for (final raw in text.split(RegExp(r'[。；;！!？?\n]'))) {
    final s = raw.trim();
    if (!RegExp(r'(出牙|长牙)').hasMatch(s) || !RegExp(r'(腹泻|拉肚子|拉稀)').hasMatch(s)) continue;
    if (RegExp(r'(不是|不会|并不|没有证据|无证据|不能|别把|不要把|不代表)').hasMatch(s)) continue;
    final causal = RegExp(r'(出牙|长牙)[^，,]*?(会|可能|容易|常|就)?(导致|引起|造成|伴有|出现|有)[^，,]*?(腹泻|拉肚子|拉稀)');
    final reverse = RegExp(r'(腹泻|拉肚子|拉稀)[^，,]*?(是|因为|由于)[^，,]*?(出牙|长牙)');
    final easy = RegExp(r'(出牙|长牙)[^，,]*?(容易|会|常)[^，,]*?(腹泻|拉肚子|拉稀)');
    final caused = RegExp(r'(出牙|长牙)[^，,]*?(导致|引起|造成)的(腹泻|拉肚子|拉稀)');
    if (causal.hasMatch(s) || reverse.hasMatch(s) || easy.hasMatch(s) || caused.hasMatch(s)) return true;
  }
  return false;
}

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

  test('统一提示：每个宝宝不一样、不能替代医生；早产提示单列（不做矫正月龄）', () {
    final all = stageCommonNotes.join();
    expect(all, contains('每个宝宝不一样'));
    expect(all, contains('不能替代医生'));
    expect(stagePretermNote, '早产宝宝的时间可能会晚一些，以矫正月龄为准。');
  });

  test('固定急症提示：3 个月以下 ≥38℃ 立即就医，以及其他危险信号', () {
    expect(stageEmergencyLine, startsWith('出现这些情况请立即就医'));
    for (final w in ['3 个月以下宝宝体温 ≥38℃', '呼吸急促或费力', '口唇发紫', '抽搐', '拒奶', '叫不醒']) {
      expect(stageEmergencyLine, contains(w));
    }
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
    for (final w in ['体温 ≥38℃（3 个月以下要立即就医）', '呕吐', '大便带血', '果酱样大便', '呼吸急促', '肚子鼓胀', '精神差', '哭声', '体重不长', '4 个月以后']) {
      expect(doc, contains(w));
    }
  });

  group('出牙和腹泻：可以纠正误解，不能说出牙导致腹泻', () {
    test('规则本身：纠正句通过，因果句不通过', () {
      for (final ok in [
        '腹泻、呕吐、出皮疹——这些也不是出牙引起的，请按生病来对待',
        '腹泻不是出牙引起的',
        '出牙不会导致腹泻',
        '没有证据表明出牙会引起拉肚子',
      ]) {
        expect(claimsTeethingCausesDiarrhea(ok), isFalse, reason: ok);
      }
      for (final bad in [
        '出牙会导致腹泻',
        '出牙可能引起轻微腹泻',
        '长牙时容易拉肚子',
        '出牙期常伴有腹泻',
        '腹泻是出牙引起的',
        '出牙造成的腹泻一般几天就好',
      ]) {
        expect(claimsTeethingCausesDiarrhea(bad), isTrue, reason: bad);
      }
    });

    test('出牙期文案：说明不引起 ≥38℃ 发烧，并说明腹泻也不是出牙引起的', () {
      final c = stageCopy[CryStage.teething]!;
      expect(c.when, contains('6 个月左右'));
      expect(c.when, contains('4–12 个月开始都正常'));
      expect(c.keyFact, allOf(contains('不会引起'), contains('38℃')));
      expect(c.seeDoctor.any((t) => t.contains('腹泻') && t.contains('不是出牙引起的')), isTrue);
      for (final cc in stageCopy.values) {
        for (final t in _texts(cc)) {
          expect(claimsTeethingCausesDiarrhea(t), isFalse, reason: t);
        }
      }
    });
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
