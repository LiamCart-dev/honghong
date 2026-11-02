import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/hh_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/health_log_repository.dart';
import '../../domain/health/health_config.dart';
import '../../domain/health/health_models.dart';
import 'temp_input.dart';

/// 首页「今天的记录」/「全部记录」健康行（CareLogRow 风格）。
class HealthLogRow extends StatelessWidget {
  const HealthLogRow({super.key, required this.log, this.last = false, this.onTap});
  final HealthLog log;
  final bool last;
  final VoidCallback? onTap;

  static final _hm = DateFormat('HH:mm');

  static (AppIcon icon, String title, String subtitle) lines(HealthLog log, {HealthConfig config = kHealthConfig}) {
    final kind = HealthKind.values.byName(log.kind);
    return switch (kind) {
      HealthKind.temperature => (
          AppIcon.healthTemp,
          '体温 · ${log.tempC?.toStringAsFixed(1) ?? '--'}℃',
          log.tempSite != null ? tempSiteLabel(TempSite.values.byName(log.tempSite!)) : '',
        ),
      HealthKind.medication => (
          AppIcon.healthMed,
          '用药 · ${log.medName ?? ''}',
          log.medDose ?? '',
        ),
      HealthKind.symptom => () {
          final set = HealthLogRepository.decodeSymptoms(log.symptoms);
          final labels = [
            for (final s in Symptom.values)
              if (set.contains(s))
                s == Symptom.other && (log.symptomOther?.isNotEmpty ?? false)
                    ? log.symptomOther!
                    : (config.copy.symptomLabels[s] ?? s.name),
          ];
          final title = labels.isEmpty ? '症状' : '症状 · ${labels.take(2).join('、')}${labels.length > 2 ? '…' : ''}';
          return (AppIcon.healthSymptom, title, labels.length > 2 ? '共${labels.length}项' : '');
        }(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    final (icon, title, subtitle) = lines(log);
    final timeStyle = TextStyle(fontSize: 13, color: c.sub, fontFeatures: const [FontFeature.tabularFigures()]);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        key: Key('health-row-${log.id}'),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: c.line))),
          child: Row(children: [
            IconTile(icon, bg: c.peachL),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(title,
                    key: const Key('health-row-title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.ink)),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: c.sub)),
                ],
              ]),
            ),
            const SizedBox(width: 10),
            Text(_hm.format(log.at), textAlign: TextAlign.right, style: timeStyle),
          ]),
        ),
      ),
    );
  }
}
