/// 健康快照序列化 / 从日志构建（#1 PR-F）。纯 Dart。
library;

import 'package:honghong/domain/health/health_config.dart';
import 'package:honghong/domain/health/health_models.dart';

/// 写入 `CryContext.toJson()['health']` 的形状；研究上传时剔除该键。
Map<String, Object?> healthSnapshotToJson(HealthSnapshot s) => {
      'at': s.at.toIso8601String(),
      'temps': [
        for (final t in s.temps)
          {
            'at': t.at.toIso8601String(),
            'celsius': t.celsius,
            'site': t.site.name,
          },
      ],
      'meds': [
        for (final m in s.meds)
          {
            'at': m.at.toIso8601String(),
            'kind': m.kind.name,
            'name': m.name,
          },
      ],
      'symptoms': [
        for (final r in s.symptoms)
          {
            'at': r.at.toIso8601String(),
            'symptoms': [for (final x in r.symptoms) x.name],
          },
      ],
    };

/// 解析快照；缺字段或坏数据返回 null（老记录无横幅）。
HealthSnapshot? healthSnapshotFromJson(Object? raw) {
  if (raw is! Map) return null;
  final atRaw = raw['at'];
  final at = atRaw is String ? DateTime.tryParse(atRaw) : null;
  if (at == null) return null;

  final temps = <TempReading>[];
  final tempsRaw = raw['temps'];
  if (tempsRaw is List) {
    for (final item in tempsRaw) {
      if (item is! Map) continue;
      final tAt = DateTime.tryParse('${item['at']}');
      final c = item['celsius'];
      final site = TempSite.values.asNameMap()['${item['site']}'];
      if (tAt == null || c is! num || site == null) continue;
      temps.add(TempReading(at: tAt, celsius: c.toDouble(), site: site));
    }
  }

  final meds = <MedReading>[];
  final medsRaw = raw['meds'];
  if (medsRaw is List) {
    for (final item in medsRaw) {
      if (item is! Map) continue;
      final mAt = DateTime.tryParse('${item['at']}');
      final kind = MedKind.values.asNameMap()['${item['kind']}'];
      if (mAt == null || kind == null) continue;
      meds.add(MedReading(at: mAt, kind: kind, name: '${item['name'] ?? ''}'));
    }
  }

  final symptoms = <SymptomReading>[];
  final symRaw = raw['symptoms'];
  if (symRaw is List) {
    for (final item in symRaw) {
      if (item is! Map) continue;
      final sAt = DateTime.tryParse('${item['at']}');
      if (sAt == null) continue;
      final set = <Symptom>{};
      final list = item['symptoms'];
      if (list is List) {
        for (final n in list) {
          final s = Symptom.values.asNameMap()['$n'];
          if (s != null) set.add(s);
        }
      }
      if (set.isEmpty) continue;
      symptoms.add(SymptomReading(at: sAt, symptoms: set));
    }
  }

  return HealthSnapshot(at: at, temps: temps, meds: meds, symptoms: symptoms);
}

/// 研究上传用：拷贝 context map 并去掉 `health`（及历史别名）。
Map<String, dynamic> stripHealthFromResearchContext(Map<String, dynamic> context) {
  final out = Map<String, dynamic>.from(context);
  out.remove('health');
  out.remove('health_snapshot');
  return out;
}

/// 为评估拉取的回看窗口：覆盖发烧发作回看。
Duration healthSnapshotLookback(HealthConfig config) {
  var max = config.feverEpisodeLookback;
  void consider(Duration? d) {
    if (d != null && d > max) max = d;
  }
  consider(config.feverWindow);
  consider(config.medicationWindow);
  consider(config.symptomWindow);
  return max;
}
