// #37：录音页每 90ms 收到一次音量时，波形不能抛 "Cannot remove from a fixed-length list"，并且要跟着声音变。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/features/cry/recording_page.dart';

import 'helpers.dart';

/// 波形的 26 根竖条：宽 6 的 AnimatedContainer
List<double> _barHeights(WidgetTester tester) => [
  for (final w in tester.widgetList<AnimatedContainer>(
    find.descendant(of: find.byType(RecordingPage), matching: find.byWidgetPredicate((w) => w is AnimatedContainer && w.constraints?.maxWidth == 6)),
  ))
    w.constraints!.maxHeight,
];

void main() {
  testWidgets('读音量（#37）：每 90ms 一次回调，3 秒内没有异常，波形左移、最右边是最新音量', (tester) async {
    fixClock(tester, DateTime(2026, 10, 20, 14));
    // 手机尺寸（390×844），默认 800×600 的测试画布放不下录音页
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    // 先安静 1 秒（-60 dBFS），然后一直大声（-6 dBFS）
    var n = 0;
    final amp = Stream<double>.periodic(const Duration(milliseconds: 90), (_) => ++n <= 11 ? -60.0 : -6.0);
    final db = await pumpApp(
      tester,
      seed: (db) async => db.into(db.babies).insert(BabiesCompanionX.make('b1')),
      overrides: [recordingAmplitudeOverrideProvider.overrideWithValue(amp)],
    );
    await tester.tap(find.byKey(const Key('cry-button')));
    await tester.pump();
    expect(find.byType(RecordingPage), findsOneWidget);

    final errors = <Object>[];
    for (var i = 0; i < 34; i++) {
      await tester.pump(const Duration(milliseconds: 90));
      final e = tester.takeException();
      if (e != null) errors.add(e);
    }
    expect(errors, isEmpty, reason: '90ms 计时触发后不应有异常');
    expect(n, greaterThanOrEqualTo(30), reason: '音量回调确实触发了 30 次以上');

    final h = _barHeights(tester);
    expect(h, hasLength(26));
    // 最右边是大声：(-6 + 60) / 60 = 0.9 → 12 + 128 × 0.9
    expect(h.last, closeTo(12 + 128 * .9, .01));
    expect(h.where((x) => (x - (12 + 128 * .08)).abs() < .01), isEmpty, reason: '初始值 0.08 都被挤出去了（安静是 0.06，大声是 0.9）');

    await unmount(tester);
    await tester.runAsync(db.close);
  });
}
