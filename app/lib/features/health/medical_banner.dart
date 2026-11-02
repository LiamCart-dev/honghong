import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/health/health.dart';

/// 结果页就医横幅（设计稿 05 / 05b）。不能收起；级别由调用方决定。
class MedicalBanner extends StatelessWidget {
  const MedicalBanner({
    super.key,
    required this.alert,
    required this.copy,
    this.onOpenRecords,
    this.maxReasons = 3,
  });

  final MedicalAlert alert;
  final HealthCopy copy;
  final VoidCallback? onOpenRecords;
  final int maxReasons;

  @override
  Widget build(BuildContext context) {
    if (alert.level == MedicalAlertLevel.none) return const SizedBox.shrink();
    final c = context.hh;
    final urgent = alert.isUrgent;
    final title = urgent ? copy.bannerTitleUrgent : copy.bannerTitleAdvise;
    final body = urgent ? copy.bannerBodyUrgent : copy.bannerBodyAdvise;
    final reasons = alert.reasons.take(maxReasons).toList();

    return Padding(
      key: Key(urgent ? 'medical-banner-urgent' : 'medical-banner-advise'),
      padding: const EdgeInsets.only(bottom: 14),
      child: Semantics(
        container: true,
        header: true,
        liveRegion: true,
        label: '$title。$body',
        child: Material(
          color: c.alertBg,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onOpenRecords,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: c.alertInk,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    body,
                    style: TextStyle(fontSize: 13, height: 1.55, color: c.alertInk),
                  ),
                  if (reasons.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    for (final r in reasons)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '· ${r.label}',
                          style: TextStyle(fontSize: 13, height: 1.45, color: c.alertInk),
                        ),
                      ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    copy.bannerDisclaimer,
                    style: TextStyle(fontSize: 11, height: 1.45, color: c.alertInk.withValues(alpha: 0.85)),
                  ),
                  if (onOpenRecords != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '查看健康记录 ›',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: c.alertInk,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
