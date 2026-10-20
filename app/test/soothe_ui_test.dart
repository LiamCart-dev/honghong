import 'dart:convert';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:honghong/core/prefs.dart';
import 'package:honghong/core/router/app_router.dart';
import 'package:honghong/core/theme/app_theme.dart';
import 'package:honghong/domain/stages/cry_stage.dart';
import 'package:honghong/data/db/app_database.dart';
import 'package:honghong/data/repositories/care_log_repository.dart';
import 'package:honghong/domain/models/care_log_type.dart';
import 'package:honghong/domain/soothe/wake_window.dart';
import 'package:honghong/features/soothe/sleep_reminder.dart';
import 'package:honghong/features/soothe/soothe_copy.dart';
import 'package:honghong/features/soothe/soothe_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

class _Sick implements SleepReminderSuppressor {
  @override
  bool suppresses(DateTime at) => true;
}

/// 2026-10-20 12:00（星期二中午）
final noon = DateTime(2026, 10, 20, 12);

/// 第 42 天（0–3 个月；猛长期 21–42 天 + 哭闹高峰期）
final birth42 = DateTime(2026, 9, 8);

void _phone(WidgetTester tester, {double textScale = 1}) {
  tester.view.physicalSize = const Size(390, 844) * 3;
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// 启动整个 App：时间固定在 [now]，宝宝生日 [birth]，最近一次睡眠在 [awake] 前结束（null = 没有睡眠记录），
/// [sleeping] = 另有一条正在进行的睡觉计时。
Future<AppDatabase> _pump(
  WidgetTester tester, {
  DateTime? now,
  DateTime? birth,
  Duration? awake = const Duration(minutes: 62),
  bool sleeping = false,
  Map<String, Object> prefs = const {sootheSafetySeenKey: true},
  List overrides = const [],
  double textScale = 1,
}) async {
  _phone(tester, textScale: textScale);
  final t = now ?? noon;
  fixClock(tester, t);
  return pumpApp(
    tester,
    prefs: prefs,
    overrides: overrides,
    seed: (db) async {
      await db.into(db.babies).insert(BabiesCompanion.insert(id: 'b1', nickname: '小米粒', birthDate: birth ?? birth42));
      if (awake != null) {
        final end = t.subtract(awake);
        await db
            .into(db.careLogs)
            .insert(CareLogsCompanion.insert(id: 's1', babyId: 'b1', type: 'sleep', startedAt: end.subtract(const Duration(hours: 1)), endedAt: Value(end)));
      }
      if (sleeping) {
        await db.into(db.careLogs).insert(CareLogsCompanion.insert(id: 's2', babyId: 'b1', type: 'sleep', startedAt: t.subtract(const Duration(minutes: 5))));
      }
    },
  );
}

Future<void> _done(WidgetTester tester, AppDatabase db) async {
  await unmount(tester);
  await tester.runAsync(db.close);
}

GoRouter _router(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(Scaffold).first)).read(routerProvider);

/// 打开页面。用 go（不保留首页）：首页时间线在大字体下原本就有溢出（master 上已有，不属于 #38），避免干扰这里的检查
Future<void> _open(WidgetTester tester, String path) async {
  tester.takeException();
  _router(tester).go(path);
  await settle(tester, 10);
}

Finder get _card => find.byKey(const Key('sleep-reminder-card'));

/// [item] 的下边缘离底部固定区 [bar] 的上边缘至少 16dp
void _expectClearOfBar(WidgetTester tester, Finder item, Finder bar) {
  final itemBottom = tester.getRect(item).bottom;
  final barTop = tester.getRect(bar).top;
  expect(barTop - itemBottom, greaterThanOrEqualTo(16 - .01), reason: '内容底 $itemBottom，固定区顶 $barTop');
}

Future<void> _scrollToEnd(WidgetTester tester, Finder scroll) async {
  for (var i = 0; i < 40; i++) {
    await tester.drag(scroll, const Offset(0, -400));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await settle(tester, 4);
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('首页提醒卡', () {
    testWidgets('醒了 62 分钟：内嵌在状态条下方，标题、困倦信号、两个按钮；读屏只播报标题', (tester) async {
      final db = await _pump(tester);
      expect(_card, findsOneWidget);
      expect(find.text('宝宝醒了约 1 小时，可能快困了'), findsOneWidget);
      expect(find.text(reminderBody), findsOneWidget);
      expect(find.byKey(const Key('reminder-not-sleepy')), findsOneWidget);
      expect(find.byKey(const Key('reminder-start')), findsOneWidget);
      // 提醒卡不放 C2、不放月龄范围（Liam 确认）
      expect(find.descendant(of: _card, matching: find.textContaining('不要用哄睡的办法', findRichText: true)), findsNothing);
      expect(find.descendant(of: _card, matching: find.textContaining('1–1.5 小时')), findsNothing);
      expect(find.byWidgetPredicate((w) => w is Semantics && w.properties.liveRegion == true && w.properties.label == '宝宝醒了约 1 小时，可能快困了'), findsOneWidget);
      // 内嵌：在状态条下面、哭声按钮上面，哭声按钮仍然在第一屏
      final status = tester.getRect(find.textContaining('已醒', findRichText: true).first);
      expect(tester.getRect(_card).top, greaterThan(status.bottom));
      expect(tester.getRect(find.text('宝宝在哭')).bottom, lessThan(844));
      await _done(tester, db);
    });

    testWidgets('不到下限不出现；到 60 分钟自动出现', (tester) async {
      final db = await _pump(tester, awake: const Duration(minutes: 58));
      expect(_card, findsNothing);
      await tester.pump(const Duration(minutes: 2, seconds: 1));
      await settle(tester);
      expect(_card, findsOneWidget);
      await _done(tester, db);
    });

    testWidgets('21:00–06:00 不出现', (tester) async {
      final db = await _pump(tester, now: DateTime(2026, 10, 20, 21, 30));
      expect(_card, findsNothing);
      await _done(tester, db);
    });

    testWidgets('正在睡觉计时不出现', (tester) async {
      final db = await _pump(tester, sleeping: true);
      expect(_card, findsNothing);
      await _done(tester, db);
    });

    testWidgets('没有睡眠记录不出现', (tester) async {
      final db = await _pump(tester, awake: null);
      expect(_card, findsNothing);
      await _done(tester, db);
    });

    testWidgets('超过上限 2 倍（0–3 个月 3 小时）不出现', (tester) async {
      final db = await _pump(tester, awake: const Duration(hours: 3, minutes: 5));
      expect(_card, findsNothing);
      await _done(tester, db);
    });

    testWidgets('满 12 个月不出现', (tester) async {
      final db = await _pump(tester, birth: DateTime(2025, 9, 1));
      expect(_card, findsNothing);
      await _done(tester, db);
    });

    testWidgets('#28 压制钩子：有压制时不出现', (tester) async {
      final db = await _pump(
        tester,
        overrides: [
          sleepReminderSuppressorsProvider.overrideWithValue([_Sick()]),
        ],
      );
      expect(_card, findsNothing);
      await _done(tester, db);
    });

    testWidgets('「还不困」：收起，本次醒着期间不再出现（存在本机）', (tester) async {
      final db = await _pump(tester);
      await tester.tap(find.byKey(const Key('reminder-not-sleepy')));
      await settle(tester);
      expect(_card, findsNothing);
      final sp = await SharedPreferences.getInstance();
      expect(sp.getInt(SleepReminderDismissNotifier.key), noon.subtract(const Duration(minutes: 62)).millisecondsSinceEpoch);
      await tester.pump(const Duration(minutes: 30));
      await settle(tester);
      expect(_card, findsNothing);
      await _done(tester, db);
    });

    testWidgets('开始睡觉计时（或家人同步来一条睡眠）后 1 秒内收起', (tester) async {
      final db = await _pump(tester);
      expect(_card, findsOneWidget);
      await tester.runAsync(() => CareLogRepository(db).startSession('b1', CareLogType.sleep));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await settle(tester, 6);
      expect(_card, findsNothing);
      await _done(tester, db);
    });

    testWidgets('「开始哄睡」进入哄睡页；第一次进入自动弹出安全须知', (tester) async {
      final db = await _pump(tester, prefs: const {});
      await tester.tap(find.byKey(const Key('reminder-start')));
      await settle(tester, 12);
      expect(find.byKey(const Key('soothe-fixed-notes')), findsOneWidget);
      expect(find.text(safetySheetTitle), findsOneWidget);
      expect(find.text(safetyFirstTimeLine), findsOneWidget);
      await _done(tester, db);
    });

    testWidgets('大字体 1.4×：默认折叠正文，只留标题和两个按钮；可以展开、收起', (tester) async {
      // 首页时间线标题和换尿布提示在 390 宽 1.4× 下原本就溢出（master 已有，不属于 #38）：
      // 这里只要求溢出不是提醒卡造成的
      final errors = <FlutterErrorDetails>[];
      final old = FlutterError.onError;
      FlutterError.onError = errors.add;
      final db = await _pump(tester, textScale: 1.4);
      expect(_card, findsOneWidget);
      expect(find.byKey(const Key('reminder-body')), findsNothing);
      expect(find.text(reminderExpand), findsOneWidget);
      expect(tester.getSize(find.byKey(const Key('reminder-expand'))).height, greaterThanOrEqualTo(48));
      // 第一屏仍然能看到「宝宝在哭」
      expect(tester.getRect(find.text('宝宝在哭')).bottom, lessThan(844));
      await tester.tap(find.byKey(const Key('reminder-expand')));
      await settle(tester);
      expect(find.byKey(const Key('reminder-body')), findsOneWidget);
      expect(find.text(reminderCollapse), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == reminderCollapseSemantics && w.properties.expanded == true), findsOneWidget);
      await _done(tester, db);
      FlutterError.onError = old;
      for (final e in errors) {
        expect(e.exceptionAsString(), contains('overflowed'), reason: '只允许首页原有的溢出');
      }
    });

    for (final scale in [1.0, 1.3, 1.5, 2.0]) {
      testWidgets('提醒卡单独渲染 $scale× 日夜都不溢出、不截断', (tester) async {
        for (final night in [false, true]) {
          tester.view.physicalSize = const Size(390, 844) * 3;
          tester.view.devicePixelRatio = 3;
          addTearDown(tester.view.reset);
          SharedPreferences.setMockInitialValues({});
          final sp = await SharedPreferences.getInstance();
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                prefsProvider.overrideWithValue(sp),
                sleepReminderProvider.overrideWithValue(
                  SleepReminderDecision.show(awake: const Duration(minutes: 95), band: WakeBand.months3to6, wakeAt: noon),
                ),
                currentStageTipProvider.overrideWithValue(StageTip(ageDays: 106, stages: const [CryStage.sleepChange])),
              ],
              child: MaterialApp(
                theme: night ? AppTheme.night : AppTheme.day,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                ),
                home: Scaffold(
                  body: ListView(padding: const EdgeInsets.all(20), children: const [SleepReminderCard()]),
                ),
              ),
            ),
          );
          await settle(tester);
          if (find.byKey(const Key('reminder-expand')).evaluate().isNotEmpty) {
            await tester.tap(find.byKey(const Key('reminder-expand')));
            await settle(tester);
          }
          expect(find.byKey(const Key('reminder-body')), findsOneWidget);
          expect(find.byKey(const Key('reminder-stage')), findsOneWidget);
          expect(tester.takeException(), isNull, reason: 'night=$night');
          await unmount(tester);
        }
      });
    }

    testWidgets('1.0× 不折叠，也没有展开入口', (tester) async {
      final db = await _pump(tester);
      expect(find.byKey(const Key('reminder-expand')), findsNothing);
      await _done(tester, db);
    });

    testWidgets('睡眠模式变化期（4 个月）卡片内多一行阶段提示，点开是 #30 说明面板；42 天没有', (tester) async {
      var db = await _pump(tester);
      expect(find.byKey(const Key('reminder-stage')), findsNothing);
      await _done(tester, db);
      // 第 106 天：3–6 个月档，睡眠模式变化 92–152 天；醒了 95 分钟
      db = await _pump(tester, birth: DateTime(2026, 7, 6), awake: const Duration(minutes: 95));
      expect(find.text('宝宝醒了约 1.5 小时，可能快困了'), findsOneWidget);
      expect(find.byKey(const Key('reminder-stage')), findsOneWidget);
      expect(find.text('这周宝宝可能在睡眠模式变化期'), findsOneWidget);
      await tester.tap(find.byKey(const Key('reminder-stage')));
      await settle(tester, 10);
      expect(find.byKey(const Key('stage-sheet')), findsOneWidget);
      await _done(tester, db);
    });

    testWidgets('减少动态效果：卡片直接出现和消失', (tester) async {
      final db = await _pump(tester);
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await settle(tester, 2);
      expect(find.descendant(of: find.byType(SleepReminderCard), matching: find.byType(AnimatedSize)), findsNothing);
      await tester.tap(find.byKey(const Key('reminder-not-sleepy')));
      await tester.pump();
      expect(_card, findsNothing);
      await _done(tester, db);
    });
  });

  group('哄睡页', () {
    testWidgets('B1 固定提示、A2（0–3 个月）、底部安全须知（C1、C2、急症提示、补充、C3）都在', (tester) async {
      final db = await _pump(tester);
      await _open(tester, Routes.soothe);
      final fixed = find.byKey(const Key('soothe-fixed-notes'));
      for (final n in playerFixedNotes) {
        expect(find.descendant(of: fixed, matching: find.text(plainCopy(n), findRichText: true)), findsOneWidget);
      }
      expect(find.text(wakeRangeCopy[WakeBand.months0to3]!), findsOneWidget);
      final scroll = find.byKey(const Key('soothe-scroll'));
      await tester.dragUntilVisible(find.byKey(const Key('soothe-disclaimer')), scroll, const Offset(0, -300));
      for (final l in safeSleepLines) {
        expect(find.text(plainCopy(l), findRichText: true), findsOneWidget);
      }
      expect(find.text(plainCopy(sickNoSootheLine), findRichText: true), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('soothe-emergency')), matching: find.text(stageEmergencyLine)), findsOneWidget);
      expect(find.text(unusualCryLine), findsOneWidget);
      expect(find.text(disclaimerLine), findsOneWidget);
      await _done(tester, db);
    });

    testWidgets('A2 按当前月龄：3–6 个月、6–12 个月；12 个月以上不显示', (tester) async {
      var db = await _pump(tester, birth: DateTime(2026, 6, 1), awake: null);
      await _open(tester, Routes.soothe);
      expect(find.text(wakeRangeCopy[WakeBand.months3to6]!), findsOneWidget);
      await _done(tester, db);
      db = await _pump(tester, birth: DateTime(2026, 2, 1), awake: null);
      await _open(tester, Routes.soothe);
      expect(find.text(wakeRangeCopy[WakeBand.months6to12]!), findsOneWidget);
      await _done(tester, db);
      db = await _pump(tester, birth: DateTime(2025, 6, 1), awake: null);
      await _open(tester, Routes.soothe);
      expect(find.byKey(const Key('soothe-wake-range')), findsNothing);
      await _done(tester, db);
    });

    testWidgets('安全须知只自动弹一次；之后从右上角打开（不显示「第一次使用」）', (tester) async {
      final db = await _pump(tester, prefs: const {});
      await _open(tester, Routes.soothe);
      expect(find.text(safetySheetTitle), findsOneWidget);
      expect(find.text(safetyFirstTimeLine), findsOneWidget);
      await tester.tap(find.byKey(const Key('safety-got-it')));
      await settle(tester, 10);
      expect(find.text(safetySheetTitle), findsNothing);
      final sp = await SharedPreferences.getInstance();
      expect(sp.getBool(sootheSafetySeenKey), isTrue);
      // 再进一次：不自动弹
      await _open(tester, Routes.home);
      await _open(tester, Routes.soothe);
      expect(find.text(safetySheetTitle), findsNothing);
      await tester.tap(find.byKey(const Key('soothe-safety-link')));
      await settle(tester, 10);
      expect(find.text(safetySheetTitle), findsOneWidget);
      expect(find.text(safetyFirstTimeLine), findsNothing);
      await _done(tester, db);
    });

    testWidgets('安全须知面板内容：安全睡眠、包裹、绝不能摇晃（读屏读「重要：」）、哄睡声音、可能生病时、急症提示、C3', (tester) async {
      final db = await _pump(tester);
      await _open(tester, Routes.soothe);
      await tester.tap(find.byKey(const Key('soothe-safety-link')));
      await settle(tester, 10);
      final sheet = find.byType(SootheSafetySheet);
      for (final t in [safetySleepHeading, safetySwaddleHeading, safetySoundHeading, safetySickHeading]) {
        expect(find.descendant(of: sheet, matching: find.text(t)), findsOneWidget);
      }
      expect(find.bySemanticsLabel('重要：${plainCopy(neverShakeLine)}'), findsOneWidget);
      await _scrollToEnd(tester, find.byKey(const Key('safety-sheet-scroll')));
      expect(find.descendant(of: sheet, matching: find.byKey(const Key('safety-emergency'))), findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.text(disclaimerLine)), findsOneWidget);
      await _done(tester, db);
    });

    testWidgets('「睡着了 · 开始记录睡觉」：开始睡觉计时并回到首页', (tester) async {
      final db = await _pump(tester);
      await _open(tester, Routes.soothe);
      await tester.tap(find.byKey(const Key('soothe-asleep')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await settle(tester, 10);
      final active = await tester.runAsync(() => CareLogRepository(db).activeSession('b1', CareLogType.sleep));
      expect(active, isNotNull);
      expect(find.text('宝宝在哭'), findsOneWidget);
      expect(find.textContaining('睡觉中', findRichText: true), findsWidgets);
      await _done(tester, db);
    });

    testWidgets('已经在睡觉计时：主按钮显示「睡觉已在计时」并且不能点', (tester) async {
      final db = await _pump(tester, sleeping: true);
      await _open(tester, Routes.soothe);
      expect(find.text(asleepAlreadyLogging), findsOneWidget);
      final btn = tester.widget<TextButton>(find.descendant(of: find.byKey(const Key('soothe-asleep')), matching: find.byType(TextButton)));
      expect(btn.onPressed, isNull);
      await _done(tester, db);
    });
  });

  group('哄睡步骤', () {
    testWidgets('6 步，上一步 / 下一步；每一步都有「撑不住」；第 3 步紧跟红框；末尾有安全内容', (tester) async {
      final db = await _pump(tester, birth: DateTime(2026, 6, 1)); // 第 141 天：不在哭闹高峰期
      await _open(tester, Routes.sootheSteps);
      expect(find.byKey(const Key('steps-never-shake-top')), findsNothing);
      for (var i = 0; i < sootheSteps.length; i++) {
        expect(find.text('第 ${i + 1} / 6 步'), findsOneWidget);
        expect(find.text(sootheSteps[i].title), findsWidgets);
        expect(find.byKey(const Key('steps-overwhelmed')), findsOneWidget);
        expect(find.text(plainCopy(overwhelmedLine), findRichText: true), findsOneWidget);
        expect(find.byKey(const Key('steps-never-shake')), i == shakeStepIndex ? findsOneWidget : findsNothing);
        if (i < sootheSteps.length - 1) {
          expect(find.text('$nextStepPrefix${sootheSteps[i + 1].title}'), findsOneWidget);
          await tester.tap(find.byKey(const Key('steps-next')));
          await settle(tester, 4);
        }
      }
      expect(find.text(stepsDone), findsOneWidget);
      await tester.tap(find.byKey(const Key('steps-prev')));
      await settle(tester, 4);
      expect(find.text('第 5 / 6 步'), findsOneWidget);
      await tester.dragUntilVisible(find.byKey(const Key('steps-disclaimer')), find.byKey(const Key('steps-scroll')), const Offset(0, -300));
      expect(find.byKey(const Key('steps-emergency')), findsOneWidget);
      expect(find.text(plainCopy(sickNoSootheLine), findRichText: true), findsOneWidget);
      await _done(tester, db);
    });

    testWidgets('左右滑动切换步骤', (tester) async {
      final db = await _pump(tester);
      await _open(tester, Routes.sootheSteps);
      await tester.fling(find.byKey(const ValueKey('soothe-step-0')), const Offset(-300, 0), 1000);
      await settle(tester, 4);
      expect(find.text('第 2 / 6 步'), findsOneWidget);
      await tester.fling(find.byKey(const ValueKey('soothe-step-1')), const Offset(300, 0), 1000);
      await settle(tester, 4);
      expect(find.text('第 1 / 6 步'), findsOneWidget);
      await _done(tester, db);
    });

    testWidgets('哭闹高峰期（第 42 天）：「绝不能摇晃宝宝」置顶', (tester) async {
      final db = await _pump(tester);
      await _open(tester, Routes.sootheSteps);
      expect(find.byKey(const Key('steps-never-shake-top')), findsOneWidget);
      expect(find.bySemanticsLabel('重要：${plainCopy(neverShakeLine)}'), findsOneWidget);
      final top = tester.getRect(find.byKey(const Key('steps-never-shake-top')));
      expect(top.top, lessThan(tester.getRect(find.byKey(const ValueKey('soothe-step-0'))).top));
      await _done(tester, db);
    });
  });

  group('底部固定区不遮挡内容（终稿修订 6287435046：padding = 实测高度 + 16dp）', () {
    for (final scale in [1.0, 1.4]) {
      testWidgets('安全须知面板 $scale×：滚到底急症框和最后一行完整显示；渐变只在没滚到底时出现', (tester) async {
        final db = await _pump(tester, textScale: scale);
        await _open(tester, Routes.soothe);
        await tester.tap(find.byKey(const Key('soothe-safety-link')));
        await settle(tester, 10);
        final fade = find.byKey(const Key('pinned-fade'));
        expect(fade, findsOneWidget, reason: '刚弹出时内容超出一屏，要有渐变');
        expect(tester.getSize(fade).height, 32);
        final bar = find.byKey(const Key('safety-sheet-bottom'));
        // 渐变紧贴在「知道了」上方，不拦截点击
        expect(tester.getRect(fade).bottom, closeTo(tester.getRect(bar).top, .01));
        await _scrollToEnd(tester, find.byKey(const Key('safety-sheet-scroll')));
        _expectClearOfBar(tester, find.byKey(const Key('safety-emergency')), bar);
        _expectClearOfBar(tester, find.descendant(of: find.byType(SootheSafetySheet), matching: find.text(disclaimerLine)), bar);
        expect(fade, findsNothing, reason: '滚到底后渐变隐藏');
        expect(tester.takeException(), isNull);
        await _done(tester, db);
      });

      testWidgets('哄睡页 $scale×：滚到底急症框和 C3 不被底部操作条压住', (tester) async {
        final db = await _pump(tester, textScale: scale);
        await _open(tester, Routes.soothe);
        await _scrollToEnd(tester, find.byKey(const Key('soothe-scroll')));
        final bar = find.byKey(const Key('soothe-bottom'));
        _expectClearOfBar(tester, find.byKey(const Key('soothe-emergency')), bar);
        _expectClearOfBar(tester, find.byKey(const Key('soothe-disclaimer')), bar);
        expect(tester.takeException(), isNull);
        await _done(tester, db);
      });

      testWidgets('步骤页 $scale×：滚到底急症框和 C3 不被底部操作条压住', (tester) async {
        final db = await _pump(tester, textScale: scale);
        await _open(tester, Routes.sootheSteps);
        await _scrollToEnd(tester, find.byKey(const Key('steps-scroll')));
        final bar = find.byKey(const Key('steps-bottom'));
        _expectClearOfBar(tester, find.byKey(const Key('steps-emergency')), bar);
        _expectClearOfBar(tester, find.byKey(const Key('steps-disclaimer')), bar);
        expect(tester.takeException(), isNull);
        await _done(tester, db);
      });
    }

    testWidgets('padding 跟着底部区实测高度变（1.0× 和 1.4× 不同）', (tester) async {
      double padFor(WidgetTester t) {
        final lv = t.widget<ListView>(find.byKey(const Key('soothe-scroll')));
        return (lv.padding! as EdgeInsets).bottom;
      }

      var db = await _pump(tester);
      await _open(tester, Routes.soothe);
      final h1 = tester.getSize(find.byKey(const Key('soothe-bottom'))).height;
      expect(padFor(tester), closeTo(h1 + 16, .01));
      await _done(tester, db);
      db = await _pump(tester, textScale: 1.4);
      await _open(tester, Routes.soothe);
      final h2 = tester.getSize(find.byKey(const Key('soothe-bottom'))).height;
      expect(h2, greaterThan(h1));
      expect(padFor(tester), closeTo(h2 + 16, .01));
      await _done(tester, db);
    });
  });

  group('结果页「困了」→ 开始哄睡', () {
    String pred(String top) => jsonEncode({
      'version': 'rule-1',
      'ranked': [
        {'cause': top, 'p': .5, 'reason': '已经醒了 1 小时 2 分'},
        {'cause': top == 'sleepy' ? 'hungry' : 'sleepy', 'p': .3, 'reason': 'x'},
        {'cause': 'holdMe', 'p': .2, 'reason': 'y'},
      ],
    });

    Future<AppDatabase> pumpResult(WidgetTester tester, String top, {bool sleeping = false, List overrides = const []}) async {
      final db = await _pump(tester, sleeping: sleeping, overrides: overrides);
      await tester.runAsync(
        () => db
            .into(db.cryEvents)
            .insert(
              CryEventsCompanion.insert(
                id: 'e1',
                babyId: 'b1',
                startedAt: noon,
                durationMs: 10000,
                contextJson: '{}',
                predictionJson: pred(top),
                predictorVersion: 'rule-1',
              ),
            ),
      );
      _router(tester).go(Routes.result('e1'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await settle(tester, 10);
      return db;
    }

    testWidgets('第一名是困了：建议卡里有「开始哄睡」和 C2，点了进入哄睡页', (tester) async {
      final db = await pumpResult(tester, 'sleepy');
      expect(find.text('建议先试哄睡'), findsOneWidget);
      expect(find.byKey(const Key('soothe-entry-start')), findsOneWidget);
      expect(find.text(plainCopy(sickNoSootheLine), findRichText: true), findsOneWidget);
      await tester.tap(find.byKey(const Key('soothe-entry-start')));
      await settle(tester, 10);
      expect(find.byKey(const Key('soothe-fixed-notes')), findsOneWidget);
      await _done(tester, db);
    });

    testWidgets('第一名不是困了：没有入口', (tester) async {
      final db = await pumpResult(tester, 'hungry');
      expect(find.byKey(const Key('soothe-entry')), findsNothing);
      await _done(tester, db);
    });

    testWidgets('睡觉计时中：SleepResultCard 优先，「开始哄睡」不显示', (tester) async {
      final db = await pumpResult(tester, 'sleepy', sleeping: true);
      expect(find.byKey(const Key('sleep-result-card')), findsOneWidget);
      expect(find.byKey(const Key('soothe-entry')), findsNothing);
      await _done(tester, db);
    });

    testWidgets('#28 压制：不给哄睡入口，换成 C2 + 急症提示', (tester) async {
      final db = await pumpResult(
        tester,
        'sleepy',
        overrides: [
          sleepReminderSuppressorsProvider.overrideWithValue([_Sick()]),
        ],
      );
      expect(find.byKey(const Key('soothe-entry-start')), findsNothing);
      expect(find.byKey(const Key('soothe-entry-see-doctor')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('soothe-entry-emergency')), matching: find.text(stageEmergencyLine)), findsOneWidget);
      await _done(tester, db);
    });
  });

  testWidgets('热区：提醒卡按钮、展开入口、哄睡页按钮和链接都 ≥ 48dp', (tester) async {
    final db = await _pump(tester);
    for (final k in ['reminder-not-sleepy', 'reminder-start']) {
      expect(tester.getSize(find.byKey(Key(k))).height, greaterThanOrEqualTo(48), reason: k);
    }
    await _open(tester, Routes.soothe);
    for (final k in ['soothe-asleep', 'soothe-safety-link', 'soothe-steps-link']) {
      expect(tester.getSize(find.byKey(Key(k))).height, greaterThanOrEqualTo(48), reason: k);
    }
    await _done(tester, db);
  });

  testWidgets('夜间模式：提醒卡和哄睡页都能正常显示', (tester) async {
    final db = await _pump(tester, prefs: const {sootheSafetySeenKey: true, 'night_mode': true});
    expect(_card, findsOneWidget);
    await _open(tester, Routes.soothe);
    expect(find.byKey(const Key('soothe-fixed-notes')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _done(tester, db);
  });
}
