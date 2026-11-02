import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_icon.dart';
import 'health_providers.dart';
import 'med_sheet.dart';
import 'symptom_sheet.dart';
import 'temp_sheet.dart';

/// 首页快捷区下方的三个健康入口（设计稿 01；夜间也显示）。
class HealthEntryRow extends ConsumerWidget {
  const HealthEntryRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(healthFeatureVisibleProvider)) return const SizedBox.shrink();
    final c = context.hh;
    final badge = ref.watch(healthPendingBadgeProvider);
    final gap = SizedBox(width: c.dnd(10, 12));
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (badge != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  key: const Key('health-pending-badge'),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: c.peachL, borderRadius: BorderRadius.circular(8)),
                  child: Text(badge, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.peachDeep)),
                ),
              ),
            ),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _Entry(
                    icon: AppIcon.healthTemp,
                    label: '体温',
                    semantic: '记体温',
                    onTap: () async {
                      if (await showTempSheet(context) && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已记下体温')));
                      }
                    },
                  ),
                ),
                gap,
                Expanded(
                  child: _Entry(
                    icon: AppIcon.healthMed,
                    label: '用药',
                    semantic: '记用药',
                    onTap: () async {
                      if (await showMedSheet(context) && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已记下用药')));
                      }
                    },
                  ),
                ),
                gap,
                Expanded(
                  child: _Entry(
                    icon: AppIcon.healthSymptom,
                    label: '症状',
                    semantic: '记症状',
                    onTap: () async {
                      if (await showSymptomSheet(context) && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已记下症状')));
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({required this.icon, required this.label, required this.semantic, required this.onTap});
  final AppIcon icon;
  final String label;
  final String semantic;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    return Semantics(
      button: true,
      label: semantic,
      child: Material(
        color: c.card,
        borderRadius: BorderRadius.circular(18),
        elevation: c.dnd(1, 0),
        shadowColor: const Color(0x14000000),
        child: InkWell(
          key: Key('health-entry-${icon.file}'),
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ExcludeSemantics(child: HhIcon(icon, size: 26)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.ink),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
