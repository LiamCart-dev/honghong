/// 渠道门禁：版本名后缀 `-dev` / `-ci` + 可选 `--dart-define=HH_CHANNEL=…`（ADR-0009）。
/// 有占位（[HealthConfig.pendingReviewNotes] 非空）时，正式渠道隐藏健康记录功能。
library;

import 'package:honghong/domain/health/health_config.dart';

/// 构建 / 分发渠道。
enum HealthChannel {
  /// 正式包（无 `-dev`/`-ci` 后缀，或 HH_CHANNEL=stable）
  stable,

  /// 开发包（版本名以 `-dev` 结尾，或 HH_CHANNEL=dev）
  dev,

  /// CI 产物（版本名以 `-ci` 结尾，或 HH_CHANNEL=ci）
  ci,
}

/// 从版本名与可选 dart-define 解析渠道。
///
/// [hhChannelDefine] 优先；合法值 `dev` / `ci` / `stable`（大小写不敏感）。
/// 否则看 [versionName] 是否以 `-dev` / `-ci` 结尾（也兼容 `1.0.0-dev+42` 一类 `+` 构建号）。
HealthChannel resolveHealthChannel({
  String? versionName,
  String? hhChannelDefine,
}) {
  switch (hhChannelDefine?.trim().toLowerCase()) {
    case 'dev':
      return HealthChannel.dev;
    case 'ci':
      return HealthChannel.ci;
    case 'stable':
      return HealthChannel.stable;
  }

  final v = versionName ?? '';
  // 1.2.3-dev / 1.2.3-dev+45 / 1.2.3-ci
  if (RegExp(r'-dev(?:\+|$)|-dev$').hasMatch(v) || v.endsWith('-dev')) {
    return HealthChannel.dev;
  }
  if (RegExp(r'-ci(?:\+|$)|-ci$').hasMatch(v) || v.endsWith('-ci')) {
    return HealthChannel.ci;
  }
  return HealthChannel.stable;
}

/// 健康记录功能是否对用户可见。
///
/// - 无待审占位 → 所有渠道可见
/// - 有待审占位 → 仅 `dev` / `ci` 可见；`stable` 隐藏（ADR-0009）
bool isHealthFeatureVisible({
  required HealthConfig config,
  required HealthChannel channel,
}) {
  if (!config.hasPendingReview) return true;
  return channel == HealthChannel.dev || channel == HealthChannel.ci;
}

/// 测试渠道上展示的「文案待审核」角标文案；正式渠道或无占位时返回 null。
String? healthPendingReviewBadge({
  required HealthConfig config,
  required HealthChannel channel,
}) {
  if (!config.hasPendingReview) return null;
  if (channel == HealthChannel.dev || channel == HealthChannel.ci) {
    return config.copy.pendingReviewBadge;
  }
  return null;
}
