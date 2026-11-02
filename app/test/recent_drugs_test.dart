import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/domain/health/health_models.dart';
import 'package:honghong/domain/health/recent_drugs.dart';

void main() {
  final t0 = DateTime(2026, 11, 2, 12);

  test('补充剂不算最近用药；药品去重最多 3 个', () {
    final meds = [
      MedReading(at: t0, kind: MedKind.supplement, name: '维生素D'),
      MedReading(at: t0.subtract(const Duration(hours: 1)), kind: MedKind.drug, name: '布洛芬'),
      MedReading(at: t0.subtract(const Duration(hours: 2)), kind: MedKind.drug, name: '美林'),
      MedReading(at: t0.subtract(const Duration(hours: 3)), kind: MedKind.drug, name: '布洛芬'),
      MedReading(at: t0.subtract(const Duration(hours: 4)), kind: MedKind.drug, name: '泰诺'),
      MedReading(at: t0.subtract(const Duration(hours: 5)), kind: MedKind.drug, name: '旧药'),
    ];
    expect(recentDrugNames(meds), ['布洛芬', '美林', '泰诺']);
  });

  test('5 分钟内同名药品算重复', () {
    final meds = [
      MedReading(at: t0, kind: MedKind.drug, name: '布洛芬'),
    ];
    expect(
      duplicateMedWithin(meds: meds, at: t0.add(const Duration(minutes: 3)), kind: MedKind.drug, name: '布洛芬'),
      isNotNull,
    );
    expect(
      duplicateMedWithin(meds: meds, at: t0.add(const Duration(minutes: 6)), kind: MedKind.drug, name: '布洛芬'),
      isNull,
    );
  });
}
