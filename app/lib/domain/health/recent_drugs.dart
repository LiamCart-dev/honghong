/// 最近用药药名（ADR-0002：补充剂不算）。
library;

import 'package:honghong/domain/health/health_models.dart';

/// 从用药读数里取最近用过的药名，最多 [limit] 个，按时间新→旧去重。
/// 只计 [MedKind.drug]；空名忽略。
List<String> recentDrugNames(Iterable<MedReading> meds, {int limit = 3}) {
  final seen = <String>{};
  final out = <String>[];
  final sorted = [...meds]..sort((a, b) => b.at.compareTo(a.at));
  for (final m in sorted) {
    if (m.kind != MedKind.drug) continue;
    final n = m.name.trim();
    if (n.isEmpty) continue;
    if (seen.add(n)) {
      out.add(n);
      if (out.length >= limit) break;
    }
  }
  return out;
}

/// 5 分钟内是否已有同类用药（药品要求药名相同；补充剂同样比名）。
MedReading? duplicateMedWithin({
  required Iterable<MedReading> meds,
  required DateTime at,
  required MedKind kind,
  required String name,
  Duration window = const Duration(minutes: 5),
  String? excludeId,
}) {
  final n = name.trim();
  for (final m in meds) {
    if (m.kind != kind) continue;
    if (m.name.trim() != n) continue;
    final d = m.at.difference(at).abs();
    if (d <= window) return m;
  }
  return null;
}
