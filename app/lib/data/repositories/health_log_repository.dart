import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/app_clock.dart';
import '../../domain/health/health_models.dart';
import '../db/app_database.dart';

/// 健康记录本地仓库（#1 PR-B）。本 PR 不接云端同步。
class HealthLogRepository {
  HealthLogRepository(this._db);
  final AppDatabase _db;

  static const _maxMedName = 20;
  static const _maxMedDose = 20;
  static const _maxSymptomOther = 20;

  /// 新增一条。返回 id。
  Future<String> add({
    required String babyId,
    required HealthKind kind,
    required DateTime at,
    double? tempC,
    TempSite? tempSite,
    MedKind? medKind,
    String? medName,
    String? medDose,
    Set<Symptom>? symptoms,
    String? symptomOther,
    String? note,
  }) async {
    final id = const Uuid().v4();
    await _db.into(_db.healthLogs).insert(_companion(
          id: id,
          babyId: babyId,
          kind: kind,
          at: at,
          tempC: tempC,
          tempSite: tempSite,
          medKind: medKind,
          medName: medName,
          medDose: medDose,
          symptoms: symptoms,
          symptomOther: symptomOther,
          note: note,
          dirty: true,
        ));
    return id;
  }

  /// 修改已有记录（软字段全量覆盖可空列；标记 dirty）。
  Future<void> update(
    String id, {
    required DateTime at,
    double? tempC,
    TempSite? tempSite,
    MedKind? medKind,
    String? medName,
    String? medDose,
    Set<Symptom>? symptoms,
    String? symptomOther,
    String? note,
  }) async {
    final existing = await byId(id);
    if (existing == null || existing.deleted) return;
    await (_db.update(_db.healthLogs)..where((t) => t.id.equals(id))).write(
      HealthLogsCompanion(
        at: Value(at),
        tempC: Value(tempC),
        tempSite: Value(tempSite?.name),
        medKind: Value(medKind?.name),
        medName: Value(_clip(medName, _maxMedName)),
        medDose: Value(_clip(medDose, _maxMedDose)),
        symptoms: Value(_encodeSymptoms(symptoms)),
        symptomOther: Value(_clip(symptomOther, _maxSymptomOther)),
        note: Value(note),
        updatedAt: Value(AppClock.now()),
        updatedBy: const Value(null),
        dirty: const Value(true),
      ),
    );
  }

  /// 软删除。
  Future<void> softDelete(String id) async {
    await (_db.update(_db.healthLogs)..where((t) => t.id.equals(id))).write(
      HealthLogsCompanion(
        deleted: const Value(true),
        updatedAt: Value(AppClock.now()),
        updatedBy: const Value(null),
        dirty: const Value(true),
      ),
    );
  }

  Future<HealthLog?> byId(String id) =>
      (_db.select(_db.healthLogs)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// 按时间范围查询（含边界），默认排除已删，按 at 升序。
  Future<List<HealthLog>> list({
    required String babyId,
    DateTime? from,
    DateTime? to,
    bool includeDeleted = false,
  }) {
    final q = _db.select(_db.healthLogs)..where((t) => t.babyId.equals(babyId));
    if (!includeDeleted) {
      q.where((t) => t.deleted.equals(false));
    }
    if (from != null) {
      q.where((t) => t.at.isBiggerOrEqualValue(from));
    }
    if (to != null) {
      q.where((t) => t.at.isSmallerOrEqualValue(to));
    }
    q.orderBy([(t) => OrderingTerm.asc(t.at)]);
    return q.get();
  }

  /// 监听某宝宝未删除记录（按 at 升序）。
  Stream<List<HealthLog>> watch(String babyId) {
    return (_db.select(_db.healthLogs)
          ..where((t) => t.babyId.equals(babyId) & t.deleted.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.at)]))
        .watch();
  }

  HealthLogsCompanion _companion({
    required String id,
    required String babyId,
    required HealthKind kind,
    required DateTime at,
    double? tempC,
    TempSite? tempSite,
    MedKind? medKind,
    String? medName,
    String? medDose,
    Set<Symptom>? symptoms,
    String? symptomOther,
    String? note,
    required bool dirty,
  }) {
    return HealthLogsCompanion.insert(
      id: id,
      babyId: babyId,
      kind: kind.name,
      at: at,
      tempC: Value(tempC),
      tempSite: Value(tempSite?.name),
      medKind: Value(medKind?.name),
      medName: Value(_clip(medName, _maxMedName)),
      medDose: Value(_clip(medDose, _maxMedDose)),
      symptoms: Value(_encodeSymptoms(symptoms)),
      symptomOther: Value(_clip(symptomOther, _maxSymptomOther)),
      note: Value(note),
      updatedAt: Value(AppClock.now()),
      dirty: Value(dirty),
    );
  }

  static String? _clip(String? s, int max) {
    if (s == null) return null;
    final t = s.trim();
    if (t.isEmpty) return null;
    return t.length <= max ? t : t.substring(0, max);
  }

  static String? _encodeSymptoms(Set<Symptom>? symptoms) {
    if (symptoms == null || symptoms.isEmpty) return null;
    return jsonEncode([for (final s in symptoms) s.name]);
  }

  /// 解析库里的 symptoms JSON；坏数据返回空集合。
  static Set<Symptom> decodeSymptoms(String? raw) {
    if (raw == null || raw.isEmpty) return {};
    try {
      final list = jsonDecode(raw);
      if (list is! List) return {};
      final out = <Symptom>{};
      for (final e in list) {
        if (e is! String) continue;
        out.add(Symptom.values.byName(e));
      }
      return out;
    } catch (_) {
      return {};
    }
  }
}
