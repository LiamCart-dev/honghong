import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_clock.dart';
import '../../core/prefs.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/hh_widgets.dart';
import '../../domain/models/care_log_type.dart';
import '../../domain/soothe/wake_window.dart';
import '../../domain/stages/cry_stage.dart';
import '../stage/stage_copy.dart' show stageTipLine, stageTipSub;
import '../stage/stage_tip.dart';
import 'soothe_copy.dart';
import 'soothe_widgets.dart';

/// 压制哄睡提醒和结果页「开始哄睡」的来源。默认没有；以后 #28 的生病记录把自己的
/// [SleepReminderSuppressor] 加进来即可（和 #30 的 `stageTipSuppressorsProvider` 一样）。
final sleepReminderSuppressorsProvider = Provider<List<SleepReminderSuppressor>>((ref) => const []);

/// 「还不困」：记下那次醒来的时间（= 最近一次睡眠的结束时间），本次醒着期间不再提醒。
/// 按设备存（不跟家人同步），App 重启后仍然有效。
class SleepReminderDismissNotifier extends Notifier<DateTime?> {
  static const key = 'sleep_reminder_dismissed_wake';

  @override
  DateTime? build() {
    final ms = ref.watch(prefsProvider).getInt(key);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  void dismiss(DateTime wakeAt) {
    state = wakeAt;
    ref.read(prefsProvider).setInt(key, wakeAt.millisecondsSinceEpoch);
  }
}

final sleepReminderDismissProvider = NotifierProvider<SleepReminderDismissNotifier, DateTime?>(SleepReminderDismissNotifier.new);

/// 现在要不要显示首页哄睡提醒。数据还没加载完时为 null。
/// 睡眠记录（含家人同步来的）一变就重新算；另外在下一个时间点（到下限、超过 2 倍上限、进出夜间时段）定时重算。
final sleepReminderProvider = Provider<SleepReminderDecision?>((ref) {
  final baby = ref.watch(currentBabyProvider).value;
  final active = ref.watch(activeSessionsProvider).value;
  final latest = ref.watch(latestLogsProvider).value;
  if (baby == null || active == null || latest == null) return null;
  final now = AppClock.now();
  final sleeping = active.any((l) => l.type == CareLogType.sleep.name);
  final lastEnd = latest[CareLogType.sleep]?.endedAt;
  final d = evaluateSleepReminder(
    birthDate: baby.birthDate,
    now: now,
    lastSleepEnd: lastEnd,
    sleeping: sleeping,
    dismissedWakeAt: ref.watch(sleepReminderDismissProvider),
    suppressors: ref.watch(sleepReminderSuppressorsProvider),
  );
  final next = nextReminderCheck(now: now, lastSleepEnd: lastEnd, band: d.band);
  if (next != null) {
    final t = Timer(next.difference(now) + const Duration(milliseconds: 50), ref.invalidateSelf);
    ref.onDispose(t.cancel);
  }
  return d;
});

/// 当前月龄档（哄睡页的 A2 卡用）；满 12 个月为 null
final currentWakeBandProvider = Provider<WakeBand?>((ref) {
  final baby = ref.watch(currentBabyProvider).value;
  return baby == null ? null : wakeBandFor(baby.birthDate, AppClock.now());
});

/// 现在是不是在 #30 的某个阶段（按今天的日龄；被 #30 的压制钩子压制时为 null）
final currentStageTipProvider = Provider<StageTip?>((ref) {
  final baby = ref.watch(currentBabyProvider).value;
  if (baby == null) return null;
  return stageTipFor(birthDate: baby.birthDate, at: AppClock.now(), suppressors: ref.watch(stageTipSuppressorsProvider));
});

/// 首页哄睡提醒卡（设计终稿 final-01 / 01c / 08 / 08b）：内嵌在状态条下方，不遮挡任何入口。
/// 只讲困倦信号，不放 C2、不放月龄范围（Liam 2026-10-20 确认）。
class SleepReminderCard extends ConsumerStatefulWidget {
  const SleepReminderCard({super.key});

  @override
  ConsumerState<SleepReminderCard> createState() => _SleepReminderCardState();
}

class _SleepReminderCardState extends ConsumerState<SleepReminderCard> {
  /// 大字体时正文默认折叠；展开状态只存在这里，卡片下次出现时又是折叠的
  bool _expanded = false;

  void _start(SleepReminderDecision d) {
    HapticFeedback.lightImpact();
    // 已经开始哄睡：本次醒着期间不再提醒（卡片收起）
    if (d.wakeAt != null) ref.read(sleepReminderDismissProvider.notifier).dismiss(d.wakeAt!);
    context.push(Routes.soothe);
  }

  void _notSleepy(SleepReminderDecision d) {
    HapticFeedback.selectionClick();
    if (d.wakeAt != null) ref.read(sleepReminderDismissProvider.notifier).dismiss(d.wakeAt!);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(sleepReminderProvider.select((d) => d?.show ?? false), (prev, next) {
      if (next && prev != true) {
        HapticFeedback.mediumImpact();
        if (mounted) setState(() => _expanded = false);
      }
    });
    final d = ref.watch(sleepReminderProvider);
    final still = reduceMotion(context);
    final child = (d == null || !d.show) ? const SizedBox(key: ValueKey('none'), width: double.infinity) : _card(context, d);
    if (still) return child;
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(duration: const Duration(milliseconds: 180), child: child),
    );
  }

  Widget _card(BuildContext context, SleepReminderDecision d) {
    final c = context.hh;
    final big = largeText(context);
    final showBody = !big || _expanded;
    final title = reminderTitle(d.awake!);
    final stage = ref.watch(currentStageTipProvider);
    final sleepChange = stage != null && stage.stages.contains(CryStage.sleepChange);
    final buttons = [
      HhButton(key: const Key('reminder-not-sleepy'), label: reminderNotSleepy, primary: false, onPressed: () => _notSleepy(d)),
      HhButton(key: const Key('reminder-start'), label: reminderStart, onPressed: () => _start(d)),
    ];
    return Padding(
      key: const ValueKey('card'),
      padding: const EdgeInsets.only(top: 12),
      child: Semantics(
        container: true,
        liveRegion: true,
        label: title,
        child: Container(
          key: const Key('sleep-reminder-card'),
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: c.line),
            boxShadow: c.cardShadows,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ExcludeSemantics(child: HhIcon(AppIcon.causeSleepy, size: 28)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ExcludeSemantics(
                      child: Text(
                        title,
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.ink),
                      ),
                    ),
                  ),
                ],
              ),
              if (big) _expandToggle(context),
              if (showBody) ...[
                const SizedBox(height: 6),
                Text(
                  reminderBody,
                  key: const Key('reminder-body'),
                  style: TextStyle(fontSize: 14, color: c.ink, height: 1.6),
                ),
              ],
              if (sleepChange && showBody) ...[const SizedBox(height: 10), _StageLine(tip: stage)],
              const SizedBox(height: 12),
              if (big)
                Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [buttons[1], const SizedBox(height: 8), buttons[0]])
              else
                Row(
                  children: [
                    Expanded(child: buttons[0]),
                    const SizedBox(width: 10),
                    Expanded(child: buttons[1]),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _expandToggle(BuildContext context) {
    final c = context.hh;
    void toggle() {
      HapticFeedback.selectionClick();
      setState(() => _expanded = !_expanded);
    }

    return Semantics(
      button: true,
      expanded: _expanded,
      label: _expanded ? reminderCollapseSemantics : reminderExpand,
      excludeSemantics: true,
      onTap: toggle,
      child: InkWell(
        key: const Key('reminder-expand'),
        onTap: toggle,
        borderRadius: BorderRadius.circular(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _expanded ? reminderCollapse : reminderExpand,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.ink),
                ),
              ),
              HhIcon(_expanded ? AppIcon.chevronUp : AppIcon.chevronDown, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// 01c：睡眠模式变化期时卡片内多一行，样式照 #30 的 StageTipRow，点开是 #30 的说明面板
class _StageLine extends StatelessWidget {
  const _StageLine({required this.tip});
  final StageTip tip;

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    final only = StageTip(ageDays: tip.ageDays, stages: const [CryStage.sleepChange]);
    final line = stageTipLine(only.stages);
    void open() {
      HapticFeedback.selectionClick();
      showStageSheet(context, only);
    }

    return Semantics(
      button: true,
      label: '$line。$stageTipSub',
      excludeSemantics: true,
      onTap: open,
      child: Material(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const Key('reminder-stage'),
          onTap: open,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.line),
            ),
            child: Row(
              children: [
                const HhIcon(AppIcon.avatarBaby, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.ink),
                      ),
                      Text(stageTipSub, style: TextStyle(fontSize: 12, color: c.sub)),
                    ],
                  ),
                ),
                const HhIcon(AppIcon.chevronRight, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
