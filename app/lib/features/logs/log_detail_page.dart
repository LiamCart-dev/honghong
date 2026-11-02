import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hh_widgets.dart';
import '../../data/db/app_database.dart';
import '../../domain/health/health_models.dart';
import '../care/care_actions.dart';
import '../care/care_log_row.dart';
import '../cry/recording_page.dart';
import '../health/health_log_row.dart';
import '../health/health_providers.dart';
import '../health/med_sheet.dart';
import '../health/symptom_sheet.dart';
import '../health/temp_sheet.dart';
import 'record_editor_sheet.dart';

enum _LogFilter { all, care, health }

/// 全部记录：按天分组；顶部筛选 全部/护理/健康；右上角「补记」（仅护理）。
class LogDetailPage extends ConsumerStatefulWidget {
  const LogDetailPage({super.key});

  @override
  ConsumerState<LogDetailPage> createState() => _LogDetailPageState();
}

class _LogDetailPageState extends ConsumerState<LogDetailPage> {
  _LogFilter _filter = _LogFilter.all;

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    final careAsync = ref.watch(recentLogsProvider);
    final healthVisible = ref.watch(healthFeatureVisibleProvider);
    final healthAsync = healthVisible ? ref.watch(allHealthLogsProvider) : const AsyncValue.data(<HealthLog>[]);
    final actions = CareActions(ref);
    final day = DateFormat('M月d日 EEEE', 'zh_CN');
    final badge = ref.watch(healthPendingBadgeProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: SizedBox(
              height: 52,
              child: Stack(alignment: Alignment.center, children: [
                Align(alignment: Alignment.centerLeft, child: CircleBack(onTap: () => Navigator.of(context).maybePop())),
                Text('全部记录', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.ink)),
                if (_filter != _LogFilter.health)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Material(
                      color: c.peachL,
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        key: const Key('backfill-add'),
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => openRecordEditor(context, ref),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          child: Text('＋ 补记', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.peachDeep)),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
          if (healthVisible) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: HhSegmented<_LogFilter>(
                values: _LogFilter.values,
                label: (f) => switch (f) {
                  _LogFilter.all => '全部',
                  _LogFilter.care => '护理',
                  _LogFilter.health => '健康',
                },
                selected: _filter,
                onChanged: (f) => setState(() => _filter = f),
              ),
            ),
            if (badge != null)
              Padding(
                padding: const EdgeInsets.only(left: 20, bottom: 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: c.peachL, borderRadius: BorderRadius.circular(8)),
                    child: Text(badge, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c.peachDeep)),
                  ),
                ),
              ),
          ],
          Expanded(
            child: careAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('出错了：$e')),
              data: (careList) {
                final healthList = healthAsync.value ?? const <HealthLog>[];
                final items = <Object>[];
                if (_filter != _LogFilter.health) items.addAll(careList);
                if (_filter != _LogFilter.care && healthVisible) items.addAll(healthList);
                items.sort((a, b) {
                  final ta = a is CareLog ? a.startedAt : (a as HealthLog).at;
                  final tb = b is CareLog ? b.startedAt : (b as HealthLog).at;
                  return tb.compareTo(ta);
                });
                if (items.isEmpty) {
                  final empty = _filter == _LogFilter.health
                      ? ref.read(healthConfigProvider).copy.emptyHealthRecords
                      : '还没有记录，在首页点一下就能记，\n忘了点也可以右上角「补记」';
                  return Center(child: Text(empty, textAlign: TextAlign.center, style: TextStyle(color: c.sub)));
                }
                final groups = <DateTime, List<Object>>{};
                for (final it in items) {
                  final at = it is CareLog ? it.startedAt : (it as HealthLog).at;
                  groups.putIfAbsent(DateUtils.dateOnly(at), () => []).add(it);
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  children: [
                    for (final g in groups.entries) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 8),
                        child: Text(day.format(g.key), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.sub)),
                      ),
                      HhCard(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Column(children: [
                          for (var i = 0; i < g.value.length; i++)
                            if (g.value[i] is CareLog)
                              Dismissible(
                                key: ValueKey((g.value[i] as CareLog).id),
                                direction: DismissDirection.endToStart,
                                onDismissed: (_) => ref.read(careLogRepositoryProvider).delete((g.value[i] as CareLog).id),
                                background: Container(
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 20),
                                  color: const Color(0xFFFFD9CC),
                                  child: Text('删除', style: TextStyle(color: c.peachDeep, fontWeight: FontWeight.w700)),
                                ),
                                child: CareLogRow(
                                  log: g.value[i] as CareLog,
                                  last: i == g.value.length - 1,
                                  onTap: () {
                                    final l = g.value[i] as CareLog;
                                    l.endedAt == null ? actions.end(context, l) : openRecordEditor(context, ref, log: l);
                                  },
                                ),
                              )
                            else
                              Dismissible(
                                key: ValueKey((g.value[i] as HealthLog).id),
                                direction: DismissDirection.endToStart,
                                onDismissed: (_) => ref.read(healthLogRepositoryProvider).softDelete((g.value[i] as HealthLog).id),
                                background: Container(
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 20),
                                  color: const Color(0xFFFFD9CC),
                                  child: Text('删除', style: TextStyle(color: c.peachDeep, fontWeight: FontWeight.w700)),
                                ),
                                child: HealthLogRow(
                                  log: g.value[i] as HealthLog,
                                  last: i == g.value.length - 1,
                                  onTap: () => _editHealth(context, g.value[i] as HealthLog),
                                ),
                              ),
                        ]),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _editHealth(BuildContext context, HealthLog h) async {
    final ok = await switch (HealthKind.values.byName(h.kind)) {
      HealthKind.temperature => showTempSheet(context, existing: h),
      HealthKind.medication => showMedSheet(context, existing: h),
      HealthKind.symptom => showSymptomSheet(context, existing: h),
    };
    if (ok && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('已保存修改')));
    }
  }
}

/// 打开补记（log == null）或修改面板，并把结果写进数据库。
Future<void> openRecordEditor(BuildContext context, WidgetRef ref, {CareLog? log}) async {
  final repo = ref.read(careLogRepositoryProvider);
  final baby = await ref.read(currentBabyProvider.future);
  if (!context.mounted) return;
  final r = await showRecordEditor(context,
      log: log, overlaps: (t, a, b) => repo.overlapping(baby.id, t, a, b, excludeId: log?.id));
  if (r == null) return;
  if (r.delete) {
    if (log != null) await repo.delete(log.id);
    return;
  }
  if (log == null) {
    await repo.backfill(baby.id, r.type, start: r.start!, end: r.end, detail: r.detail);
  } else {
    await repo.updateRecord(log.id, start: r.start!, end: r.end, detail: r.detail);
  }
  if (context.mounted) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(log == null ? '已补记${r.type.label}' : '已保存修改')));
  }
}
