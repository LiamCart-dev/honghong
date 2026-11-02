/// [MedicalAlert.evaluate]：纯函数，无 IO / 无 Flutter。规则见 Issue #1 / 审核表。
library;

import 'package:honghong/domain/health/health_config.dart';
import 'package:honghong/domain/health/health_models.dart';

/// 就医提示级别。
enum MedicalAlertLevel {
  /// 无提示
  none,

  /// 「可能不舒服，建议就医」
  advise,

  /// 「请尽快就医」
  urgent,
}

/// 一条触发原因（用于横幅原因列表；UI 再拼相对时间等）。
class MedicalAlertReason {
  const MedicalAlertReason({required this.code, required this.label});

  /// 稳定码：如 `U1`、`A2`，便于测试与埋点（第一版不埋点）。
  final String code;

  /// 给家长看的原因短句（审核 5.4–5.5d 口径；不含相对时间占位时用通用描述）。
  final String label;

  @override
  String toString() => '$code:$label';
}

/// [MedicalAlert.evaluate] 的返回值；静态 [evaluate] 为纯函数入口。
class MedicalAlert {
  const MedicalAlert({required this.level, required this.reasons});
  final MedicalAlertLevel level;
  final List<MedicalAlertReason> reasons;

  bool get isUrgent => level == MedicalAlertLevel.urgent;
  bool get isAdvise => level == MedicalAlertLevel.advise;

  /// 根据 [snapshot]、宝宝日龄 [ageDays]、配置 [config] 计算提示级别与原因。
  ///
  /// 窗口取配置；缺省窗口时不触发对应规则。急症症状命中 → 直接 urgent。
  /// 「建议」与「请尽快」同时命中时取「请尽快」。
  static MedicalAlert evaluate({
    required HealthSnapshot snapshot,
    required int ageDays,
    HealthConfig config = kHealthConfig,
  }) {
    final urgent = <MedicalAlertReason>[];
    final advise = <MedicalAlertReason>[];

    final feverWindow = config.feverWindow;
    final symptomWindow = config.symptomWindow;
    final medWindow = config.medicationWindow;

    // —— 急症症状 U5 ——
    if (symptomWindow != null) {
      final since = snapshot.at.subtract(symptomWindow);
      for (final s in snapshot.symptoms) {
        if (s.at.isBefore(since) || s.at.isAfter(snapshot.at)) continue;
        for (final id in s.symptoms) {
          if (config.dangerSymptoms.contains(id)) {
            final label = config.copy.symptomLabels[id] ?? id.name;
            urgent.add(MedicalAlertReason(code: 'U5', label: label));
          }
        }
      }
    }

    // 窗口内体温（按时间升序，便于取最近与算发作）
    final tempsInFeverWindow = <TempReading>[];
    if (feverWindow != null) {
      final since = snapshot.at.subtract(feverWindow);
      for (final t in snapshot.temps) {
        if (!t.at.isBefore(since) && !t.at.isAfter(snapshot.at)) {
          tempsInFeverWindow.add(t);
        }
      }
    }
    tempsInFeverWindow.sort((a, b) => a.at.compareTo(b.at));

    final feverInWindow =
        tempsInFeverWindow.where(config.isFeverReading).toList();
    final hasFeverInWindow = feverInWindow.isNotEmpty;

    // —— U1 未满 N 月 + 发烧 ——
    final underMonths = config.urgentUnderAgeMonths;
    if (hasFeverInWindow &&
        underMonths != null &&
        config.underAgeMonths(ageDays, underMonths)) {
      urgent.add(
        MedicalAlertReason(
          code: 'U1',
          label: config.copy.panelUrgentUnder3mo,
        ),
      );
    }

    // —— U2 满 3 未满 6 月，读数 ≥39（保守）——
    // TODO(#1-review)
    final high39 = config.highFeverCUnder6mo;
    if (high39 != null &&
        config.atLeastAgeMonths(ageDays, 3) &&
        config.underAgeMonths(ageDays, 6)) {
      if (tempsInFeverWindow.any((t) => t.celsius >= high39)) {
        urgent.add(
          MedicalAlertReason(
            code: 'U2',
            label: config.copy.panelUrgentHigh39Under6mo,
          ),
        );
      }
    }

    // —— U3 任何月龄 ≥40（保守）——
    // TODO(#1-review)
    final high40 = config.anyAgeVeryHighC;
    if (high40 != null &&
        tempsInFeverWindow.any((t) => t.celsius >= high40)) {
      urgent.add(
        MedicalAlertReason(
          code: 'U3',
          label: config.copy.panelUrgentHigh40,
        ),
      );
    }

    // —— U4 未满 3 月，窗口内最近一条 <36 ——
    final lowCut = config.lowTempCUnder3mo;
    if (lowCut != null &&
        underMonths != null &&
        config.underAgeMonths(ageDays, underMonths) &&
        tempsInFeverWindow.isNotEmpty) {
      final latest = tempsInFeverWindow.last;
      if (latest.celsius < lowCut) {
        urgent.add(
          MedicalAlertReason(
            code: 'U4',
            label: config.copy.panelLowTempUnder3mo,
          ),
        );
      }
    }

    // —— U7 同一次发烧 ≥72h（保守）——
    // TODO(#1-review)
    final escalateAfter = config.feverEscalateAfter;
    if (escalateAfter != null && hasFeverInWindow) {
      final episode = _currentFeverEpisode(
        temps: snapshot.temps,
        at: snapshot.at,
        config: config,
      );
      if (episode != null) {
        final span = episode.last.at.difference(episode.first.at);
        if (span >= escalateAfter) {
          urgent.add(
            const MedicalAlertReason(
              code: 'U7',
              label: '发烧已持续 3 天或更久，请尽快带宝宝去医院。',
            ),
          );
        }
      }
    }

    // —— A1 发烧 ——
    if (hasFeverInWindow) {
      final latestFever = feverInWindow.last;
      final tier = config.tierFor(latestFever.site);
      final label = switch (tier) {
        FeverTier.rectal => config.copy.panelFeverRectal,
        FeverTier.axillary || null => config.copy.panelFeverAxillary,
      };
      advise.add(MedicalAlertReason(code: 'A1', label: label));
    }

    // —— A2 普通症状 ——
    if (symptomWindow != null) {
      final since = snapshot.at.subtract(symptomWindow);
      var hasOrdinary = false;
      for (final s in snapshot.symptoms) {
        if (s.at.isBefore(since) || s.at.isAfter(snapshot.at)) continue;
        for (final id in s.symptoms) {
          if (!config.dangerSymptoms.contains(id)) {
            hasOrdinary = true;
            break;
          }
        }
        if (hasOrdinary) break;
      }
      if (hasOrdinary) {
        advise.add(
          const MedicalAlertReason(
            code: 'A2',
            label: '记了不适症状，建议就医。',
          ),
        );
      }
    }

    // —— A3 药品 ——
    final medSince = snapshot.at.subtract(medWindow);
    final hasDrug = snapshot.meds.any(
      (m) =>
          m.kind == MedKind.drug &&
          !m.at.isBefore(medSince) &&
          !m.at.isAfter(snapshot.at),
    );
    if (hasDrug) {
      advise.add(
        const MedicalAlertReason(
          code: 'A3',
          label: '最近用过药，建议就医。',
        ),
      );
    }

    if (urgent.isNotEmpty) {
      return MedicalAlert(
        level: MedicalAlertLevel.urgent,
        reasons: _dedupeByCode(urgent),
      );
    }
    if (advise.isNotEmpty) {
      return MedicalAlert(
        level: MedicalAlertLevel.advise,
        reasons: _dedupeByCode(advise),
      );
    }
    return const MedicalAlert(level: MedicalAlertLevel.none, reasons: []);
  }

  /// 同一次发烧：从 [at] 往回看 [feverEpisodeLookback]，只保留发烧读数，
  /// 相邻间隔 ≤ [feverEpisodeGap] 连成一段；返回含最新发烧的那一段（时间升序）。
  static List<TempReading>? _currentFeverEpisode({
    required List<TempReading> temps,
    required DateTime at,
    required HealthConfig config,
  }) {
    final since = at.subtract(config.feverEpisodeLookback);
    final feverTemps = temps
        .where(
          (t) =>
              !t.at.isBefore(since) &&
              !t.at.isAfter(at) &&
              config.isFeverReading(t),
        )
        .toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    if (feverTemps.isEmpty) return null;

    final gap = config.feverEpisodeGap;
    final episode = <TempReading>[feverTemps.last];
    for (var i = feverTemps.length - 2; i >= 0; i--) {
      final newer = episode.first;
      final older = feverTemps[i];
      if (newer.at.difference(older.at) <= gap) {
        episode.insert(0, older);
      } else {
        break;
      }
    }
    return episode;
  }

  static List<MedicalAlertReason> _dedupeByCode(List<MedicalAlertReason> list) {
    final seen = <String>{};
    final out = <MedicalAlertReason>[];
    for (final r in list) {
      if (seen.add(r.code)) out.add(r);
    }
    return out;
  }
}
