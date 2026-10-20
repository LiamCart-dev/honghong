import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/core/app_clock.dart';
import 'package:honghong/core/prefs.dart';
import 'package:honghong/features/soothe/soothe_audio.dart';
import 'package:honghong/services/audio/auto_listen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_soothe_engine.dart';
import 'helpers.dart';

final _t0 = DateTime(2026, 10, 20, 14);

/// 时间跟着 tester.pump 走；自动听哭声开关打开
Future<(ProviderContainer, FakeSootheEngine)> _setup(WidgetTester tester, {bool autoListen = true}) async {
  fixClock(tester, _t0);
  SharedPreferences.setMockInitialValues({AutoListenNotifier.key: autoListen});
  final sp = await SharedPreferences.getInstance();
  final engine = FakeSootheEngine();
  final c = ProviderContainer(overrides: [prefsProvider.overrideWithValue(sp), sootheEngineProvider.overrideWithValue(engine)]);
  addTearDown(c.dispose);
  c.read(autoListenControllerProvider); // 首页一直在 watch
  return (c, engine);
}

SootheAudioController _ctl(ProviderContainer c) => c.read(sootheAudioProvider.notifier);
SootheAudioState _s(ProviderContainer c) => c.read(sootheAudioProvider);
AutoListenController _listen(ProviderContainer c) => c.read(autoListenControllerProvider.notifier);

Future<void> _wait(WidgetTester tester, Duration d) async {
  // 按 1 秒一步推进，让 250ms 的定时器正常跑
  final end = d.inMilliseconds;
  for (var ms = 0; ms < end; ms += 1000) {
    await tester.pump(Duration(milliseconds: end - ms < 1000 ? end - ms : 1000));
  }
}

void main() {
  group('默认值（Liam 2026-10-20 确认）', () {
    test('粉噪音、30%、最高 70%、定时 15/30/45/60 默认 30、淡入 3 秒、淡出 10 秒、再播 15 分钟', () {
      const s = SootheAudioState();
      expect(s.sound, SootheSound.pink);
      expect(s.volume, .30);
      expect(sootheMaxVolume, .70);
      expect(s.timerMinutes, 30);
      expect(sootheTimerOptions, [15, 30, 45, 60]);
      expect(sootheFadeIn, const Duration(seconds: 3));
      expect(sootheFadeOut, const Duration(seconds: 10));
      expect(sootheExtraMinutes, 15);
      expect(s.phase, SoothePhase.idle);
    });

    test('四种声音的素材都在仓库里（脚本生成、CC0），10 秒单声道 22050 Hz', () {
      for (final s in SootheSound.values) {
        final f = File(s.asset);
        expect(f.existsSync(), isTrue, reason: s.asset);
        final b = f.readAsBytesSync();
        expect(String.fromCharCodes(b.sublist(0, 4)), 'RIFF');
        final rate = b.buffer.asByteData().getUint32(24, Endian.little);
        final channels = b.buffer.asByteData().getUint16(22, Endian.little);
        expect((rate, channels), (22050, 1));
        expect(b.length, 44 + 22050 * 2 * 10);
      }
      expect(File('assets/soothe/LICENSE.md').readAsStringSync(), contains('CC0'));
      expect(File('tool/soothe_sounds/generate.py').existsSync(), isTrue);
    });

    test('淡入淡出系数', () {
      expect(sootheFadeGain(sinceStart: Duration.zero, remaining: const Duration(minutes: 30)), 0);
      expect(sootheFadeGain(sinceStart: const Duration(milliseconds: 1500), remaining: const Duration(minutes: 30)), closeTo(.5, 1e-9));
      expect(sootheFadeGain(sinceStart: const Duration(seconds: 3), remaining: const Duration(minutes: 30)), 1);
      expect(sootheFadeGain(sinceStart: const Duration(minutes: 5), remaining: const Duration(seconds: 5)), closeTo(.5, 1e-9));
      expect(sootheFadeGain(sinceStart: const Duration(minutes: 5), remaining: Duration.zero), 0);
    });

    test('剩余时间格式', () {
      expect(formatRemaining(const Duration(minutes: 28, seconds: 41)), '28:41');
      expect(formatRemaining(const Duration(minutes: 30)), '30:00');
      expect(formatRemaining(const Duration(seconds: 9)), '00:09');
    });
  });

  group('音量', () {
    testWidgets('滑块最高 70%；播放器收到的音量从不超过 70%（不做增益）', (tester) async {
      final (c, engine) = await _setup(tester);
      _ctl(c).setVolume(1.0);
      expect(_s(c).volume, .70);
      _ctl(c).setVolume(-1);
      expect(_s(c).volume, 0);
      _ctl(c).setVolume(.7);
      await _ctl(c).start();
      await _wait(tester, const Duration(minutes: 1));
      expect(engine.volume, closeTo(.7, 1e-9));
      expect(engine.volumes.every((v) => v >= 0 && v <= .7 + 1e-9), isTrue);
      await _ctl(c).stop();
    });

    testWidgets('每次进哄睡页（没在播）都回到默认值；正在播时不重置', (tester) async {
      final (c, _) = await _setup(tester);
      _ctl(c)
        ..setVolume(.6)
        ..setTimer(60)
        ..selectSound(SootheSound.brown);
      _ctl(c).resetIfNotActive();
      expect((_s(c).sound, _s(c).volume, _s(c).timerMinutes), (SootheSound.pink, .30, 30));
      _ctl(c).setVolume(.5);
      await _ctl(c).start();
      _ctl(c).resetIfNotActive();
      expect(_s(c).volume, .5);
      expect(_s(c).phase, SoothePhase.playing);
      await _ctl(c).stop();
    });
  });

  group('定时关闭和淡入淡出', () {
    testWidgets('默认 30 分钟：3 秒淡入到 30%，最后 10 秒淡出，到点停止并显示「播放了 30 分钟」', (tester) async {
      final (c, engine) = await _setup(tester);
      await _ctl(c).start();
      expect(engine.loaded, SootheSound.pink);
      expect(engine.playing, isTrue);
      expect(engine.volumes.first, 0); // 从 0 开始淡入
      expect(_s(c).remaining, const Duration(minutes: 30));
      await tester.pump(const Duration(milliseconds: 1500));
      expect(engine.volume, closeTo(.15, .02));
      await tester.pump(const Duration(milliseconds: 2000));
      expect(engine.volume, closeTo(.30, 1e-9));
      await _wait(tester, const Duration(minutes: 29, seconds: 51, milliseconds: 500));
      // 还剩 5 秒：淡出到一半
      expect(_s(c).remaining, const Duration(seconds: 5));
      expect(engine.volume, closeTo(.15, .02));
      expect(_s(c).phase, SoothePhase.playing);
      await _wait(tester, const Duration(seconds: 6));
      expect(_s(c).phase, SoothePhase.ended);
      expect(_s(c).playedMinutes, 30);
      expect(engine.playing, isFalse);
      expect(engine.volume, 0);
      // 不 stop：保留锁屏控件，点播放 = 再播 15 分钟
      expect(engine.calls.last, 'pause');
    });

    testWidgets('15 / 45 / 60 分钟都按选的时间关闭', (tester) async {
      for (final m in [15, 45, 60]) {
        final (c, _) = await _setup(tester);
        _ctl(c).setTimer(m);
        await _ctl(c).start();
        await _wait(tester, Duration(minutes: m) - const Duration(seconds: 2));
        expect(_s(c).phase, SoothePhase.playing, reason: '$m');
        await _wait(tester, const Duration(seconds: 3));
        expect(_s(c).phase, SoothePhase.ended, reason: '$m');
        expect(_s(c).playedMinutes, m);
        c.dispose();
      }
    });

    testWidgets('「再播 15 分钟」：同一种声音、当前音量、3 秒淡入，15 分钟后停；不改定时选项；可以反复点', (tester) async {
      final (c, engine) = await _setup(tester);
      _ctl(c).setTimer(15);
      await _ctl(c).selectSound(SootheSound.shush);
      _ctl(c).setVolume(.4);
      await _ctl(c).start();
      await _wait(tester, const Duration(minutes: 15, seconds: 1));
      expect(_s(c).phase, SoothePhase.ended);
      _ctl(c).setTimer(45);
      engine.volumes.clear();
      await _ctl(c).playExtra();
      expect(_s(c).phase, SoothePhase.playing);
      expect(_s(c).remaining, const Duration(minutes: 15));
      expect(_s(c).timerMinutes, 45);
      expect(engine.loaded, SootheSound.shush);
      expect(engine.volumes.first, 0);
      await tester.pump(const Duration(seconds: 4));
      expect(engine.volume, closeTo(.4, 1e-9));
      await _wait(tester, const Duration(minutes: 15));
      expect(_s(c).phase, SoothePhase.ended);
      expect(_s(c).playedMinutes, 15);
      await _ctl(c).playExtra();
      expect(_s(c).phase, SoothePhase.playing);
      await _ctl(c).stop();
    });

    testWidgets('播放中改定时：从现在起重新算', (tester) async {
      final (c, _) = await _setup(tester);
      await _ctl(c).start();
      await _wait(tester, const Duration(minutes: 10));
      _ctl(c).setTimer(15);
      expect(_s(c).remaining, const Duration(minutes: 15));
      await _wait(tester, const Duration(minutes: 15, seconds: 1));
      expect(_s(c).phase, SoothePhase.ended);
      expect(_s(c).playedMinutes, 25);
    });

    testWidgets('点停止：马上停、去掉锁屏控件，回到未播放', (tester) async {
      final (c, engine) = await _setup(tester);
      await _ctl(c).start();
      await _wait(tester, const Duration(minutes: 1));
      await _ctl(c).stop();
      expect(_s(c).phase, SoothePhase.idle);
      expect(engine.calls.last, 'stop');
      await _wait(tester, const Duration(minutes: 40));
      expect(_s(c).phase, SoothePhase.idle);
    });

    testWidgets('播放中换声音：接着播，不重新计时', (tester) async {
      final (c, engine) = await _setup(tester);
      await _ctl(c).start();
      await _wait(tester, const Duration(minutes: 5));
      await _ctl(c).selectSound(SootheSound.white);
      await tester.pump(const Duration(seconds: 1));
      expect(engine.loaded, SootheSound.white);
      expect(engine.playing, isTrue);
      expect(_s(c).remaining.inSeconds, inInclusiveRange(24 * 60 + 58, 25 * 60));
      await _ctl(c).stop();
    });
  });

  group('打断和锁屏控件（定稿边界规则）', () {
    testWidgets('来电打断：剩余时间停住；结束后不自动继续，点继续才接着播（3 秒淡入）', (tester) async {
      final (c, engine) = await _setup(tester);
      await _ctl(c).start();
      await _wait(tester, const Duration(minutes: 10));
      engine.emit(SootheEngineEvent.interrupted);
      expect(_s(c).phase, SoothePhase.paused);
      expect(_s(c).remaining, const Duration(minutes: 20));
      await _wait(tester, const Duration(minutes: 30));
      expect(_s(c).phase, SoothePhase.paused);
      expect(_s(c).remaining, const Duration(minutes: 20));
      expect(engine.playing, isFalse);
      engine.volumes.clear();
      await _ctl(c).resume();
      expect(_s(c).phase, SoothePhase.playing);
      expect(engine.volumes.first, 0);
      await _wait(tester, const Duration(minutes: 20, seconds: 1));
      expect(_s(c).phase, SoothePhase.ended);
      expect(_s(c).playedMinutes, 30);
    });

    testWidgets('定时结束后在锁屏上点播放 = 再播 15 分钟', (tester) async {
      final (c, engine) = await _setup(tester);
      await _ctl(c).start();
      await _wait(tester, const Duration(minutes: 30, seconds: 1));
      expect(_s(c).phase, SoothePhase.ended);
      engine.emit(SootheEngineEvent.remotePlay);
      await tester.pump();
      expect(_s(c).phase, SoothePhase.playing);
      expect(_s(c).remaining, const Duration(minutes: 15));
      expect(_s(c).timerMinutes, 30);
      await _ctl(c).stop();
    });

    testWidgets('锁屏上点暂停 = 暂停；再点播放 = 继续', (tester) async {
      final (c, engine) = await _setup(tester);
      await _ctl(c).start();
      await _wait(tester, const Duration(minutes: 2));
      engine.emit(SootheEngineEvent.remotePause);
      expect(_s(c).phase, SoothePhase.paused);
      engine.emit(SootheEngineEvent.remotePlay);
      await tester.pump();
      expect(_s(c).phase, SoothePhase.playing);
      expect(_s(c).remaining, const Duration(minutes: 28));
      await _ctl(c).stop();
    });

    testWidgets('没在播时锁屏上点播放：不认，马上暂停回去', (tester) async {
      final (c, engine) = await _setup(tester);
      expect(_s(c).phase, SoothePhase.idle); // 打开哄睡页
      engine.emit(SootheEngineEvent.remotePlay);
      await tester.pump();
      expect(_s(c).phase, SoothePhase.idle);
      expect(engine.calls.last, 'pause');
    });

    testWidgets('声音加载失败：显示出错状态，自动听哭声恢复', (tester) async {
      final (c, engine) = await _setup(tester);
      engine.failLoad = true;
      await _ctl(c).start();
      expect(_s(c).phase, SoothePhase.error);
      expect(_listen(c).heldForSoothe, isFalse);
    });
  });

  group('播放期间暂停自动听哭声', () {
    testWidgets('播放中暂停；停止、播完、被打断后恢复；再播时重新暂停', (tester) async {
      final (c, engine) = await _setup(tester);
      expect(c.read(autoListenControllerProvider), isNot(AutoListenStatus.paused));
      await _ctl(c).start();
      expect(_listen(c).heldForSoothe, isTrue);
      expect(c.read(autoListenControllerProvider), AutoListenStatus.paused);

      // 播完
      await _wait(tester, const Duration(minutes: 30, seconds: 1));
      expect(_listen(c).heldForSoothe, isFalse);
      // 再播
      await _ctl(c).playExtra();
      expect(_listen(c).heldForSoothe, isTrue);
      // 打断
      engine.emit(SootheEngineEvent.interrupted);
      expect(_listen(c).heldForSoothe, isFalse);
      await _ctl(c).resume();
      expect(_listen(c).heldForSoothe, isTrue);
      // 停止
      await _ctl(c).stop();
      expect(_listen(c).heldForSoothe, isFalse);
    });

    testWidgets('播放中录音页结束时调 resume()：仍然保持暂停，不打开麦克风', (tester) async {
      final (c, _) = await _setup(tester);
      await _ctl(c).start();
      await _listen(c).pause();
      _listen(c).resume();
      expect(_listen(c).heldForSoothe, isTrue);
      expect(c.read(autoListenControllerProvider), AutoListenStatus.paused);
      await _ctl(c).stop();
    });
  });

  group('QA #38 修复', () {
    testWidgets('第 1 条：录音页暂停了监听时，声音被打断 / 停止也不会重新打开麦克风；录音页结束后才恢复', (tester) async {
      final (c, engine) = await _setup(tester);
      await _ctl(c).start();
      await _listen(c).pause(); // 录音页打开
      engine.emit(SootheEngineEvent.interrupted);
      expect(_listen(c).heldForSoothe, isFalse);
      expect(_listen(c).wantsMic, isFalse, reason: '录音页还开着');
      expect(c.read(autoListenControllerProvider), AutoListenStatus.paused);
      await _ctl(c).resume();
      await _ctl(c).stop();
      expect(_listen(c).wantsMic, isFalse);
      _listen(c).resume(); // 录音页关闭
      expect(_listen(c).wantsMic, isTrue);
      // 反过来：先播放、再进出录音页，声音还在播就一直不听
      await _ctl(c).start();
      await _listen(c).pause();
      _listen(c).resume();
      expect(_listen(c).wantsMic, isFalse);
      await _ctl(c).stop();
      expect(_listen(c).wantsMic, isTrue);
    });

    testWidgets('第 2 条：只要求调低音量的提示音：调低到 30%，结束后恢复，不暂停', (tester) async {
      final (c, engine) = await _setup(tester);
      await _ctl(c).start();
      await _wait(tester, const Duration(seconds: 10));
      expect(engine.volume, closeTo(.30, 1e-9));
      engine.emit(SootheEngineEvent.duck);
      expect(_s(c).phase, SoothePhase.playing);
      expect(engine.playing, isTrue);
      expect(engine.volume, closeTo(.30 * sootheDuckFactor, 1e-9));
      await _wait(tester, const Duration(seconds: 2));
      expect(engine.volume, closeTo(.30 * sootheDuckFactor, 1e-9));
      engine.emit(SootheEngineEvent.unduck);
      expect(engine.volume, closeTo(.30, 1e-9));
      expect(_listen(c).heldForSoothe, isTrue);
      await _ctl(c).stop();
    });

    testWidgets('第 4 条：拿不到音频焦点 → 出错状态，不显示播放中；播放中途出错也一样', (tester) async {
      final (c, engine) = await _setup(tester);
      engine.grantFocus = false;
      await _ctl(c).start();
      expect(_s(c).phase, SoothePhase.error);
      expect(engine.calls, isNot(contains('play')));
      expect(_listen(c).heldForSoothe, isFalse);
      engine.grantFocus = true;
      await _ctl(c).start();
      expect(_s(c).phase, SoothePhase.playing);
      engine.emit(SootheEngineEvent.failed);
      expect(_s(c).phase, SoothePhase.error);
      expect(_listen(c).heldForSoothe, isFalse);
      await _wait(tester, const Duration(minutes: 1));
      expect(_s(c).phase, SoothePhase.error);
    });

    testWidgets('第 5 条：改系统时间不影响剩余时间（用单调时钟）', (tester) async {
      final (c, _) = await _setup(tester);
      await _ctl(c).start();
      await _wait(tester, const Duration(minutes: 10));
      final before = _s(c).remaining;
      final src = AppClock.source;
      AppClock.source = () => src().add(const Duration(hours: 3)); // 用户把系统时间往后调 3 小时
      await tester.pump(const Duration(seconds: 1));
      expect(_s(c).phase, SoothePhase.playing);
      expect(_s(c).remaining.inSeconds, inInclusiveRange(before.inSeconds - 2, before.inSeconds));
      AppClock.source = () => src().subtract(const Duration(hours: 3)); // 往前调
      await tester.pump(const Duration(seconds: 1));
      expect(_s(c).remaining.inSeconds, inInclusiveRange(before.inSeconds - 3, before.inSeconds - 1));
      await _wait(tester, const Duration(minutes: 20));
      expect(_s(c).phase, SoothePhase.ended);
      expect(_s(c).playedMinutes, 30);
    });

    testWidgets('第 6 条：播放中换声音先淡出到 0 再换，再淡入；音量不跳变', (tester) async {
      final (c, engine) = await _setup(tester);
      await _ctl(c).start();
      await _wait(tester, const Duration(seconds: 10));
      engine.volumes.clear();
      engine.calls.clear();
      await _ctl(c).selectSound(SootheSound.brown);
      expect(engine.loaded, SootheSound.pink, reason: '还在淡出旧声音');
      await tester.pump(const Duration(milliseconds: 300));
      expect(engine.loaded, SootheSound.pink);
      expect(engine.volume, lessThan(.30));
      await tester.pump(const Duration(seconds: 2));
      expect(engine.loaded, SootheSound.brown);
      expect(engine.volume, closeTo(.30, 1e-9));
      final loadAt = engine.calls.indexOf('load:brown');
      expect(loadAt, isNonNegative);
      // 换之前音量已经降到 0
      final v = engine.volumes;
      final zero = v.indexOf(0);
      expect(zero, isNonNegative);
      for (var i = 1; i < v.length; i++) {
        expect((v[i] - v[i - 1]).abs(), lessThanOrEqualTo(.07), reason: '第 $i 步 ${v[i - 1]} → ${v[i]}');
      }
      expect(_s(c).remaining.inSeconds, greaterThan(29 * 60));
      await _ctl(c).stop();
    });

    testWidgets('第 7 条：每次开始 / 继续 / 再播之前都重新激活音频会话（切回播放类别）', (tester) async {
      final (c, engine) = await _setup(tester);
      List<String> beforePlays() => [
        for (var i = 0; i < engine.calls.length; i++)
          if (engine.calls[i] == 'play') engine.calls.sublist(0, i).lastWhere((x) => x == 'activate' || x == 'play', orElse: () => ''),
      ];
      await _ctl(c).start();
      engine.emit(SootheEngineEvent.interrupted);
      // 中间去录了一次音（录音插件改了音频类别）
      await _listen(c).pause();
      _listen(c).resume();
      await _ctl(c).resume();
      await _wait(tester, const Duration(minutes: 31));
      await _ctl(c).playExtra();
      final plays = engine.calls.where((x) => x == 'play').length;
      expect(plays, 3);
      expect(beforePlays(), everyElement('activate'));
      await _ctl(c).stop();
    });
  });
}
