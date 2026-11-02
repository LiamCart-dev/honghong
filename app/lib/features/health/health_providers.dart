import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:honghong/core/app_clock.dart';
import 'package:honghong/core/env.dart';
import 'package:honghong/core/providers.dart';
import 'package:honghong/data/db/app_database.dart';
import 'package:honghong/domain/health/health.dart';
import 'package:honghong/features/update/update_providers.dart';
import 'package:flutter/material.dart' show DateUtils;

/// 可在测试里 overrideWithValue。正式运行从 PackageInfo / HH_CHANNEL 解析。
final healthChannelProvider = Provider<HealthChannel>((ref) {
  final info = ref.watch(packageInfoProvider).value;
  final define = hhChannelDefine.trim();
  return resolveHealthChannel(
    versionName: info?.version,
    hhChannelDefine: define.isEmpty ? null : define,
  );
});

final healthConfigProvider = Provider<HealthConfig>((ref) => kHealthConfig);

/// 功能是否对当前渠道可见（有 pendingReview 时正式包隐藏）。
final healthFeatureVisibleProvider = Provider<bool>((ref) {
  return isHealthFeatureVisible(
    config: ref.watch(healthConfigProvider),
    channel: ref.watch(healthChannelProvider),
  );
});

/// 测试渠道上的「文案待审核」角标；正式包或无占位时为 null。
final healthPendingBadgeProvider = Provider<String?>((ref) {
  return healthPendingReviewBadge(
    config: ref.watch(healthConfigProvider),
    channel: ref.watch(healthChannelProvider),
  );
});

/// 今天的健康记录（未删），按 at 降序。
final todayHealthLogsProvider = StreamProvider<List<HealthLog>>((ref) async* {
  final baby = await ref.watch(currentBabyProvider.future);
  final repo = ref.watch(healthLogRepositoryProvider);
  yield* repo.watch(baby.id).map((rows) {
    final today = DateUtils.dateOnly(AppClock.now());
    final list = rows.where((h) => !h.at.isBefore(today)).toList()
      ..sort((a, b) => b.at.compareTo(a.at));
    return list;
  });
});


/// 全部未删健康记录（按 at 降序），供「全部记录」页。
final allHealthLogsProvider = StreamProvider<List<HealthLog>>((ref) async* {
  final baby = await ref.watch(currentBabyProvider.future);
  final repo = ref.watch(healthLogRepositoryProvider);
  yield* repo.watch(baby.id).map((rows) {
    final list = [...rows]..sort((a, b) => b.at.compareTo(a.at));
    return list;
  });
});
