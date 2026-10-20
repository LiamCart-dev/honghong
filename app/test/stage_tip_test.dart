import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/core/prefs.dart';
import 'package:honghong/core/providers.dart';
import 'package:honghong/core/theme/app_theme.dart';
import 'package:honghong/data/db/app_database.dart';
import 'package:honghong/domain/stages/cry_stage.dart';
import 'package:honghong/features/cry/result_page.dart';
import 'package:honghong/features/stage/stage_copy.dart';
import 'package:honghong/features/stage/stage_tip.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

class _Always implements StageTipSuppressor {
  @override
  bool suppresses(DateTime at) => true;
}

AppDatabase? _db;

/// 每个测试结束时调用：先卸载页面（停掉数据库流），再关库
Future<void> _done(WidgetTester tester) async {
  await unmount(tester);
  await tester.runAsync(() => _db!.close());
}

final _pred = jsonEncode({
  'version': 'rule-1',
  'ranked': [
    {'cause': 'hungry', 'p': .5, 'reason': '距上次喂奶 3 小时'},
    {'cause': 'sleepy', 'p': .3, 'reason': '已经醒了 1 小时'},
    {'cause': 'holdMe', 'p': .2, 'reason': '可能只是想被抱'},
  ],
});

/// 宝宝生日 [birth]，哭声发生在 [cryAt]；直接打开结果页
Future<List<Uri>> _pumpResult(
  WidgetTester tester, {
  required DateTime birth,
  required DateTime cryAt,
  bool night = false,
  bool reduceMotion = false,
  bool openOk = true,
  List overrides = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final sp = await SharedPreferences.getInstance();
  final db = AppDatabase.memory();
  _db = db;
  await tester.runAsync(() async {
    await db.into(db.babies).insert(BabiesCompanion.insert(id: 'b1', nickname: '小米粒', birthDate: birth));
    await db
        .into(db.cryEvents)
        .insert(
          CryEventsCompanion.insert(
            id: 'e1',
            babyId: 'b1',
            startedAt: cryAt,
            durationMs: 10000,
            contextJson: '{}',
            predictionJson: _pred,
            predictorVersion: 'rule-1',
          ),
        );
  });
  final opened = <Uri>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        prefsProvider.overrideWithValue(sp),
        databaseProvider.overrideWithValue(db),
        linkOpenerProvider.overrideWithValue((u) async {
          opened.add(u);
          return openOk;
        }),
        ...overrides.cast(),
      ],
      child: MaterialApp(
        theme: night ? AppTheme.night : AppTheme.day,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: const ResultPage(eventId: 'e1'),
      ),
    ),
  );
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await settle(tester);
  return opened;
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('stage-tip')));
  await tester.tap(find.byKey(const Key('stage-tip')));
  await settle(tester, 8);
}

Finder _inSheet(String text) =>
    find.descendant(of: find.byKey(const Key('stage-sheet')), matching: find.textContaining(text, findRichText: true));

Future<void> _scrollTo(WidgetTester tester, Finder f) async {
  await tester.dragUntilVisible(f, find.byKey(const Key('stage-sheet')), const Offset(0, -200), maxIteration: 40);
  await settle(tester, 2);
}

void main() {
  // 第 49 天：只有哭闹高峰期
  final birth = DateTime(2026, 9, 1);
  final day49 = DateTime(2026, 10, 20, 2, 30);

  testWidgets('结果页显示一行「这周宝宝可能在哭闹高峰期」，点开有说明、关键提示、就医信号、统一提示', (tester) async {
    await _pumpResult(tester, birth: birth, cryAt: day49);
    expect(find.text('这周宝宝可能在哭闹高峰期'), findsOneWidget);
    expect(find.text(stageTipSub), findsOneWidget);

    await _openSheet(tester);
    expect(_inSheet('按宝宝出生第 49 天估计'), findsOneWidget);
    expect(find.byKey(const Key('stage-preterm')), findsOneWidget); // 顶部醒目处
    expect(_inSheet(stagePretermNote), findsOneWidget);
    expect(find.byKey(const Key('stage-keyfact-哭闹高峰期')), findsOneWidget);
    expect(_inSheet('绝不能摇晃宝宝'), findsOneWidget);
    await _scrollTo(tester, _inSheet('4 个月以后还是这样哭'));
    await _scrollTo(tester, find.byKey(const Key('stage-emergency')));
    expect(_inSheet('3 个月以下宝宝体温 ≥38℃'), findsOneWidget);
    await _scrollTo(tester, _inSheet('不能替代医生判断'));
    expect(_inSheet('每个宝宝不一样'), findsWidgets);
    expect(_inSheet('不能替代医生判断'), findsOneWidget);
    await _done(tester);
  });

  testWidgets('来源可以点开（交给浏览器）；打不开时提示并复制链接', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    final src = stageCopy[CryStage.cryingPeak]!.sources.first;
    final opened = await _pumpResult(tester, birth: birth, cryAt: day49, openOk: false);
    await _openSheet(tester);
    final link = find.byKey(Key('stage-source-${src.url}'));
    await _scrollTo(tester, link);
    await tester.tap(link);
    await settle(tester);
    expect(opened, [Uri.parse(src.url)]);
    expect(copied, [src.url]);
    expect(find.text('打不开浏览器，链接已复制'), findsOneWidget);
    await _done(tester);
  });

  testWidgets('两个阶段重叠：一行里两个名字，面板里两节都有', (tester) async {
    await _pumpResult(tester, birth: birth, cryAt: DateTime(2026, 9, 25, 20)); // 第 24 天
    expect(find.text('这周宝宝可能在猛长期，也可能在哭闹高峰期'), findsOneWidget);
    await _openSheet(tester);
    expect(_inSheet('部分宝宝可能出现几天的猛吃期'), findsOneWidget);
    // 每个阶段一节末尾都有急症提示
    for (final st in [CryStage.growthSpurt]) {
      await _scrollTo(
        tester,
        find.descendant(
          of: find.byKey(Key('stage-section-${st.name}')),
          matching: find.byKey(const Key('stage-emergency')),
        ),
      );
    }
    await _scrollTo(tester, find.byKey(const Key('stage-keyfact-哭闹高峰期')));
    expect(_inSheet('绝不能摇晃宝宝'), findsOneWidget);
    // 每个阶段一节末尾都有急症提示
    for (final st in [CryStage.cryingPeak]) {
      await _scrollTo(
        tester,
        find.descendant(
          of: find.byKey(Key('stage-section-${st.name}')),
          matching: find.byKey(const Key('stage-emergency')),
        ),
      );
    }
    await _done(tester);
  });

  testWidgets('按哭声那天的日龄算，不按今天（翻看旧记录时也对）', (tester) async {
    // 生日很早，今天早已满 12 个月；但哭声发生在第 200 天
    final old = DateTime(2020, 1, 1);
    await _pumpResult(tester, birth: old, cryAt: old.add(const Duration(days: 200, hours: 12)));
    expect(find.text('这周宝宝可能在出牙期，也可能在睡眠模式变化期'), findsOneWidget);
    await _done(tester);
  });

  testWidgets('没有命中阶段时不显示，也不占位置', (tester) async {
    await _pumpResult(tester, birth: birth, cryAt: DateTime(2026, 9, 4)); // 第 3 天
    expect(find.byKey(const Key('stage-tip')), findsNothing);
    expect(find.textContaining('这周宝宝可能在'), findsNothing);
    expect(find.text('可能的原因'), findsOneWidget); // 结果页本身正常
    await _done(tester);
  });

  testWidgets('压制钩子：以后 #28 的就医横幅出现时不显示阶段提示', (tester) async {
    await _pumpResult(
      tester,
      birth: birth,
      cryAt: day49,
      overrides: [
        stageTipSuppressorsProvider.overrideWithValue([_Always()]),
      ],
    );
    expect(find.byKey(const Key('stage-tip')), findsNothing);
    await _done(tester);
  });

  testWidgets('夜间模式：文字用夜间主题颜色', (tester) async {
    await _pumpResult(tester, birth: birth, cryAt: day49, night: true);
    final hh = AppTheme.night.extension<Hh>()!;
    final t = tester.widget<Text>(find.text('这周宝宝可能在哭闹高峰期'));
    expect(t.style!.color, hh.ink);
    final m = tester.widget<Material>(
      find.ancestor(of: find.byKey(const Key('stage-tip')), matching: find.byType(Material)).first,
    );
    expect(m.color, hh.card);
    await _done(tester);
  });

  testWidgets('读屏：一行提示是按钮，来源是链接', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpResult(tester, birth: birth, cryAt: day49);
    expect(
      tester.getSemantics(find.byKey(const Key('stage-tip'))),
      matchesSemantics(label: '这周宝宝可能在哭闹高峰期。$stageTipSub', isButton: true, hasTapAction: true),
    );
    await _openSheet(tester);
    final src = stageCopy[CryStage.cryingPeak]!.sources.first;
    final link = find.byKey(Key('stage-source-${src.url}'));
    await _scrollTo(tester, link);
    final node = tester.getSemantics(link);
    expect(node.flagsCollection.isLink, isTrue);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(node.label, contains(src.org));
    handle.dispose();
    await _done(tester);
  });

  testWidgets('减少动态效果：说明面板直接出现，没有滑入动画', (tester) async {
    await _pumpResult(tester, birth: birth, cryAt: day49, reduceMotion: true);
    await tester.ensureVisible(find.byKey(const Key('stage-tip')));
    await tester.tap(find.byKey(const Key('stage-tip')));
    await tester.pump();
    final y0 = tester.getTopLeft(find.byKey(const Key('stage-sheet'))).dy;
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getTopLeft(find.byKey(const Key('stage-sheet'))).dy, y0);
    await _done(tester);
  });

  testWidgets('正常动画：说明面板从下往上滑入', (tester) async {
    await _pumpResult(tester, birth: birth, cryAt: day49);
    await tester.ensureVisible(find.byKey(const Key('stage-tip')));
    await tester.tap(find.byKey(const Key('stage-tip')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final y0 = tester.getTopLeft(find.byKey(const Key('stage-sheet'))).dy;
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getTopLeft(find.byKey(const Key('stage-sheet'))).dy, lessThan(y0));
    await _done(tester);
  });
}

