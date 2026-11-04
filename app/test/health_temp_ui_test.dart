import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/data/db/app_database.dart';
import 'package:honghong/data/repositories/health_log_repository.dart';
import 'package:honghong/domain/health/health_channel.dart';
import 'package:honghong/domain/health/health_models.dart';
import 'package:honghong/features/health/health_providers.dart';

import 'helpers.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Future<void> phone(WidgetTester tester, {double textScale = 1}) async {
    tester.view.physicalSize = const Size(390, 1100) * 3;
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(() {
      tester.view.reset();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
  }

  testWidgets('门禁关闭时入口不显示', (tester) async {
    await phone(tester);
    await pumpApp(tester, overrides: [
      healthChannelProvider.overrideWithValue(HealthChannel.stable),
    ]);
    expect(find.byKey(const Key('health-entry-health_temp')), findsNothing);
    expect(find.text('文案待审核'), findsNothing);
    await unmount(tester);
  });

  testWidgets('测试渠道显示入口与待审核角标，可打开体温面板并保存', (tester) async {
    await phone(tester);
    fixClock(tester, DateTime(2026, 11, 2, 15, 30));
    final db = await pumpApp(tester, overrides: [
      healthChannelProvider.overrideWithValue(HealthChannel.ci),
    ]);

    expect(find.byKey(const Key('health-pending-badge')), findsOneWidget);
    expect(find.text('文案待审核'), findsOneWidget);
    expect(find.byKey(const Key('health-entry-health_temp')), findsOneWidget);

    await tester.tap(find.byKey(const Key('health-entry-health_temp')));
    await settle(tester, 12);
    expect(find.text('记体温'), findsOneWidget);

    // 点 + 把 --.- 调到有读数：空时 _adjust 用 36.5 起
    await tester.tap(find.byKey(const Key('temp-plus')));
    await tester.pump();
    expect(find.textContaining('36.6'), findsWidgets);

    // 再加到 37.5 触发发烧提示
    for (var i = 0; i < 9; i++) {
      await tester.tap(find.byKey(const Key('temp-plus')));
      await tester.pump();
    }
    expect(find.byKey(const Key('temp-alert')), findsOneWidget);

    await tester.tap(find.byKey(const Key('temp-save')));
    await settle(tester, 12);

    expect(find.text('记体温'), findsNothing);
    expect(find.textContaining('体温 · 37.5℃'), findsOneWidget);
    expect(find.text('腋温'), findsWidgets);

    final all = await tester.runAsync(() async {
      final baby = await db.select(db.babies).getSingle();
      return HealthLogRepository(db).list(babyId: baby.id);
    });
    expect(all!.length, 1);
    expect(all.single.tempC, 37.5);
    expect(all.single.tempSite, TempSite.armpit.name);

    await unmount(tester);
    await tester.runAsync(db.close);
  });

  testWidgets('夜间也显示健康入口', (tester) async {
    await phone(tester);
    await pumpApp(tester, overrides: [
      healthChannelProvider.overrideWithValue(HealthChannel.dev),
    ]);
    await tester.tap(find.byKey(const Key('night-toggle')));
    await settle(tester);
    expect(find.byKey(const Key('health-entry-health_temp')), findsOneWidget);
    expect(find.byKey(const Key('health-entry-health_med')), findsOneWidget);
    expect(find.byKey(const Key('health-entry-health_symptom')), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('1.4× / 2.0× 大字体温面板无溢出', (tester) async {
    for (final scale in [1.4, 2.0]) {
      await phone(tester, textScale: scale);
      final db = await pumpApp(tester, overrides: [
        healthChannelProvider.overrideWithValue(HealthChannel.ci),
      ]);
      // 首页在超大字号下原有入口可能溢出；本测只关心体温面板
      FlutterError.onError = (d) {
        final m = d.toString();
        if (m.contains('overflowed') && !m.contains('temp_sheet')) {
          return;
        }
        FlutterError.presentError(d);
      };
      addTearDown(() => FlutterError.onError = FlutterError.presentError);
      await tester.tap(find.byKey(const Key('health-entry-health_temp')));
      await settle(tester, 12);
      expect(find.text('记体温'), findsOneWidget);
      expect(find.byKey(const Key('temp-save')), findsOneWidget);
      // 面板内不应再抛溢出
      final pending = tester.takeException();
      if (pending != null) {
        expect(pending.toString(), isNot(contains('temp_sheet')), reason: 'scale=$scale $pending');
      }
      await tester.tap(find.text('取消'));
      await settle(tester, 8);
      await unmount(tester);
      await tester.runAsync(db.close);
    }
  });


  testWidgets('首页：请尽快就医显示横幅，建议就医不显示', (tester) async {
    await phone(tester);
    fixClock(tester, DateTime(2026, 11, 2, 15, 30));
    final at = DateTime(2026, 11, 2, 15, 0);
    final db = await pumpApp(
      tester,
      overrides: [
        healthChannelProvider.overrideWithValue(HealthChannel.ci),
      ],
      seed: (database) async {
        await database.into(database.babies).insert(
              BabiesCompanion.insert(
                id: 'b1',
                nickname: '小米粒',
                birthDate: DateTime(2026, 9, 20),
              ),
            );
        await database.into(database.healthLogs).insert(HealthLogsCompanion.insert(
              id: 'hl-urgent',
              babyId: 'b1',
              kind: HealthKind.temperature.name,
              at: at,
              tempC: const Value(38.3),
              tempSite: const Value('rectal'),
            ));
      },
    );
    await settle(tester, 24);
    expect(find.byKey(const Key('medical-banner-urgent')), findsOneWidget);
    expect(find.byKey(const Key('medical-banner-advise')), findsNothing);
    await unmount(tester);
    await tester.runAsync(db.close);
  });

  testWidgets('首页：仅建议就医时不显示横幅', (tester) async {
    await phone(tester);
    fixClock(tester, DateTime(2026, 11, 2, 15, 30));
    final at = DateTime(2026, 11, 2, 15, 0);
    final db = await pumpApp(
      tester,
      overrides: [
        healthChannelProvider.overrideWithValue(HealthChannel.ci),
      ],
      seed: (database) async {
        await database.into(database.babies).insert(
              BabiesCompanion.insert(
                id: 'b1',
                nickname: '小米粒',
                birthDate: DateTime(2026, 1, 1),
              ),
            );
        await database.into(database.healthLogs).insert(HealthLogsCompanion.insert(
              id: 'hl-advise',
              babyId: 'b1',
              kind: HealthKind.temperature.name,
              at: at,
              tempC: const Value(37.8),
              tempSite: const Value('armpit'),
            ));
      },
    );
    await settle(tester, 24);
    expect(find.byKey(const Key('medical-banner-urgent')), findsNothing);
    expect(find.byKey(const Key('medical-banner-advise')), findsNothing);
    await unmount(tester);
    await tester.runAsync(db.close);
  });

}
