import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_clock.dart';
import '../../core/providers.dart';
import '../../core/router/app_router.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/hh_widgets.dart';
import '../../domain/stages/cry_stage.dart';
import '../cry/recording_page.dart' show CircleBack;
import 'soothe_copy.dart';
import 'soothe_player.dart';
import 'soothe_widgets.dart';

/// 宝宝现在是不是在 #30 的哭闹高峰期（按今天的日龄）。
/// 这里**不**看 #30 的压制钩子：「绝不能摇晃宝宝」置顶只会更安全，不该被压制。
final inCryingPeakProvider = Provider<bool>((ref) {
  final baby = ref.watch(currentBabyProvider).value;
  if (baby == null) return false;
  final d = ageInDays(baby.birthDate, AppClock.now());
  return d != null && stagesForAge(d).contains(CryStage.cryingPeak);
});

/// 哄睡步骤（设计终稿 final-04 / 04b）：6 张卡，左右滑或点「上一步」「下一步」。
/// - 每一步下面都有「撑不住」那段；第 3 步紧跟「绝不能摇晃宝宝」红框；
/// - 哭闹高峰期时，「绝不能摇晃宝宝」在页面最前面置顶；
/// - 页面末尾是 C1、C2、急症提示、C2 补充、C3。
class SootheStepsPage extends ConsumerStatefulWidget {
  const SootheStepsPage({super.key});

  @override
  ConsumerState<SootheStepsPage> createState() => _SootheStepsPageState();
}

class _SootheStepsPageState extends ConsumerState<SootheStepsPage> {
  int _i = 0;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _go(int i) {
    if (i < 0 || i >= sootheSteps.length) return;
    HapticFeedback.selectionClick();
    setState(() => _i = i);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _close() => context.canPop() ? context.pop() : context.go(Routes.home);

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    final peak = ref.watch(inCryingPeakProvider);
    final still = reduceMotion(context);
    final step = sootheSteps[_i];
    final last = _i == sootheSteps.length - 1;
    final card = HhCard(
      key: ValueKey('soothe-step-$_i'),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '第 ${_i + 1} 步',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink),
          ),
          const SizedBox(height: 4),
          Semantics(
            header: true,
            child: Text(
              step.title,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: c.ink),
            ),
          ),
          const SizedBox(height: 10),
          for (final p in step.body.split('\n')) SoothePara(p, size: 15, bottom: 6),
        ],
      ),
    );
    final prev = HhButton(key: const Key('steps-prev'), label: prevStep, primary: false, onPressed: _i == 0 ? null : () => _go(_i - 1));
    final next = HhButton(
      key: const Key('steps-next'),
      label: last ? stepsDone : '$nextStepPrefix${sootheSteps[_i + 1].title}',
      onPressed: last ? _close : () => _go(_i + 1),
    );
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: PinnedBottomLayout(
          scrollKey: const Key('steps-scroll'),
          controller: _scroll,
          items: [
            SizedBox(
              height: 52,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Semantics(
                      label: '关闭',
                      button: true,
                      child: CircleBack(icon: AppIcon.close, onTap: _close),
                    ),
                  ),
                  Semantics(
                    header: true,
                    child: Text(
                      stepsTitle,
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.ink),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        '第 ${_i + 1} / ${sootheSteps.length} 步',
                        key: const Key('steps-progress'),
                        style: TextStyle(fontSize: 14, color: c.ink),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (peak) ...[const AlertBox(neverShakeLine, key: Key('steps-never-shake-top')), const SizedBox(height: 12)],
            ExcludeSemantics(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var k = 0; k < sootheSteps.length; k++)
                    Container(
                      width: k == _i ? 22 : 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(color: k == _i ? c.peach2 : c.line, borderRadius: BorderRadius.circular(4)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragEnd: (d) {
                final v = d.primaryVelocity ?? 0;
                if (v < -200) _go(_i + 1);
                if (v > 200) _go(_i - 1);
              },
              child: still ? card : AnimatedSwitcher(duration: const Duration(milliseconds: 180), child: card),
            ),
            if (_i == shakeStepIndex) ...[const SizedBox(height: 12), const AlertBox(neverShakeLine, key: Key('steps-never-shake'))],
            const SizedBox(height: 12),
            Container(
              key: const Key('steps-overwhelmed'),
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
              decoration: BoxDecoration(
                color: c.card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: c.line),
              ),
              child: const SoothePara(overwhelmedLine),
            ),
            const SootheSafetySection(id: 'steps', showHeading: false),
          ],
          bottom: SootheBottomBar(
            key: const Key('steps-bottom'),
            children: [
              // 声音在播放 / 暂停时显示「粉噪音播放中 · 26:10 后关闭  停止」（终稿 04）
              const SootheMiniPlayer(),
              if (largeText(context)) ...[
                next,
                const SizedBox(height: 8),
                prev,
              ] else
                Row(
                  children: [
                    Expanded(flex: 2, child: prev),
                    const SizedBox(width: 10),
                    Expanded(flex: 3, child: next),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
