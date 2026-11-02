import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/domain/context_builder.dart';
import 'package:honghong/domain/models/care_log_type.dart';
import 'package:honghong/domain/health/health_config.dart';
import 'package:honghong/domain/health/health_models.dart';
import 'package:honghong/domain/models/cry_cause.dart';
import 'package:honghong/domain/models/cry_context.dart';
import 'package:honghong/domain/predictor/cry_predictor.dart';
import 'package:honghong/domain/predictor/rule_based_predictor.dart';

void main() {
  final p = RuleBasedPredictor();
  const audio = AudioFeatures();
  final afternoon = DateTime(2026, 10, 13, 14);

  test('概率归一且降序', () async {
    final r = await p.predict(audio, CryContext(at: afternoon, babyAgeMonths: 1));
    final sum = r.ranked.fold<double>(0, (a, s) => a + s.probability);
    expect(sum, closeTo(1, 1e-9));
    expect(r.ranked.length, CryCause.values.length);
    for (var i = 1; i < r.ranked.length; i++) {
      expect(r.ranked[i - 1].probability >= r.ranked[i].probability, isTrue);
    }
    expect(r.predictorVersion, 'rule-2');
  });

  test('久未喂奶时"饿"排第一', () async {
    final r = await p.predict(
      audio,
      CryContext(
        at: afternoon,
        babyAgeMonths: 1,
        sinceLastFeed: const Duration(hours: 4),
        sinceLastSleepEnd: const Duration(minutes: 20),
        sinceLastDiaper: const Duration(minutes: 30),
      ),
    );
    expect(r.ranked.first.cause, CryCause.hungry);
  });

  test('刚喂完没拍嗝时"胀气"排第一', () async {
    final r = await p.predict(
      audio,
      CryContext(
        at: afternoon,
        babyAgeMonths: 1,
        sinceLastFeed: const Duration(minutes: 15),
        sinceLastSleepEnd: const Duration(minutes: 30),
        sinceLastDiaper: const Duration(minutes: 20),
      ),
    );
    expect(r.ranked.first.cause, CryCause.gas);
  });

  test('夜里醒了很久时"困"排第一', () async {
    final r = await p.predict(
      audio,
      CryContext(
        at: DateTime(2026, 10, 13, 22),
        babyAgeMonths: 2,
        sinceLastFeed: const Duration(minutes: 90),
        sinceLastBurp: const Duration(minutes: 70),
        sinceLastSleepEnd: const Duration(minutes: 150),
        sinceLastDiaper: const Duration(minutes: 40),
      ),
    );
    expect(r.ranked.first.cause, CryCause.sleepy);
  });

  test('个性化先验会改变排序', () async {
    final ctx = CryContext(at: afternoon, babyAgeMonths: 1);
    final base = await p.predict(audio, ctx);
    final personal = await RuleBasedPredictor(priors: {CryCause.holdMe: 3})
        .predict(audio, ctx);
    expect(personal.ranked.first.cause, CryCause.holdMe);
    expect(base.ranked.first.cause, isNot(CryCause.holdMe));
  });

  test('Prediction JSON 往返', () async {
    final r = await p.predict(audio, CryContext(at: afternoon, babyAgeMonths: 1));
    final back = Prediction.decode(jsonEncode(r.toJson()));
    expect(back.predictorVersion, r.predictorVersion);
    expect(back.ranked.map((s) => s.cause), r.ranked.map((s) => s.cause));
  });

  test('buildCryContext 计算间隔和睡眠状态', () {
    final now = DateTime(2026, 10, 13, 12);
    final ctx = buildCryContext(
      now: now,
      birthDate: DateTime(2026, 9, 13),
      latest: {
        CareLogType.feed: LastLog(now.subtract(const Duration(hours: 2))),
        CareLogType.sleep: LastLog(now.subtract(const Duration(hours: 1))),
      },
    );
    expect(ctx.sinceLastFeed, const Duration(hours: 2));
    expect(ctx.isSleeping, isTrue);
    expect(ctx.sinceLastDiaper, isNull);
    expect(ctx.babyAgeMonths, closeTo(1, 0.05));
  });

  group('rule-2 健康快照', () {
    Map<CryCause, double> probs(Prediction r) =>
        {for (final s in r.ranked) s.cause: s.probability};

    CryContext baseCtx({HealthSnapshot? health}) => CryContext(
          at: afternoon,
          babyAgeMonths: 4,
          sinceLastFeed: const Duration(hours: 2),
          sinceLastSleepEnd: const Duration(minutes: 40),
          sinceLastDiaper: const Duration(minutes: 30),
          health: health,
        );

    test('无健康快照：与空快照概率一致（等同原 rule-1 路径）', () async {
      final none = await p.predict(audio, baseCtx());
      final empty = await p.predict(audio, baseCtx(health: HealthSnapshot(at: afternoon)));
      expect(probs(none), probs(empty));
      expect(none.predictorVersion, 'rule-2');
      expect(none.ranked.first.cause, isNot(CryCause.diaper)); // 基线不是不舒服第一
    });

    test('窗口内发烧 → 不舒服概率上升且 why 用配置文案', () async {
      final baseline = probs(await p.predict(audio, baseCtx()));
      final withFever = await p.predict(
        audio,
        baseCtx(
          health: HealthSnapshot(
            at: afternoon,
            temps: [
              TempReading(at: afternoon.subtract(const Duration(hours: 1)), celsius: 37.5, site: TempSite.armpit),
            ],
          ),
        ),
      );
      expect(probs(withFever)[CryCause.diaper]! > baseline[CryCause.diaper]!, isTrue);
      final diaper = withFever.ranked.firstWhere((s) => s.cause == CryCause.diaper);
      expect(diaper.reason, kHealthConfig.copy.predictorWhyFever);
    });

    test('刚好窗外发烧 → 不加分', () async {
      final baseline = probs(await p.predict(audio, baseCtx()));
      final outside = probs(await p.predict(
        audio,
        baseCtx(
          health: HealthSnapshot(
            at: afternoon,
            temps: [
              TempReading(
                at: afternoon.subtract(const Duration(hours: 24, minutes: 1)),
                celsius: 38.0,
                site: TempSite.armpit,
              ),
            ],
          ),
        ),
      ));
      expect(outside, baseline);
    });

    test('阈值下不发烧 → 不加分', () async {
      final baseline = probs(await p.predict(audio, baseCtx()));
      final under = probs(await p.predict(
        audio,
        baseCtx(
          health: HealthSnapshot(
            at: afternoon,
            temps: [
              TempReading(at: afternoon, celsius: 37.4, site: TempSite.armpit),
            ],
          ),
        ),
      ));
      expect(under, baseline);
    });

    test('窗口内药品加分；补充剂不加', () async {
      final baseline = probs(await p.predict(audio, baseCtx()));
      final drug = await p.predict(
        audio,
        baseCtx(
          health: HealthSnapshot(
            at: afternoon,
            meds: [MedReading(at: afternoon.subtract(const Duration(hours: 2)), kind: MedKind.drug, name: '退烧药')],
          ),
        ),
      );
      expect(probs(drug)[CryCause.diaper]! > baseline[CryCause.diaper]!, isTrue);
      expect(
        drug.ranked.firstWhere((s) => s.cause == CryCause.diaper).reason,
        kHealthConfig.copy.predictorWhyMed,
      );

      final supp = probs(await p.predict(
        audio,
        baseCtx(
          health: HealthSnapshot(
            at: afternoon,
            meds: [MedReading(at: afternoon, kind: MedKind.supplement, name: '维生素D')],
          ),
        ),
      ));
      expect(supp, baseline);
    });

    test('发烧+用药：组合 why 文案', () async {
      final r = await p.predict(
        audio,
        baseCtx(
          health: HealthSnapshot(
            at: afternoon,
            temps: [TempReading(at: afternoon, celsius: 37.5, site: TempSite.armpit)],
            meds: [MedReading(at: afternoon, kind: MedKind.drug)],
          ),
        ),
      );
      expect(
        r.ranked.firstWhere((s) => s.cause == CryCause.diaper).reason,
        kHealthConfig.copy.predictorWhyFeverAndMed,
      );
    });

    test('注入假配置：更大 boost 时不舒服可排第一', () async {
      final hot = RuleBasedPredictor(
        healthConfig: HealthConfig(
          feverC: kHealthConfig.feverC,
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
          uncomfortableBoost: 5.0,
          otherDampWhenUncomfortable: 0.5,
        ),
      );
      final r = await hot.predict(
        audio,
        baseCtx(
          health: HealthSnapshot(
            at: afternoon,
            temps: [TempReading(at: afternoon, celsius: 37.5, site: TempSite.armpit)],
          ),
        ),
      );
      expect(r.ranked.first.cause, CryCause.diaper);
    });
  });

}
