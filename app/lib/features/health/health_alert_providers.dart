import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:honghong/core/app_clock.dart';
import 'package:honghong/core/providers.dart';
import 'package:honghong/domain/health/health.dart';
import 'package:honghong/domain/models/cry_context.dart';
import 'package:honghong/domain/soothe/wake_window.dart';
import 'package:honghong/domain/stages/cry_stage.dart';
import 'package:honghong/features/health/health_providers.dart';

/// 当前宝宝「现在」的就医提示（首页横幅 / 压制钩子）。无日志或无命中 → none。
final liveMedicalAlertProvider = FutureProvider<MedicalAlert>((ref) async {
  final baby = await ref.watch(currentBabyProvider.future);
  final config = ref.watch(healthConfigProvider);
  final now = AppClock.now();
  final snap = await ref.watch(healthLogRepositoryProvider).snapshotAt(
        babyId: baby.id,
        at: now,
        config: config,
      );
  final days = ageInDays(baby.birthDate, now) ?? 0;
  return MedicalAlert.evaluate(snapshot: snap, ageDays: days, config: config);
});

/// 某次哭声结果页的就医提示：只看当时写入的健康快照；老记录无快照 → none。
final eventMedicalAlertProvider =
    FutureProvider.autoDispose.family<MedicalAlert, String>((ref, eventId) async {
  final e = await ref.watch(cryEventRepositoryProvider).byId(eventId);
  if (e == null) return const MedicalAlert(level: MedicalAlertLevel.none, reasons: []);
  Map<String, dynamic> map;
  try {
    map = Map<String, dynamic>.from(jsonDecode(e.contextJson) as Map);
  } catch (_) {
    return const MedicalAlert(level: MedicalAlertLevel.none, reasons: []);
  }
  final ctx = CryContext.fromJson(map);
  final health = ctx.health;
  if (health == null) {
    return const MedicalAlert(level: MedicalAlertLevel.none, reasons: []);
  }
  final baby = await ref.watch(currentBabyProvider.future);
  final config = ref.watch(healthConfigProvider);
  final days = ageInDays(baby.birthDate, e.startedAt) ?? 0;
  return MedicalAlert.evaluate(snapshot: health, ageDays: days, config: config);
});

/// 首页阶段提示：仅在「请尽快就医」（与首页横幅同级）时压制。
class _UrgentStageTipSuppressor implements StageTipSuppressor {
  _UrgentStageTipSuppressor(this._alert);
  final MedicalAlert _alert;
  @override
  bool suppresses(DateTime at) => _alert.isUrgent;
}

/// 哄睡提醒 / 结果页入口：有就医提示（urgent 或 advise）即压制。
class _MedicalSleepSuppressor implements SleepReminderSuppressor {
  _MedicalSleepSuppressor(this._alert);
  final MedicalAlert _alert;
  @override
  bool suppresses(DateTime at) => _alert.level != MedicalAlertLevel.none;
}

final medicalStageTipSuppressorProvider = Provider<StageTipSuppressor?>((ref) {
  final alert = ref.watch(liveMedicalAlertProvider).value;
  if (alert == null || !alert.isUrgent) return null;
  return _UrgentStageTipSuppressor(alert);
});

final medicalSleepReminderSuppressorProvider = Provider<SleepReminderSuppressor?>((ref) {
  final alert = ref.watch(liveMedicalAlertProvider).value;
  if (alert == null || alert.level == MedicalAlertLevel.none) return null;
  return _MedicalSleepSuppressor(alert);
});
