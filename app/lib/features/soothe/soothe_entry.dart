import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_clock.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hh_widgets.dart';
import '../stage/stage_tip.dart' show EmergencyLineBox;
import 'sleep_reminder.dart';
import 'soothe_copy.dart';
import 'soothe_page.dart' show sleepingNowProvider;
import 'soothe_widgets.dart';

/// 结果页建议卡里的哄睡入口（设计终稿 final-02）：第一名是「困了」时显示。
/// - 「开始哄睡」按钮 + 下面一行 C2；
/// - 睡觉计时中不显示（结果页的 SleepResultCard 优先）；
/// - #28 的压制条件满足时，不给哄睡入口，换成 C2 + 急症提示（先看医生）。
class SootheEntry extends ConsumerWidget {
  const SootheEntry({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(sleepingNowProvider)) return const SizedBox.shrink();
    final c = context.hh;
    final now = AppClock.now();
    final suppressed = ref.watch(sleepReminderSuppressorsProvider).any((s) => s.suppresses(now));
    // 建议卡底色是写死的浅色渐变（日夜一样）：日间用 ink、夜间用 sub（终稿第 6 条，日 9.37 / 夜 5.64）
    final lineStyle = TextStyle(fontSize: 13, color: c.dn(c.ink, c.sub), height: 1.6);
    if (suppressed) {
      return Padding(
        key: const Key('soothe-entry-see-doctor'),
        padding: const EdgeInsets.only(top: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CopyText(sickNoSootheLine, style: lineStyle),
            const SizedBox(height: 10),
            const EmergencyLineBox(boxKey: Key('soothe-entry-emergency')),
          ],
        ),
      );
    }
    return Padding(
      key: const Key('soothe-entry'),
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HhButton(
            key: const Key('soothe-entry-start'),
            label: reminderStart,
            onPressed: () {
              HapticFeedback.lightImpact();
              context.push(Routes.soothe);
            },
          ),
          const SizedBox(height: 8),
          CopyText(sickNoSootheLine, style: lineStyle),
        ],
      ),
    );
  }
}
