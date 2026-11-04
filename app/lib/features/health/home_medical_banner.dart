import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';
import '../../domain/health/health.dart';
import 'health_alert_providers.dart';
import 'health_providers.dart';
import 'medical_banner.dart';

/// 首页就医横幅（ADR-0008）：仅「请尽快就医」；门禁关闭时不显示。
class HomeMedicalBanner extends ConsumerWidget {
  const HomeMedicalBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(healthFeatureVisibleProvider)) return const SizedBox.shrink();
    final config = ref.watch(healthConfigProvider);
    final alert = ref.watch(liveMedicalAlertProvider).value;
    if (alert == null || alert.level == MedicalAlertLevel.none) {
      return const SizedBox.shrink();
    }
    if (config.homeBannerOnlyUrgent && !alert.isUrgent) {
      return const SizedBox.shrink();
    }
    return MedicalBanner(
      alert: alert,
      copy: config.copy,
      onOpenRecords: () => context.push(Routes.logs),
    );
  }
}
