import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/data/repositories/health_log_repository.dart';
import 'package:honghong/domain/health/health_channel.dart';
import 'package:honghong/domain/health/health_models.dart';
import 'package:honghong/features/health/health_providers.dart';

import 'helpers.dart';

void main() {
  void ignoreHomeOverflow() {
    final old = FlutterError.onError;
    FlutterError.onError = (details) {
      final m = details.exceptionAsString();
      if (m.contains('overflowed') && !m.contains('med_sheet') && !m.contains('symptom_sheet') && !m.contains('log_detail')) {
        return;
      }
      old?.call(details);
    };
    addTearDown(() => FlutterError.onError = old);
  }

  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 1100) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('用药面板：填药名可保存；补充剂可选', (tester) async {
    ignoreHomeOverflow();
    await phone(tester);
    final db = await pumpApp(tester, overrides: [
      healthChannelProvider.overrideWithValue(HealthChannel.ci),
    ]);
    await tester.tap(find.byKey(const Key('health-entry-health_med')));
    await settle(tester, 12);
    expect(find.text('记用药'), findsOneWidget);
    expect(find.textContaining('不给用药建议'), findsWidgets);

    await tester.tap(find.text('＋ 填写药名'));
    await settle(tester, 6);
    await tester.enterText(find.byType(TextField).last, '布洛芬');
    await tester.tap(find.text('确定'));
    await settle(tester, 6);

    await tester.tap(find.byKey(const Key('med-save')));
    await settle(tester, 12);
    expect(find.textContaining('用药 · 布洛芬'), findsOneWidget);

    final all = await tester.runAsync(() async {
      final baby = await db.select(db.babies).getSingle();
      return HealthLogRepository(db).list(babyId: baby.id);
    });
    expect(all!.single.medKind, MedKind.drug.name);
    expect(all.single.medName, '布洛芬');

    await unmount(tester);
    await tester.runAsync(db.close);
  });

  testWidgets('症状面板：多选 + 急症显示急症框', (tester) async {
    ignoreHomeOverflow();
    await phone(tester);
    final db = await pumpApp(tester, overrides: [
      healthChannelProvider.overrideWithValue(HealthChannel.dev),
    ]);
    await tester.tap(find.byKey(const Key('health-entry-health_symptom')));
    await settle(tester, 12);
    expect(find.text('记症状'), findsOneWidget);

    await tester.tap(find.byKey(Key('sym-${Symptom.cough.name}')));
    await tester.pump();
    expect(find.byKey(const Key('sym-emergency')), findsNothing);

    await tester.tap(find.byKey(Key('sym-${Symptom.seizure.name}')));
    await settle(tester, 8);
    expect(find.byKey(const Key('sym-emergency')), findsOneWidget);

    await tester.tap(find.byKey(const Key('sym-save')));
    await settle(tester, 12);
    expect(find.textContaining('症状'), findsWidgets);

    final all = await tester.runAsync(() async {
      final baby = await db.select(db.babies).getSingle();
      return HealthLogRepository(db).list(babyId: baby.id);
    });
    final set = HealthLogRepository.decodeSymptoms(all!.single.symptoms);
    expect(set, containsAll([Symptom.cough, Symptom.seizure]));

    await unmount(tester);
    await tester.runAsync(db.close);
  });

  testWidgets('全部记录：全部/护理/健康筛选', (tester) async {
    ignoreHomeOverflow();
    await phone(tester);
    final db = await pumpApp(tester, overrides: [
      healthChannelProvider.overrideWithValue(HealthChannel.ci),
    ]);
    // 先记一条体温
    await tester.tap(find.byKey(const Key('health-entry-health_temp')));
    await settle(tester, 10);
    await tester.tap(find.byKey(const Key('temp-plus')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('temp-save')));
    await settle(tester, 10);

    await tester.tap(find.text('查看全部记录 ›'));
    await settle(tester, 12);
    expect(find.text('全部'), findsOneWidget);
    expect(find.text('护理'), findsOneWidget);
    expect(find.text('健康'), findsOneWidget);

    await tester.tap(find.text('健康'));
    await settle(tester, 8);
    expect(find.textContaining('体温'), findsWidgets);

    await tester.tap(find.text('护理'));
    await settle(tester, 8);
    // 默认宝宝无护理记录
    expect(find.textContaining('还没有记录'), findsOneWidget);

    await unmount(tester);
    await tester.runAsync(db.close);
  });
}
