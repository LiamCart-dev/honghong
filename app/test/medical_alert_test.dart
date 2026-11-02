import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/domain/health/health.dart';
import 'package:honghong/domain/stages/cry_stage.dart' show monthStartDay;

void main() {
  final now = DateTime(2026, 11, 2, 12);

  HealthConfig configWith({double feverAx = 37.5, double feverRec = 38.0}) {
    return HealthConfig(
      feverC: {
        FeverTier.axillary: feverAx,
        FeverTier.rectal: feverRec,
      },
      siteTier: kHealthConfig.siteTier,
      urgentUnderAgeMonths: kHealthConfig.urgentUnderAgeMonths,
      highFeverCUnder6mo: kHealthConfig.highFeverCUnder6mo,
      anyAgeVeryHighC: kHealthConfig.anyAgeVeryHighC,
      lowTempCUnder3mo: kHealthConfig.lowTempCUnder3mo,
      feverWindow: kHealthConfig.feverWindow,
      medicationWindow: kHealthConfig.medicationWindow,
      symptomWindow: kHealthConfig.symptomWindow,
      feverEpisodeLookback: kHealthConfig.feverEpisodeLookback,
      feverEpisodeGap: kHealthConfig.feverEpisodeGap,
      feverEscalateAfter: kHealthConfig.feverEscalateAfter,
      homeBannerRetain: kHealthConfig.homeBannerRetain,
      homeBannerOnlyUrgent: kHealthConfig.homeBannerOnlyUrgent,
      recordableC: kHealthConfig.recordableC,
      fahrenheitGuess: kHealthConfig.fahrenheitGuess,
      symptoms: kHealthConfig.symptoms,
      dangerSymptoms: kHealthConfig.dangerSymptoms,
      copy: kHealthConfig.copy,
      pendingReviewNotes: const [],
    );
  }

  group('MedicalAlert.evaluate', () {
    test('无记录 → none', () {
      final r = MedicalAlert.evaluate(
        snapshot: HealthSnapshot(at: now),
        ageDays: 100,
      );
      expect(r.level, MedicalAlertLevel.none);
      expect(r.reasons, isEmpty);
    });

    test('腋温阈值：t-0.1 不触发，t 触发 A1', () {
      const t = 37.5;
      final cfg = configWith(feverAx: t);
      final under = MedicalAlert.evaluate(
        snapshot: HealthSnapshot(
          at: now,
          temps: [TempReading(at: now, celsius: t - 0.1, site: TempSite.armpit)],
        ),
        ageDays: monthStartDay(4), // 满 3 月，避免 U1
        config: cfg,
      );
      expect(under.level, MedicalAlertLevel.none);

      final at = MedicalAlert.evaluate(
        snapshot: HealthSnapshot(
          at: now,
          temps: [TempReading(at: now, celsius: t, site: TempSite.armpit)],
        ),
        ageDays: monthStartDay(4),
        config: cfg,
      );
      expect(at.level, MedicalAlertLevel.advise);
      expect(at.reasons.map((e) => e.code), contains('A1'));
    });

    test('肛温阈值：t-0.1 不触发，t 触发 A1', () {
      const t = 38.0;
      final cfg = configWith(feverRec: t);
      final under = MedicalAlert.evaluate(
        snapshot: HealthSnapshot(
          at: now,
          temps: [TempReading(at: now, celsius: t - 0.1, site: TempSite.rectal)],
        ),
        ageDays: monthStartDay(4),
        config: cfg,
      );
      expect(under.level, MedicalAlertLevel.none);

      final at = MedicalAlert.evaluate(
        snapshot: HealthSnapshot(
          at: now,
          temps: [TempReading(at: now, celsius: t, site: TempSite.rectal)],
        ),
        ageDays: monthStartDay(4),
        config: cfg,
      );
      expect(at.level, MedicalAlertLevel.advise);
      expect(at.reasons.any((e) => e.code == 'A1'), isTrue);
    });

    test('U1：未满 3 个月 + 发烧 → urgent', () {
      final r = MedicalAlert.evaluate(
        snapshot: HealthSnapshot(
          at: now,
          temps: [TempReading(at: now, celsius: 37.5, site: TempSite.armpit)],
        ),
        ageDays: monthStartDay(3) - 1,
      );
      expect(r.level, MedicalAlertLevel.urgent);
      expect(r.reasons.map((e) => e.code), contains('U1'));
    });

    test('满 3 个月刚好：发烧只 advise（不 U1）', () {
      final r = MedicalAlert.evaluate(
        snapshot: HealthSnapshot(
          at: now,
          temps: [TempReading(at: now, celsius: 37.5, site: TempSite.armpit)],
        ),
        ageDays: monthStartDay(3),
      );
      expect(r.level, MedicalAlertLevel.advise);
      expect(r.reasons.map((e) => e.code), isNot(contains('U1')));
    });

    test('U5：任一急症症状 → urgent', () {
      for (final s in kHealthConfig.dangerSymptoms) {
        final r = MedicalAlert.evaluate(
          snapshot: HealthSnapshot(
            at: now,
            symptoms: [
              SymptomReading(at: now, symptoms: {s}),
            ],
          ),
          ageDays: 200,
        );
        expect(r.level, MedicalAlertLevel.urgent, reason: s.name);
        expect(r.reasons.map((e) => e.code), contains('U5'));
      }
    });

    test('普通症状 → advise A2', () {
      final r = MedicalAlert.evaluate(
        snapshot: HealthSnapshot(
          at: now,
          symptoms: [
            SymptomReading(at: now, symptoms: {Symptom.cough}),
          ],
        ),
        ageDays: 200,
      );
      expect(r.level, MedicalAlertLevel.advise);
      expect(r.reasons.map((e) => e.code), contains('A2'));
    });

    test('药品 → A3；补充剂不算', () {
      final drug = MedicalAlert.evaluate(
        snapshot: HealthSnapshot(
          at: now,
          meds: [MedReading(at: now, kind: MedKind.drug, name: '退热药')],
        ),
        ageDays: 200,
      );
      expect(drug.level, MedicalAlertLevel.advise);
      expect(drug.reasons.map((e) => e.code), contains('A3'));

      final supp = MedicalAlert.evaluate(
        snapshot: HealthSnapshot(
          at: now,
          meds: [MedReading(at: now, kind: MedKind.supplement, name: '维生素D')],
        ),
        ageDays: 200,
      );
      expect(supp.level, MedicalAlertLevel.none);
    });

    test('U2：满 3 未满 6 月 ≥39 → urgent', () {
      final r = MedicalAlert.evaluate(
        snapshot: HealthSnapshot(
          at: now,
          temps: [TempReading(at: now, celsius: 39.0, site: TempSite.armpit)],
        ),
        ageDays: monthStartDay(4),
      );
      expect(r.level, MedicalAlertLevel.urgent);
      expect(r.reasons.map((e) => e.code), contains('U2'));
    });

    test('U3：任何月龄 ≥40 → urgent', () {
      final r = MedicalAlert.evaluate(
        snapshot: HealthSnapshot(
          at: now,
          temps: [TempReading(at: now, celsius: 40.0, site: TempSite.rectal)],
        ),
        ageDays: monthStartDay(12),
      );
      expect(r.level, MedicalAlertLevel.urgent);
      expect(r.reasons.map((e) => e.code), contains('U3'));
    });

    test('U4：未满 3 月最近读数 <36 → urgent；只看最近一条', () {
      final r = MedicalAlert.evaluate(
        snapshot: HealthSnapshot(
          at: now,
          temps: [
            TempReading(at: now.subtract(const Duration(hours: 2)), celsius: 37.0, site: TempSite.armpit),
            TempReading(at: now, celsius: 35.5, site: TempSite.armpit),
          ],
        ),
        ageDays: 20,
      );
      expect(r.level, MedicalAlertLevel.urgent);
      expect(r.reasons.map((e) => e.code), contains('U4'));

      // 最近一条正常，即使更早偏低 → 不 U4
      final ok = MedicalAlert.evaluate(
        snapshot: HealthSnapshot(
          at: now,
          temps: [
            TempReading(at: now.subtract(const Duration(hours: 2)), celsius: 35.0, site: TempSite.armpit),
            TempReading(at: now, celsius: 36.5, site: TempSite.armpit),
          ],
        ),
        ageDays: 20,
      );
      expect(ok.reasons.map((e) => e.code), isNot(contains('U4')));
    });

    test('U7：同一次发烧跨度 ≥72h → urgent', () {
      // 相邻间隔 ≤ feverEpisodeGap(24h) 才能算同一次；72h 跨度至少 4 个点
      final r = MedicalAlert.evaluate(
        snapshot: HealthSnapshot(
          at: now,
          temps: [
            for (final h in [72, 48, 24, 0])
              TempReading(
                at: now.subtract(Duration(hours: h)),
                celsius: 37.5,
                site: TempSite.armpit,
              ),
          ],
        ),
        ageDays: monthStartDay(8),
      );
      expect(r.level, MedicalAlertLevel.urgent);
      expect(r.reasons.map((e) => e.code), contains('U7'));
    });

    test('发烧窗口外的旧读数不触发', () {
      final r = MedicalAlert.evaluate(
        snapshot: HealthSnapshot(
          at: now,
          temps: [
            TempReading(
              at: now.subtract(const Duration(hours: 25)),
              celsius: 39.0,
              site: TempSite.armpit,
            ),
          ],
        ),
        ageDays: monthStartDay(4),
      );
      expect(r.level, MedicalAlertLevel.none);
    });

    test('urgent 与 advise 同时命中时取 urgent', () {
      final r = MedicalAlert.evaluate(
        snapshot: HealthSnapshot(
          at: now,
          temps: [TempReading(at: now, celsius: 37.5, site: TempSite.armpit)],
          meds: [MedReading(at: now, kind: MedKind.drug)],
          symptoms: [
            SymptomReading(at: now, symptoms: {Symptom.seizure}),
          ],
        ),
        ageDays: 10,
      );
      expect(r.level, MedicalAlertLevel.urgent);
      expect(r.reasons.map((e) => e.code), contains('U5'));
      // advise 原因不混入 urgent 结果
      expect(r.reasons.map((e) => e.code), isNot(contains('A3')));
    });

    test('阈值 null 的档位不触发发烧', () {
      final cfg = HealthConfig(
        feverC: const {FeverTier.axillary: null, FeverTier.rectal: null},
        siteTier: kHealthConfig.siteTier,
        urgentUnderAgeMonths: 3,
        highFeverCUnder6mo: null,
        anyAgeVeryHighC: null,
        lowTempCUnder3mo: null,
        feverWindow: const Duration(hours: 24),
        medicationWindow: const Duration(hours: 24),
        symptomWindow: const Duration(hours: 24),
        feverEpisodeLookback: const Duration(days: 7),
        feverEpisodeGap: const Duration(hours: 24),
        feverEscalateAfter: null,
        homeBannerRetain: const Duration(hours: 24),
        homeBannerOnlyUrgent: true,
        recordableC: kHealthConfig.recordableC,
        fahrenheitGuess: kHealthConfig.fahrenheitGuess,
        symptoms: kHealthConfig.symptoms,
        dangerSymptoms: kHealthConfig.dangerSymptoms,
        copy: kHealthConfig.copy,
        pendingReviewNotes: const [],
      );
      final r = MedicalAlert.evaluate(
        snapshot: HealthSnapshot(
          at: now,
          temps: [TempReading(at: now, celsius: 39.0, site: TempSite.armpit)],
        ),
        ageDays: 10,
        config: cfg,
      );
      expect(r.level, MedicalAlertLevel.none);
    });
  });
}
