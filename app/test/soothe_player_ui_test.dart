import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/core/router/app_router.dart';
import 'package:honghong/core/theme/app_theme.dart';
import 'package:honghong/data/db/app_database.dart';
import 'package:honghong/features/soothe/soothe_audio.dart';
import 'package:honghong/features/soothe/soothe_copy.dart';
import 'package:honghong/features/soothe/soothe_page.dart';
import 'package:honghong/services/audio/auto_listen.dart';
import 'package:honghong/core/prefs.dart';

import 'fake_soothe_engine.dart';
import 'helpers.dart';

/// 2026-10-20 14:00，宝宝 42 天，62 分钟前醒
final _now = DateTime(2026, 10, 20, 14);

late FakeSootheEngine _engine;

Future<AppDatabase> _pump(WidgetTester tester, {double textScale = 1, bool sleeping = false, bool night = false}) async {
  tester.view.physicalSize = const Size(390, 844) * 3;
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  fixClock(tester, _now);
  _engine = FakeSootheEngine();
  final db = await pumpApp(
    tester,
    prefs: {sootheSafetySeenKey: true, AutoListenNotifier.key: true, if (night) 'night_mode': true},
    overrides: [sootheEngineProvider.overrideWithValue(_engine)],
    seed: (db) async {
      await db.into(db.babies).insert(BabiesCompanion.insert(id: 'b1', nickname: '小米粒', birthDate: DateTime(2026, 9, 8)));
      final end = _now.subtract(const Duration(minutes: 62));
      await db
          .into(db.careLogs)
          .insert(CareLogsCompanion.insert(id: 's1', babyId: 'b1', type: 'sleep', startedAt: end.subtract(const Duration(hours: 1)), endedAt: Value(end)));
      if (sleeping) {
        await db
            .into(db.careLogs)
            .insert(CareLogsCompanion.insert(id: 's2', babyId: 'b1', type: 'sleep', startedAt: _now.subtract(const Duration(minutes: 5))));
      }
    },
  );
  await _go(tester, Routes.soothe);
  return db;
}

ProviderContainer _container(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));

Future<void> _go(WidgetTester tester, String path) async {
  tester.takeException(); // 首页在大字体下原有的溢出（master 上已有，不属于 #38）
  _container(tester).read(routerProvider).go(path);
  await settle(tester, 10);
}

Future<void> _done(WidgetTester tester, AppDatabase db) async {
  await unmount(tester);
  await tester.runAsync(db.close);
}

Future<void> _tap(WidgetTester tester, String key) async {
  final f = find.byKey(Key(key));
  await tester.ensureVisible(f);
  await tester.tap(f);
  await settle(tester, 4);
}

Future<void> _wait(WidgetTester tester, Duration d) async {
  for (var s = 0; s < d.inSeconds; s += 30) {
    await tester.pump(Duration(seconds: d.inSeconds - s < 30 ? d.inSeconds - s : 30));
  }
  await settle(tester, 2);
}

Finder _rich(String copy) => find.text(plainCopy(copy), findRichText: true);

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('初始状态：粉噪音（默认）选中、音量 30% / 最高 70%、定时 30 分钟；左「开始播放」右「睡着了」；不自动播放', (tester) async {
    final db = await _pump(tester);
    for (final s in SootheSound.values) {
      expect(find.byKey(Key('sound-${s.name}')), findsOneWidget);
    }
    expect(find.text('✓ 粉噪音'), findsOneWidget);
    expect(find.text('白噪音'), findsOneWidget);
    expect(find.text(playerDefaultTag), findsOneWidget);
    expect(find.text('音量 30%'), findsOneWidget);
    expect(find.text(playerVolumeMax), findsOneWidget);
    final slider = tester.widget<Slider>(find.byKey(const Key('soothe-volume')));
    expect((slider.value, slider.max), (.30, .70));
    expect(find.text(playerTimerHeading), findsOneWidget);
    for (final m in sootheTimerOptions) {
      expect(find.text('$m 分钟'), findsOneWidget);
    }
    expect(find.byKey(const Key('soothe-play')), findsOneWidget);
    expect(find.byKey(const Key('soothe-asleep')), findsOneWidget);
    expect(find.byKey(const Key('soothe-status')), findsNothing);
    expect(_engine.calls, isEmpty);
    // 读屏：声音块是按钮，带选中状态，默认的那块读出「默认」
    expect(find.byWidgetPredicate((w) => w is Semantics && w.properties.selected == true && w.properties.label == '粉噪音，默认'), findsOneWidget);
    await _done(tester, db);
  });

  testWidgets('开始播放 → 「粉噪音播放中 · 30:00 后自动关闭」、左按钮变「停止」、暂停自动听哭声；停止后恢复', (tester) async {
    final db = await _pump(tester);
    await _tap(tester, 'soothe-play');
    expect(_engine.playing, isTrue);
    expect(_engine.loaded, SootheSound.pink);
    expect(_rich(playerPlayingStatus('粉噪音', '30:00')), findsOneWidget);
    expect(find.byKey(const Key('soothe-stop')), findsOneWidget);
    final listen = _container(tester).read(autoListenControllerProvider.notifier);
    expect(listen.heldForSoothe, isTrue);
    await _wait(tester, const Duration(minutes: 1));
    expect(_rich(playerPlayingStatus('粉噪音', '29:00')), findsOneWidget);
    await _tap(tester, 'soothe-stop');
    expect(_engine.playing, isFalse);
    expect(find.byKey(const Key('soothe-play')), findsOneWidget);
    expect(listen.heldForSoothe, isFalse);
    await _done(tester, db);
  });

  testWidgets('选声音、拖音量、改定时都生效；播放中换声音接着播', (tester) async {
    final db = await _pump(tester);
    await _tap(tester, 'sound-shush');
    expect(find.text('✓ 嘘声'), findsOneWidget);
    expect(find.text('粉噪音'), findsOneWidget);
    await tester.ensureVisible(find.text('15 分钟'));
    await tester.tap(find.text('15 分钟'));
    await settle(tester, 2);
    _container(tester).read(sootheAudioProvider.notifier).setVolume(.5);
    await settle(tester, 2);
    expect(find.text('音量 50%'), findsOneWidget);
    await _tap(tester, 'soothe-play');
    expect(_rich(playerPlayingStatus('嘘声', '15:00')), findsOneWidget);
    await _tap(tester, 'sound-brown');
    await settle(tester, 4); // 先淡出 0.5 秒再换
    expect(_engine.loaded, SootheSound.brown);
    expect(_engine.playing, isTrue);
    await _tap(tester, 'soothe-stop');
    await _done(tester, db);
  });

  testWidgets('定时结束（终稿 11）：「已自动关闭 · 粉噪音播放了 30 分钟」（读屏播报）+「再播 15 分钟」；点了播 15 分钟', (tester) async {
    final db = await _pump(tester);
    await _tap(tester, 'soothe-play');
    await _wait(tester, const Duration(minutes: 30, seconds: 30));
    expect(_rich(playerEndedStatus('粉噪音', 30)), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is Semantics && w.key == const Key('soothe-status') && w.properties.liveRegion == true), findsOneWidget);
    expect(find.byKey(const Key('soothe-extra')), findsOneWidget);
    expect(find.text(playerExtra), findsOneWidget);
    expect(find.text(asleepStartLog), findsOneWidget);
    expect(find.byKey(const Key('soothe-steps-link')), findsOneWidget);
    await _tap(tester, 'soothe-extra');
    expect(_rich(playerPlayingStatus('粉噪音', '15:00')), findsOneWidget);
    // 定时选项不变
    expect(_container(tester).read(sootheAudioProvider).timerMinutes, 30);
    await _tap(tester, 'soothe-stop');
    await _done(tester, db);
  });

  testWidgets('定时结束后已经在睡觉计时：主按钮「睡觉已在计时」不能点，「再播 15 分钟」照常可用', (tester) async {
    final db = await _pump(tester, sleeping: true);
    await _tap(tester, 'soothe-play');
    await _wait(tester, const Duration(minutes: 30, seconds: 30));
    expect(find.text(asleepAlreadyLogging), findsOneWidget);
    final asleep = find.descendant(of: find.byKey(const Key('soothe-asleep')), matching: find.byType(TextButton));
    expect(tester.widget<TextButton>(asleep).onPressed, isNull);
    await _tap(tester, 'soothe-extra');
    expect(_engine.playing, isTrue);
    await _tap(tester, 'soothe-stop');
    await _done(tester, db);
  });

  testWidgets('定时结束后离开哄睡页，再进来是初始状态', (tester) async {
    final db = await _pump(tester);
    await _tap(tester, 'sound-white');
    await _tap(tester, 'soothe-play');
    await _wait(tester, const Duration(minutes: 30, seconds: 30));
    await _go(tester, Routes.home);
    await _go(tester, Routes.soothe);
    expect(find.text('✓ 粉噪音'), findsOneWidget);
    expect(find.text('音量 30%'), findsOneWidget);
    expect(find.byKey(const Key('soothe-play')), findsOneWidget);
    expect(find.byKey(const Key('soothe-status')), findsNothing);
    await _done(tester, db);
  });

  testWidgets('播放中离开再回来：照常播放，状态不丢', (tester) async {
    final db = await _pump(tester);
    await _tap(tester, 'soothe-play');
    await _go(tester, Routes.home);
    await _wait(tester, const Duration(minutes: 5));
    await _go(tester, Routes.soothe);
    expect(_engine.playing, isTrue);
    expect(find.byKey(const Key('soothe-stop')), findsOneWidget);
    final left = _container(tester).read(sootheAudioProvider).remaining;
    expect(left.inSeconds, inInclusiveRange(24 * 60 + 55, 25 * 60));
    expect(_rich(playerPlayingStatus('粉噪音', formatRemaining(left))), findsOneWidget);
    await _tap(tester, 'soothe-stop');
    await _done(tester, db);
  });

  testWidgets('来电打断：「已暂停 · 点继续」，不自动继续；点「继续」接着播', (tester) async {
    final db = await _pump(tester);
    await _tap(tester, 'soothe-play');
    await _wait(tester, const Duration(minutes: 2));
    _engine.emit(SootheEngineEvent.interrupted);
    await settle(tester, 2);
    expect(_rich(playerPausedStatus), findsOneWidget);
    await _wait(tester, const Duration(minutes: 5));
    expect(_engine.playing, isFalse);
    await _tap(tester, 'soothe-resume');
    expect(_engine.playing, isTrue);
    final left = _container(tester).read(sootheAudioProvider).remaining;
    expect(left.inSeconds, inInclusiveRange(27 * 60 + 58, 28 * 60));
    expect(_rich(playerPlayingStatus('粉噪音', formatRemaining(left))), findsOneWidget);
    await _tap(tester, 'soothe-stop');
    await _done(tester, db);
  });

  testWidgets('声音没能播放：醒目提示退回自己发「嘘——」，按钮「再试一次」', (tester) async {
    final db = await _pump(tester);
    _engine.failLoad = true;
    await _tap(tester, 'soothe-play');
    expect(find.text(playerErrorLine), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == '重要：$playerErrorLine'), findsOneWidget);
    expect(find.text(playerRetry), findsOneWidget);
    _engine.failLoad = false;
    await _tap(tester, 'soothe-play');
    expect(_engine.playing, isTrue);
    await _tap(tester, 'soothe-stop');
    await _done(tester, db);
  });

  testWidgets('步骤页迷你播放条（终稿 04）：播放中显示「粉噪音播放中 · mm:ss 后关闭」和「停止」；没播时不显示', (tester) async {
    final db = await _pump(tester);
    await _go(tester, Routes.sootheSteps);
    expect(find.byKey(const Key('steps-mini-player')), findsNothing);
    await _go(tester, Routes.soothe);
    await _tap(tester, 'soothe-play');
    _container(tester).read(routerProvider).push(Routes.sootheSteps).ignore(); // push 要到返回时才结束
    await settle(tester, 10);
    expect(find.byKey(const Key('steps-mini-player')), findsOneWidget);
    String left() => formatRemaining(_container(tester).read(sootheAudioProvider).remaining);
    expect(left(), startsWith('29:5'));
    expect(_rich(playerMiniStatus('粉噪音', left())), findsOneWidget);
    await _wait(tester, const Duration(minutes: 3, seconds: 49));
    expect(left(), startsWith('26:'));
    expect(_rich(playerMiniStatus('粉噪音', left())), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('steps-mini-stop'))).height, greaterThanOrEqualTo(48));
    await _tap(tester, 'steps-mini-stop');
    expect(_engine.playing, isFalse);
    expect(find.byKey(const Key('steps-mini-player')), findsNothing);
    await _done(tester, db);
  });

  group('底部固定区不遮挡（padding = 实测高度 + 16dp）', () {
    for (final scale in [1.0, 1.4]) {
      testWidgets('定时结束状态 $scale×（final-11 / 11b）：滚到底急症框和 C3 完整显示；padding 跟着变高的底部区', (tester) async {
        final db = await _pump(tester, textScale: scale);
        final bar = find.byKey(const Key('soothe-bottom'));
        final idleH = tester.getSize(bar).height;
        await _tap(tester, 'soothe-play');
        await _wait(tester, const Duration(minutes: 30, seconds: 30));
        expect(find.byKey(const Key('soothe-extra')), findsOneWidget);
        final h = tester.getSize(bar).height;
        expect(h, greaterThan(idleH), reason: '多了一行状态');
        final lv = tester.widget<ListView>(find.byKey(const Key('soothe-scroll')));
        expect((lv.padding! as EdgeInsets).bottom, closeTo(h + 16, .01));
        for (var i = 0; i < 40; i++) {
          await tester.drag(find.byKey(const Key('soothe-scroll')), const Offset(0, -400));
          await tester.pump(const Duration(milliseconds: 50));
        }
        await settle(tester, 4);
        for (final k in ['soothe-emergency', 'soothe-disclaimer']) {
          expect(tester.getRect(bar).top - tester.getRect(find.byKey(Key(k))).bottom, greaterThanOrEqualTo(16 - .01), reason: k);
        }
        if (scale > 1.3) {
          // 大字体：两个按钮上下排，「再播 15 分钟」在上
          expect(tester.getRect(find.byKey(const Key('soothe-extra'))).bottom, lessThanOrEqualTo(tester.getRect(find.byKey(const Key('soothe-asleep'))).top));
        }
        expect(tester.takeException(), isNull);
        await _done(tester, db);
      });
    }
  });

  testWidgets('声音选中态（终稿第 7 条）：日间 peachL 底 + peach 描边，夜间 card 底 + peach2 描边，文字 ink', (tester) async {
    for (final night in [false, true]) {
      final db = await _pump(tester, night: night);
      await settle(tester, 6); // 日夜主题插值 400ms
      final c = tester.element(find.byKey(const Key('sound-pink'))).hh;
      final box = tester.widget<AnimatedContainer>(find.descendant(of: find.byKey(const Key('sound-pink')), matching: find.byType(AnimatedContainer)));
      final d = box.decoration! as BoxDecoration;
      expect(d.color, night ? c.card : c.peachL);
      expect((d.border! as Border).top.color, night ? c.peach2 : c.peach);
      expect(tester.widget<Text>(find.text('✓ 粉噪音')).style!.color, c.ink);
      await _done(tester, db);
    }
  });

  testWidgets('热区 ≥ 48dp：声音块、开始播放 / 停止', (tester) async {
    final db = await _pump(tester);
    for (final s in SootheSound.values) {
      expect(tester.getSize(find.byKey(Key('sound-${s.name}'))).height, greaterThanOrEqualTo(48), reason: s.name);
    }
    expect(tester.getSize(find.byKey(const Key('soothe-play'))).height, greaterThanOrEqualTo(48));
    await _tap(tester, 'soothe-play');
    expect(tester.getSize(find.byKey(const Key('soothe-stop'))).height, greaterThanOrEqualTo(48));
    await _tap(tester, 'soothe-stop');
    await _done(tester, db);
  });

  testWidgets('QA 第 3 条（Liam 决定）：播放中点「睡着了」→ 声音马上停（和「停止」一样）、开始记录睡觉、回首页', (tester) async {
    final db = await _pump(tester);
    await _tap(tester, 'soothe-play');
    expect(_engine.playing, isTrue);
    await _wait(tester, const Duration(minutes: 3));
    await _tap(tester, 'soothe-asleep');
    await settle(tester, 6);
    expect(_engine.playing, isFalse);
    expect(_engine.calls.last, 'stop');
    final c = _container(tester);
    expect(c.read(sootheAudioProvider).phase, SoothePhase.idle);
    expect(c.read(autoListenControllerProvider.notifier).heldForSoothe, isFalse);
    final open = (await tester.runAsync(() => db.select(db.careLogs).get()))!.where((l) => l.type == 'sleep' && l.endedAt == null).toList();
    expect(open, hasLength(1));
    expect(find.text('宝宝在哭'), findsOneWidget);
    await _wait(tester, const Duration(minutes: 40));
    expect(_engine.playing, isFalse);
    await _done(tester, db);
  });
}
