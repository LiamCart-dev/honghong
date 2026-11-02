import 'package:flutter_test/flutter_test.dart';
import 'package:honghong/domain/health/health.dart';
import 'package:honghong/domain/stages/cry_stage.dart';
import 'package:honghong/features/stage/stage_copy.dart';

void main() {
  group('kHealthConfig', () {
    test('症状面板含其他共 12 项、急症 6（设计稿 HTML；文案「11」漏计其他）', () {
      // 设计稿 04-symptom-*.html：普通 6（含其他）+ 急症 6 = 12。
      // Issue/计划写「11」未计「其他」；以 v3 HTML 为准保留「其他」。
      expect(kHealthConfig.symptoms, hasLength(12));
      expect(kHealthConfig.symptoms, contains(Symptom.other));
      expect(kHealthConfig.dangerSymptoms, hasLength(6));
      expect(
        kHealthConfig.dangerSymptoms,
        containsAll({
          Symptom.breathingHard,
          Symptom.lowEnergy,
          Symptom.poorFeeding,
          Symptom.seizure,
          Symptom.nonBlanchingRash,
          Symptom.biliousOrBloodyVomit,
        }),
      );
    });

    test('发烧阈值：腋 37.5 / 肛 38；部位映射正确', () {
      expect(kHealthConfig.feverC[FeverTier.axillary], 37.5);
      expect(kHealthConfig.feverC[FeverTier.rectal], 38.0);
      expect(kHealthConfig.siteTier[TempSite.armpit], FeverTier.axillary);
      expect(kHealthConfig.siteTier[TempSite.rectal], FeverTier.rectal);
    });

    test('首页横幅配置：仅 urgent、保留 24h', () {
      expect(kHealthConfig.homeBannerOnlyUrgent, isTrue);
      expect(kHealthConfig.homeBannerRetain, const Duration(hours: 24));
    });

    test('有 pendingReview → 正式渠道隐藏；dev/ci 可见并带角标', () {
      expect(kHealthConfig.hasPendingReview, isTrue);
      expect(
        isHealthFeatureVisible(config: kHealthConfig, channel: HealthChannel.stable),
        isFalse,
      );
      expect(
        isHealthFeatureVisible(config: kHealthConfig, channel: HealthChannel.dev),
        isTrue,
      );
      expect(
        healthPendingReviewBadge(config: kHealthConfig, channel: HealthChannel.ci),
        '文案待审核',
      );
      expect(
        healthPendingReviewBadge(config: kHealthConfig, channel: HealthChannel.stable),
        isNull,
      );
    });

    test('resolveHealthChannel：后缀与 dart-define', () {
      expect(resolveHealthChannel(versionName: '0.1.12'), HealthChannel.stable);
      expect(resolveHealthChannel(versionName: '0.1.12-dev'), HealthChannel.dev);
      expect(resolveHealthChannel(versionName: '0.1.12-ci'), HealthChannel.ci);
      expect(resolveHealthChannel(versionName: '0.1.12-dev+99'), HealthChannel.dev);
      expect(
        resolveHealthChannel(versionName: '0.1.12-dev', hhChannelDefine: 'stable'),
        HealthChannel.stable,
      );
      expect(
        resolveHealthChannel(versionName: '0.1.12', hhChannelDefine: 'CI'),
        HealthChannel.ci,
      );
    });

    test('stage_copy 五处急症相关字符串字面不变且指向 HealthStageLegacyCopy', () {
      expect(stageEmergencyLine, HealthStageLegacyCopy.stageEmergencyLine);
      expect(
        stageEmergencyLine,
        '出现这些情况请立即就医：3 个月以下宝宝体温 ≥38℃；呼吸急促或费力、口唇发紫；抽搐；拒奶或吃奶明显变差；精神很差、叫不醒。',
      );
      expect(
        HealthStageLegacyCopy.cryingPeakFeverSeeDoctor,
        '体温 ≥38℃（3 个月以下要立即就医）',
      );
      expect(
        HealthStageLegacyCopy.teethingKeyFact,
        '出牙不会引起 38℃ 及以上的发烧。体温 ≥38℃ 时不要当成出牙，请及时就医。',
      );
      expect(HealthStageLegacyCopy.teethingFeverSeeDoctor, '体温 ≥38℃');
      expect(
        HealthStageLegacyCopy.growthSpurtFeverSeeDoctor,
        '体温 ≥38℃，或者吃奶无力、精神差',
      );

      // stageCopy 实际引用
      expect(
        stageCopy[CryStage.cryingPeak]!.seeDoctor,
        contains(HealthStageLegacyCopy.cryingPeakFeverSeeDoctor),
      );
      expect(
        stageCopy[CryStage.teething]!.keyFact,
        HealthStageLegacyCopy.teethingKeyFact,
      );
      expect(
        stageCopy[CryStage.teething]!.seeDoctor,
        contains(HealthStageLegacyCopy.teethingFeverSeeDoctor),
      );
      expect(
        stageCopy[CryStage.growthSpurt]!.seeDoctor,
        contains(HealthStageLegacyCopy.growthSpurtFeverSeeDoctor),
      );
    });
  });
}
