import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/domain/health/health.dart';

void main() {
  final at = DateTime(2026, 11, 2, 12);

  test('往返序列化保留体温/用药/症状', () {
    final snap = HealthSnapshot(
      at: at,
      temps: [TempReading(at: at.subtract(const Duration(hours: 1)), celsius: 38.3, site: TempSite.rectal)],
      meds: [MedReading(at: at.subtract(const Duration(hours: 2)), kind: MedKind.drug, name: '美林')],
      symptoms: [
        SymptomReading(at: at.subtract(const Duration(minutes: 30)), symptoms: {Symptom.cough, Symptom.seizure}),
      ],
    );
    final json = healthSnapshotToJson(snap);
    final back = healthSnapshotFromJson(json)!;
    expect(back.at, at);
    expect(back.temps.single.celsius, 38.3);
    expect(back.meds.single.name, '美林');
    expect(back.symptoms.single.symptoms, containsAll([Symptom.cough, Symptom.seizure]));
  });

  test('研究上传剔除 health 字段', () {
    final ctx = {
      'at': at.toIso8601String(),
      'baby_age_months': 1.5,
      'health': healthSnapshotToJson(HealthSnapshot(at: at)),
      'hour': 12,
    };
    final stripped = stripHealthFromResearchContext(Map<String, dynamic>.from(ctx));
    expect(stripped.containsKey('health'), isFalse);
    expect(stripped['baby_age_months'], 1.5);
    expect(ctx.containsKey('health'), isTrue); // 原 map 不动
  });

  test('坏数据 / 缺 health → null', () {
    expect(healthSnapshotFromJson(null), isNull);
    expect(healthSnapshotFromJson({'temps': []}), isNull);
  });
}
