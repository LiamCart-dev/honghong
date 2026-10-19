import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/features/diary/diary_flow.dart';
import 'package:honghong/features/diary/diary_providers.dart';
import 'package:honghong/services/audio/auto_listen.dart';
import 'package:honghong/services/diary/voice_capture.dart';

import 'diary_flow_test.dart' show FakeApi, Clock, okJson;
import 'helpers.dart';

/// 启动可控的假识别：start() 要等 [gate] 完成，用来模拟首次权限弹窗、连接慢
class GateVoice implements VoiceCapture {
  final gate = Completer<bool>();
  int starts = 0;
  int stops = 0;
  int cancels = 0;
  @override
  bool failed = false;
  @override
  String? errorCode;
  @override
  String? get requestId => null;

  @override
  Future<bool> start({required void Function(String partial) onPartial, void Function(double level)? onLevel, void Function()? onError}) {
    starts++;
    return gate.future;
  }

  @override
  Future<String> stop() async {
    stops++;
    return '慢启动后的一句话';
  }

  @override
  Future<void> cancel() async => cancels++;
}

/// 记录自动听哭被暂停/恢复的次数，不碰真实麦克风
class FakeAutoListen extends AutoListenController {
  static int pauses = 0;
  static int resumes = 0;
  @override
  AutoListenStatus build() => AutoListenStatus.off;
  @override
  Future<void> pause() async => pauses++;
  @override
  void resume() => resumes++;
}

void main() {
  late FakeApi api;
  late GateVoice voice;
  late Clock clock;

  setUp(() {
    api = FakeApi(json: okJson);
    FakeAutoListen.pauses = 0;
    FakeAutoListen.resumes = 0;
  });

  // 注意：GateVoice 必须在 testWidgets 体内创建。在 setUp 里创建的 Completer 不在假时钟 zone 里，
  // 调用 complete 后的续体不会随 pump 执行。
  Future<void> open(WidgetTester tester) async {
    voice = GateVoice();
    clock = Clock();
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpApp(tester, prefs: const {kDiaryGenderPrompted: true}, overrides: [
      diaryApiProvider.overrideWithValue(api),
      voiceCaptureProvider.overrideWithValue(voice),
      cloudVoiceCaptureProvider.overrideWithValue(null),
      diaryClockProvider.overrideWithValue(clock.call),
      autoListenControllerProvider.overrideWith(FakeAutoListen.new),
    ]);
    await tester.ensureVisible(find.byKey(const Key('diary-entry')));
    await tester.tap(find.byKey(const Key('diary-entry')));
    await settle(tester, 10);
  }

  testWidgets('日记页暂停首页自动听哭，离开日记页时恢复', (tester) async {
    AutoListenController.enabledInThisEnv = true;
    addTearDown(() => AutoListenController.enabledInThisEnv = false);
    await open(tester);
    expect(FakeAutoListen.pauses, 1);
    expect(FakeAutoListen.resumes, 0);
    await unmount(tester);
    expect(FakeAutoListen.resumes, 1);
  });

  testWidgets('启动未完成时松手：等启动结束后正常结束识别，不留孤立会话', (tester) async {
    await open(tester);
    final g = await tester.startGesture(tester.getCenter(find.byKey(const Key('diary-mic'))));
    await settle(tester, 3);
    clock.t = clock.t.add(const Duration(seconds: 2));
    await g.up();
    await settle(tester, 3);
    expect(voice.stops, 0, reason: '启动还没完成，不能提前 stop');
    voice.gate.complete(true);
    await settle(tester, 10);
    expect(voice.stops, 1);
    expect(api.calls, ['voice:慢启动后的一句话']);
    await unmount(tester);
  });

  testWidgets('启动期间被系统打断（权限弹窗的 pointer cancel）：放弃本次，不当成松手也不留会话', (tester) async {
    await open(tester);
    final g = await tester.startGesture(tester.getCenter(find.byKey(const Key('diary-mic'))));
    await settle(tester, 3);
    clock.t = clock.t.add(const Duration(seconds: 2));
    await g.cancel();
    await settle(tester, 3);
    expect(voice.stops, 0);
    voice.gate.complete(true); // 用户在权限弹窗里点了允许
    await settle(tester, 10);
    expect(voice.stops, 0, reason: '不能把打断当成松手去处理结果');
    expect(voice.cancels, greaterThanOrEqualTo(1), reason: '启动后的会话必须被收起');
    expect(api.calls, isEmpty);
    expect(find.text('已取消，请再按住说一次'), findsOneWidget);
    expect(find.text('按住说话'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('启动失败时不会重复处理：走原有失败兜底（屏 9）', (tester) async {
    await open(tester);
    voice.gate.complete(false);
    await tester.tap(find.byKey(const Key('diary-mic')));
    await settle(tester, 3);
    expect(voice.starts, 1);
    await unmount(tester);
  });
}
