import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/data/db/app_database.dart';
import 'package:honghong/data/repositories/baby_repository.dart';
import 'package:honghong/data/repositories/health_log_repository.dart';
import 'package:honghong/domain/health/health_models.dart';
import 'package:honghong/services/cloud/family_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_cloud.dart';

void main() {
  late AppDatabase db;
  late HealthLogRepository repo;
  late String babyId;

  setUp(() async {
    db = AppDatabase.memory();
    repo = HealthLogRepository(db);
    babyId = (await BabyRepository(db).ensureDefault()).id;
  });
  tearDown(() => db.close());

  test('增改删查与 watch', () async {
    final id = await repo.add(
      babyId: babyId,
      kind: HealthKind.medication,
      at: DateTime(2026, 11, 2, 8),
      medKind: MedKind.drug,
      medName: '一二三四五六七八九十一二三四五六七八九十超出',
      medDose: '5ml',
    );
    final row = await repo.byId(id);
    expect(row!.kind, 'medication');
    expect(row.medName, '一二三四五六七八九十一二三四五六七八九十');
    expect(row.medName!.length, 20);
    expect(row.medDose, '5ml');

    await repo.update(
      id,
      at: DateTime(2026, 11, 2, 9),
      medKind: MedKind.drug,
      medName: '短名',
      medDose: '2.5ml',
    );
    expect((await repo.byId(id))!.at, DateTime(2026, 11, 2, 9));
    expect((await repo.byId(id))!.medName, '短名');

    final sid = await repo.add(
      babyId: babyId,
      kind: HealthKind.symptom,
      at: DateTime(2026, 11, 2, 10),
      symptoms: {Symptom.cough, Symptom.seizure},
      symptomOther: '别的',
    );
    expect(
      HealthLogRepository.decodeSymptoms((await repo.byId(sid))!.symptoms),
      {Symptom.cough, Symptom.seizure},
    );

    final listed = await repo.list(
      babyId: babyId,
      from: DateTime(2026, 11, 2, 8, 30),
      to: DateTime(2026, 11, 2, 10),
    );
    expect(listed.map((e) => e.id), [id, sid]); // id updated to 9:00 still in range? id at 9:00, sid at 10
    // wait - listed from 8:30 includes updated id at 9 and sid at 10
    expect(listed.length, 2);

    await repo.softDelete(id);
    expect(await repo.list(babyId: babyId), hasLength(1));
    expect(await repo.list(babyId: babyId, includeDeleted: true), hasLength(2));

    expect(await repo.watch(babyId).first, hasLength(1));
  });

  test('补充剂与药品字段可存；list 按 at 升序', () async {
    await repo.add(
      babyId: babyId,
      kind: HealthKind.medication,
      at: DateTime(2026, 11, 2, 12),
      medKind: MedKind.supplement,
      medName: '维生素D',
    );
    await repo.add(
      babyId: babyId,
      kind: HealthKind.temperature,
      at: DateTime(2026, 11, 2, 11),
      tempC: 36.8,
      tempSite: TempSite.rectal,
    );
    final all = await repo.list(babyId: babyId);
    expect(all.first.kind, 'temperature');
    expect(all.last.medKind, 'supplement');
  });

  test('adoptBaby 把 health_logs 改挂到家庭宝宝，删旧宝宝不触发外键错误', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final sync = FamilySync(db, FakeCloud(FakeServer(), 'ua'), prefs);

    final localId = babyId;
    await repo.add(
      babyId: localId,
      kind: HealthKind.temperature,
      at: DateTime(2026, 11, 2, 7),
      tempC: 38.0,
      tempSite: TempSite.armpit,
    );

    const remoteId = 'family-baby-uuid';
    await sync.adoptBaby({
      'id': remoteId,
      'nickname': '家庭宝宝',
      'birth_date': '2026-07-01',
      'updated_at': DateTime(2026, 11, 2).toIso8601String(),
      'gender': 'boy',
    });

    expect((await db.select(db.babies).get()).single.id, remoteId);
    final health = await db.select(db.healthLogs).get();
    expect(health, hasLength(1));
    expect(health.single.babyId, remoteId);
    expect(await repo.list(babyId: remoteId), hasLength(1));
  });
}
