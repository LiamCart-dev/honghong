/// 健康记录领域枚举（#1 / 原 #28）。纯 Dart，无 Flutter 依赖。
library;

/// 记录种类。
enum HealthKind { temperature, medication, symptom }

/// 体温测量部位。第一版只开放腋温、肛温（ADR-0001）。
enum TempSite { armpit, rectal }

/// 发烧阈值档位：腋温档 / 肛温档，不互相折算。
enum FeverTier { axillary, rectal }

/// 用药种类：补充剂不算「最近用药」（ADR-0002）。
enum MedKind { drug, supplement }

/// 症状清单（设计稿 12 项，含「其他」；计划文案「11」未计其他）。急症集合见 [HealthConfig.dangerSymptoms]。
enum Symptom {
  cough,
  runnyNose,
  vomit,
  diarrhea,
  rash,
  other,
  // 急症组（显示文案见 HealthConfig / HealthCopy）
  breathingHard,
  lowEnergy,
  poorFeeding,
  seizure,
  nonBlanchingRash,
  biliousOrBloodyVomit,
}


/// 一条体温读数（评估用）。
class TempReading {
  const TempReading({required this.at, required this.celsius, required this.site});
  final DateTime at;
  final double celsius;
  final TempSite site;
}

/// 一条用药记录（评估用）。
class MedReading {
  const MedReading({required this.at, required this.kind, this.name = ''});
  final DateTime at;
  final MedKind kind;
  final String name;
}

/// 一条症状记录（评估用；一次可多选）。
class SymptomReading {
  const SymptomReading({required this.at, required this.symptoms});
  final DateTime at;
  final Set<Symptom> symptoms;
}

/// 某时刻的健康快照：只含判断需要的事实，不含药名剂量备注等（那些留给 UI/存储）。
class HealthSnapshot {
  const HealthSnapshot({
    required this.at,
    this.temps = const [],
    this.meds = const [],
    this.symptoms = const [],
  });
  final DateTime at;
  final List<TempReading> temps;
  final List<MedReading> meds;
  final List<SymptomReading> symptoms;
}
