import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:honghong/core/prefs.dart';
import 'package:honghong/core/providers.dart';
import 'package:honghong/core/theme/app_theme.dart';
import 'package:honghong/data/db/app_database.dart';
import 'package:honghong/domain/health/health.dart';
import 'package:honghong/domain/health/health_channel.dart';
import 'package:honghong/domain/models/cry_cause.dart';
import 'package:honghong/domain/models/cry_context.dart';
import 'package:honghong/domain/predictor/cry_predictor.dart';
import 'package:honghong/features/cry/result_page.dart';
import 'package:honghong/features/health/health_providers.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  Future<void> phone(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 1400) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  Future<AppDatabase> prepare(
    WidgetTester tester, {
    required HealthSnapshot? health,
    CryCause top = CryCause.diaper,
    DateTime? birth,
  }) async {
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('zh_CN');
    final sp = await SharedPreferences.getInstance();
    final db = AppDatabase.memory();
    const babyId = 'baby-1';
    await db.into(db.babies).insert(BabiesCompanion.insert(
          id: babyId,
          nickname: '小米粒',
          birthDate: birth ?? DateTime(2026, 9, 20),
        ));
    final at = DateTime(2026, 11, 2, 15);
    final ctx = CryContext(at: at, babyAgeMonths: 1.4, health: health);
    final prediction = Prediction(
      ranked: [
        CauseScore(top, 0.55, '测试'),
        CauseScore(CryCause.hungry, 0.3, '测试'),
        CauseScore(CryCause.sleepy, 0.15, '测试'),
      ],
      predictorVersion: 'test',
    );
    const id = 'evt-1';
    await db.into(db.cryEvents).insert(CryEventsCompanion.insert(
          id: id,
          babyId: babyId,
          startedAt: at,
          durationMs: 4000,
          contextJson: jsonEncode(ctx.toJson()),
          predictionJson: jsonEncode(prediction.toJson()),
          predictorVersion: 'test',
        ));

    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, __) => const ResultPage(eventId: id)),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          prefsProvider.overrideWithValue(sp),
          databaseProvider.overrideWithValue(db),
          healthChannelProvider.overrideWithValue(HealthChannel.dev),
        ],
        child: MaterialApp.router(
          theme: AppTheme.day,
          routerConfig: router,
        ),
      ),
    );
    await settle(tester, 24);
    return db;
  }

  testWidgets('老记录无快照：无横幅，有建议卡', (tester) async {
    await phone(tester);
    final db = await prepare(tester, health: null);
    expect(find.byKey(const Key('medical-banner-urgent')), findsNothing);
    expect(find.byKey(const Key('medical-banner-advise')), findsNothing);
    expect(find.textContaining('建议先试'), findsOneWidget);
    await unmount(tester);
    await tester.runAsync(db.close);
  });

  testWidgets('建议就医：advise 横幅 + 保留建议卡 + 原因卡收起', (tester) async {
    await phone(tester);
    final at = DateTime(2026, 11, 2, 15);
    final db = await prepare(
      tester,
      health: HealthSnapshot(
        at: at,
        temps: [
          TempReading(at: at.subtract(const Duration(hours: 1)), celsius: 37.8, site: TempSite.armpit),
        ],
      ),
      birth: DateTime(2026, 5, 1),
    );
    expect(find.byKey(const Key('medical-banner-advise')), findsOneWidget);
    expect(find.byKey(const Key('medical-banner-urgent')), findsNothing);
    expect(find.textContaining('建议先试'), findsOneWidget);
    expect(find.textContaining('怎么判断'), findsNothing);
    expect(find.byKey(const Key('stage-tip')), findsNothing);
    expect(find.byKey(const Key('soothe-entry')), findsNothing);
    await unmount(tester);
    await tester.runAsync(db.close);
  });

  testWidgets('请尽快就医：urgent 横幅、无建议卡、无尿布', (tester) async {
    await phone(tester);
    final at = DateTime(2026, 11, 2, 15);
    final db = await prepare(
      tester,
      health: HealthSnapshot(
        at: at,
        temps: [
          TempReading(at: at.subtract(const Duration(hours: 1)), celsius: 38.3, site: TempSite.rectal),
        ],
      ),
      birth: DateTime(2026, 9, 20),
      top: CryCause.diaper,
    );
    expect(find.byKey(const Key('medical-banner-urgent')), findsOneWidget);
    expect(find.textContaining('建议先试'), findsNothing);
    expect(find.textContaining('尿布'), findsNothing);
    expect(find.byKey(const Key('stage-tip')), findsNothing);
    await unmount(tester);
    await tester.runAsync(db.close);
  });
}
