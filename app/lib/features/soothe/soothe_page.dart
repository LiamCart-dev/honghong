import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/prefs.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/hh_widgets.dart';
import '../../domain/models/care_log_type.dart';
import '../care/care_actions.dart';
import '../cry/recording_page.dart' show CircleBack;
import '../stage/stage_tip.dart' show EmergencyLineBox;
import 'sleep_reminder.dart';
import 'soothe_audio.dart';
import 'soothe_player.dart';
import 'soothe_copy.dart';
import 'soothe_widgets.dart';

/// 首次进入哄睡页自动弹出安全须知（只弹一次，按设备记，不跟家人同步）
const sootheSafetySeenKey = 'soothe_safety_seen';

/// 有没有正在进行的睡觉计时
final sleepingNowProvider = Provider<bool>((ref) => (ref.watch(activeSessionsProvider).value ?? const []).any((l) => l.type == CareLogType.sleep.name));

/// 哄睡页（设计终稿 final-03 / 03b / 09 / 10）。
/// 从首页提醒卡「开始哄睡」、结果页建议卡「开始哄睡」进来，夜里也能用。
class SoothePage extends ConsumerStatefulWidget {
  const SoothePage({super.key});

  @override
  ConsumerState<SoothePage> createState() => _SoothePageState();
}

class _SoothePageState extends ConsumerState<SoothePage> {
  @override
  void initState() {
    super.initState();
    // 每次进来：没在播（或已经播完）就回到默认值：粉噪音、30%、30 分钟、未播放（终稿 11 边界情况）
    Future.microtask(() {
      if (mounted) ref.read(sootheAudioProvider.notifier).resetIfNotActive();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final prefs = ref.read(prefsProvider);
      if (prefs.getBool(sootheSafetySeenKey) ?? false) return;
      // 关闭面板（知道了 / 下滑 / 点遮罩 / 返回键）后才记下；面板开着时 App 被杀，下次还会再弹
      await showSootheSafetySheet(context, firstTime: true);
      await prefs.setBool(sootheSafetySeenKey, true);
    });
  }

  Future<void> _asleep() async {
    HapticFeedback.lightImpact();
    await CareActions(ref).start(CareLogType.sleep);
    if (mounted) context.go(Routes.home);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    final band = ref.watch(currentWakeBandProvider);
    final sleeping = ref.watch(sleepingNowProvider);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: PinnedBottomLayout(
          scrollKey: const Key('soothe-scroll'),
          items: [
            SizedBox(
              height: 52,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: CircleBack(onTap: () => context.canPop() ? context.pop() : context.go(Routes.home)),
                  ),
                  Semantics(
                    header: true,
                    child: Text(
                      sootheTitle,
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.ink),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: SootheLink(key: const Key('soothe-safety-link'), label: safetyHeading, onTap: () => showSootheSafetySheet(context)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            HhCard(
              key: const Key('soothe-fixed-notes'),
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [for (final n in playerFixedNotes) SoothePara(n, bottom: 6)]),
            ),
            if (band != null) ...[
              const SizedBox(height: 12),
              // A2：静态，不能点，读屏直接读出全文
              Container(
                key: const Key('soothe-wake-range'),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: c.card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: c.line),
                ),
                child: Row(
                  children: [
                    const ExcludeSemantics(child: HhIcon(AppIcon.avatarBaby, size: 24)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(wakeRangeCopy[band]!, style: TextStyle(fontSize: 14, color: c.ink, height: 1.6)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 4),
            const SoothePlayerControls(),
            const SootheSafetySection(id: 'soothe'),
          ],
          bottom: SootheBottomBar(
            key: const Key('soothe-bottom'),
            children: [
              SoothePlayerBar(
                asleep: _AsleepButton(sleeping: sleeping, onTap: _asleep),
              ),
              Center(
                child: SootheLink(key: const Key('soothe-steps-link'), label: stepsEntry, onTap: () => context.push(Routes.sootheSteps)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 「睡着了 · 开始记录睡觉」；已经在睡觉计时（比如家人记了）时显示「睡觉已在计时」并且不能点
class _AsleepButton extends StatelessWidget {
  const _AsleepButton({required this.sleeping, required this.onTap});
  final bool sleeping;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final main = HhButton(
      key: const Key('soothe-asleep'),
      label: sleeping ? asleepAlreadyLogging : asleepStartLog,
      primary: !sleeping,
      onPressed: sleeping ? null : onTap,
    );
    return main;
  }
}

/// 安全须知底部面板（设计终稿 final-05 / 05b，按钮遮挡修订 6287435046）：
/// 标题固定 + 中间内容滚动 + 底部实色「知道了」；内容底部留 实测按钮区高度 + 16dp；按钮上方 32dp 渐变。
Future<void> showSootheSafetySheet(BuildContext context, {bool firstTime = false}) {
  final still = reduceMotion(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    sheetAnimationStyle: still ? AnimationStyle.noAnimation : null,
    builder: (_) => SootheSafetySheet(firstTime: firstTime),
  );
}

class SootheSafetySheet extends StatelessWidget {
  const SootheSafetySheet({super.key, this.firstTime = false});
  final bool firstTime;

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    final sheetColor = Theme.of(context).bottomSheetTheme.backgroundColor ?? c.bg;
    final h = MediaQuery.sizeOf(context).height;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: h * .9),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SheetGrab(),
                Semantics(
                  header: true,
                  focused: true,
                  child: Text(
                    safetySheetTitle,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.ink),
                  ),
                ),
                if (firstTime)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(safetyFirstTimeLine, style: TextStyle(fontSize: 13, color: c.ink)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: PinnedBottomLayout(
              scrollKey: const Key('safety-sheet-scroll'),
              fade: true,
              fadeColor: sheetColor,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              bottom: SootheBottomBar(
                key: const Key('safety-sheet-bottom'),
                color: sheetColor,
                divider: false,
                children: [HhButton(key: const Key('safety-got-it'), label: safetyGotIt, onPressed: () => Navigator.of(context).pop())],
              ),
              items: [
                const SootheHeading(safetySleepHeading, top: 4),
                for (final l in safeSleepLines) SoothePara(l),
                const SootheHeading(safetySwaddleHeading),
                SoothePara(sootheSteps[1].body, bottom: 12),
                const AlertBox(neverShakeLine, key: Key('safety-never-shake')),
                const SootheHeading(safetySoundHeading),
                SoothePara(playerFixedNotes.first),
                const SootheHeading(safetySickHeading),
                const SoothePara(sickNoSootheLine, bottom: 10),
                const EmergencyLineBox(boxKey: Key('safety-emergency')),
                const SizedBox(height: 10),
                const SoothePara(unusualCryLine, bottom: 8),
                Text(disclaimerLine, style: TextStyle(fontSize: 13, color: c.ink, height: 1.6)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
