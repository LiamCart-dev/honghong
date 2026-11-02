import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/data/db/app_database.dart';
import 'package:honghong/data/repositories/health_log_repository.dart';
import 'package:honghong/domain/health/health_models.dart';
import 'package:sqlite3/sqlite3.dart';

/// v5 → v6（健康记录）：老数据不丢、新表可读写。
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory dir;
  late File file;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('hh_hmig');
    file = File('${dir.path}/v5.sqlite');
  });
  tearDown(() => dir.deleteSync(recursive: true));

  int sec(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

  void seedV5() {
    final raw = sqlite3.open(file.path);
    raw.execute(File('test/fixtures/schema_v5.sql').readAsStringSync());
    raw.execute('PRAGMA user_version = 5');
    final t = DateTime(2026, 10, 13, 8);
    raw.execute(
      "INSERT INTO babies (id, nickname, birth_date, updated_at, dirty, gender) VALUES ('b1', '小糖', ?, ?, 1, 'girl')",
      [sec(DateTime(2026, 7, 1)), sec(t)],
    );
    raw.execute(
      "INSERT INTO care_logs (id, baby_id, type, started_at, ended_at, detail, updated_by, updated_at, deleted, dirty, source) "
      "VALUES ('l1', 'b1', 'feed', ?, ?, '{\"ml\":120}', 'dad', ?, 0, 0, 'quick')",
      [sec(t), sec(t.add(const Duration(minutes: 15))), sec(t)],
    );
    raw.execute(
      "INSERT INTO cry_events (id, baby_id, started_at, duration_ms, context_json, prediction_json, predictor_version) "
      "VALUES ('c1', 'b1', ?, 8000, '{}', '{}', 'rule-v1')",
      [sec(t)],
    );
    raw.execute(
      "INSERT INTO diary_inputs (id, baby_id, input_type, raw_text, age_in_days, parse_status, prompt_version) "
      "VALUES ('di1', 'b1', 'text', '喂了奶', 100, 'ok', 'v1')",
    );
    raw.close();
  }

  test('v5 → v6 老数据不丢，health_logs 可读写', () async {
    seedV5();
    final db = AppDatabase(NativeDatabase(file));
    addTearDown(db.close);

    expect((await db.select(db.babies).get()).single.nickname, '小糖');
    expect((await db.select(db.babies).get()).single.gender, 'girl');
    expect((await db.select(db.careLogs).get()).single.id, 'l1');
    expect((await db.select(db.cryEvents).get()).single.id, 'c1');
    expect((await db.select(db.diaryInputs).get()).single.id, 'di1');

    expect(await db.select(db.healthLogs).get(), isEmpty);
    final repo = HealthLogRepository(db);
    final hid = await repo.add(
      babyId: 'b1',
      kind: HealthKind.temperature,
      at: DateTime(2026, 10, 13, 10),
      tempC: 37.5,
      tempSite: TempSite.armpit,
    );
    final row = await repo.byId(hid);
    expect(row!.tempC, 37.5);
    expect(row.tempSite, 'armpit');
    expect(row.dirty, isTrue);

    final idx = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='index' AND name='health_logs_baby_at'",
        )
        .get();
    expect(idx, isNotEmpty);
    expect(
      await db.customSelect('PRAGMA user_version').map((r) => r.read<int>('user_version')).getSingle(),
      6,
    );
  });

  test('迁移后的结构与全新安装一致', () async {
    seedV5();
    final migrated = AppDatabase(NativeDatabase(file));
    final fresh = AppDatabase.memory();
    addTearDown(() async {
      await migrated.close();
      await fresh.close();
    });
    Future<Map<String, Set<String>>> cols(AppDatabase db) async {
      final m = <String, Set<String>>{};
      for (final t in db.allTables) {
        final rows = await db.customSelect('PRAGMA table_info(${t.actualTableName})').get();
        m[t.actualTableName] =
            rows.map((r) => '${r.read<String>('name')}:${r.read<String>('type')}:${r.read<int>('notnull')}').toSet();
      }
      return m;
    }

    expect(await cols(migrated), await cols(fresh));
    await expectLater(
      migrated.into(migrated.healthLogs).insert(
            HealthLogsCompanion.insert(
              id: 'x',
              babyId: 'nope',
              kind: 'temperature',
              at: DateTime(2026),
            ),
          ),
      throwsA(anything),
    );
  });
}
