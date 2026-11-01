import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_icon.dart';
import '../../domain/stages/cry_stage.dart';
import 'stage_copy.dart';

/// 压制阶段提示的来源。默认没有；以后 #28 的就医横幅把自己的 [StageTipSuppressor] 加进来即可：
/// `stageTipSuppressorsProvider.overrideWith(...)` 或在这里返回 `[ref.watch(medicalAlertSuppressorProvider)]`。
final stageTipSuppressorsProvider = Provider<List<StageTipSuppressor>>((ref) => const []);

/// 某次哭声对应的阶段提示（按哭声发生那天的日龄算，所以翻看旧记录时也对得上）
final stageTipForEventProvider = FutureProvider.autoDispose.family<StageTip?, String>((ref, eventId) async {
  final e = await ref.watch(cryEventRepositoryProvider).byId(eventId);
  if (e == null) return null;
  final baby = await ref.watch(currentBabyProvider.future);
  return stageTipFor(birthDate: baby.birthDate, at: e.startedAt, suppressors: ref.watch(stageTipSuppressorsProvider));
});

/// 打开外部链接；测试里替换掉。返回 false 表示没打开。
final linkOpenerProvider = Provider<Future<bool> Function(Uri)>(
  (ref) => (uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  },
);

/// 结果页的一行阶段提示：「这周宝宝可能在 X 期」，点开看说明。没有命中时不占位置。
class StageTipRow extends ConsumerWidget {
  const StageTipRow({super.key, required this.eventId});
  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tip = ref.watch(stageTipForEventProvider(eventId)).value;
    if (tip == null) return const SizedBox.shrink();
    final c = context.hh;
    final line = stageTipLine(tip.stages);
    void open() {
      HapticFeedback.selectionClick();
      showStageSheet(context, tip);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Semantics(
        button: true,
        label: '$line。$stageTipSub',
        excludeSemantics: true,
        onTap: open,
        child: Material(
          color: c.card,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const Key('stage-tip'),
            onTap: open,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56), // 大点按区域
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: c.line),
                ),
                child: Row(
                  children: [
                    const HhIcon(AppIcon.avatarBaby, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            line,
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink),
                          ),
                          const SizedBox(height: 2),
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
        ),
      ),
    );
  }
}

Future<void> showStageSheet(BuildContext context, StageTip tip) {
  final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    sheetAnimationStyle: still ? AnimationStyle.noAnimation : null,
    builder: (_) => StageSheet(tip: tip),
  );
}

/// 说明面板：每个命中的阶段一节（时间、说明、表现、怎么做、关键提示、就医信号、来源），底部统一提示。
class StageSheet extends StatelessWidget {
  const StageSheet({super.key, required this.tip});
  final StageTip tip;

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .85,
      minChildSize: .5,
      maxChildSize: .95,
      // 自带 ScaffoldMessenger：链接打不开时的提示显示在面板上，而不是被面板挡住的结果页上
      builder: (context, scroll) => ScaffoldMessenger(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: ListView(
            key: const Key('stage-sheet'),
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(color: c.line, borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Semantics(
                header: true,
                child: Text(
                  stageTipLine(tip.stages),
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.ink),
                ),
              ),
              const SizedBox(height: 4),
              Text('按宝宝出生第 ${tip.ageDays} 天估计', style: TextStyle(fontSize: 13, color: c.sub)),
              const SizedBox(height: 10),
              // 第一版不做矫正月龄，只在顶部醒目处提示（审阅第 18 条）
              Container(
                key: const Key('stage-preterm'),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(color: c.blueL, borderRadius: BorderRadius.circular(12)),
                child: Text(
                  stagePretermNote,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.blueInk),
                ),
              ),
              for (final s in tip.stages) _StageSection(key: Key('stage-section-${s.name}'), copy: stageCopy[s]!),
              const SizedBox(height: 20),
              for (final n in stageCommonNotes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text('· $n', style: TextStyle(fontSize: 12, color: c.sub, height: 1.6)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StageSection extends StatelessWidget {
  const _StageSection({super.key, required this.copy});
  final StageCopy copy;

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    Widget title(String t) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Semantics(
        header: true,
        child: Text(
          t,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.ink),
        ),
      ),
    );
    Widget bullets(List<String> items) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final i in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('· $i', style: TextStyle(fontSize: 14, color: c.ink, height: 1.6)),
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              header: true,
              child: Text(
                copy.name,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.ink),
              ),
            ),
            const SizedBox(height: 2),
            Text(copy.when, style: TextStyle(fontSize: 13, color: c.sub)),
            const SizedBox(height: 10),
            Text(copy.summary, style: TextStyle(fontSize: 14, color: c.ink, height: 1.6)),
            if (copy.keyFact != null) ...[
              const SizedBox(height: 12),
              Container(
                key: Key('stage-keyfact-${copy.name}'),
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: c.peachL, borderRadius: BorderRadius.circular(12)),
                child: Text(
                  copy.keyFact!,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.peachDeep, height: 1.6),
                ),
              ),
            ],
            title('可能看到'),
            bullets(copy.signs),
            title('可以怎么做'),
            bullets(copy.tips),
            title('出现这些情况请及时就医'),
            bullets(copy.seeDoctor),
            title('来源'),
            for (final s in copy.sources) _SourceLink(source: s),
            const SizedBox(height: 14),
            const EmergencyLineBox(),
          ],
        ),
      ),
    );
  }
}

/// 固定的急症提示（审阅第 1 条），醒目样式。#30 每个阶段一节的末尾用；#38 哄睡的各个面板也直接复用。
class EmergencyLineBox extends StatelessWidget {
  const EmergencyLineBox({super.key, this.boxKey = const Key('stage-emergency')});

  /// 方便测试定位（同一屏可能有两处，比如哄睡页上面盖着安全须知面板）
  final Key boxKey;

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    return Semantics(
      container: true,
      child: Container(
        key: boxKey,
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        // 用 alertBg/alertInk：日间深红字配浅红底（5.45:1），夜间浅字配深红底（5.76:1），见 #34
        decoration: BoxDecoration(
          color: c.alertBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.alertInk, width: 1.5),
        ),
        child: Text(
          stageEmergencyLine,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.alertInk, height: 1.6),
        ),
      ),
    );
  }
}

/// 来源链接给读屏的完整内容：「来源：机构，标题，日期。原文：「引句」」
String sourceLinkSemanticsLabel(StageSource s) => '来源：${s.org}，${s.title}，${s.date}。原文：「${s.quote}」';

class _SourceLink extends ConsumerWidget {
  const _SourceLink({required this.source});
  final StageSource source;

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final ok = await ref.read(linkOpenerProvider)(Uri.parse(source.url));
    if (ok || !context.mounted) return;
    // 没有浏览器等原因打不开：复制链接，方便家长自己粘贴
    await Clipboard.setData(ClipboardData(text: source.url));
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('打不开浏览器，链接已复制')));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.hh;
    // 读屏和看得见的内容一致：机构、标题、日期、原文引句都读出来；"点按在浏览器打开"作为提示（#36）。
    // 整块仍然是一个链接节点，读屏只停一次。
    return Semantics(
      link: true,
      label: sourceLinkSemanticsLabel(source),
      hint: '点按在浏览器打开',
      excludeSemantics: true,
      onTap: () => _open(context, ref),
      child: InkWell(
        key: Key('stage-source-${source.url}'),
        borderRadius: BorderRadius.circular(10),
        onTap: () => _open(context, ref),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  source.title,
                  style: TextStyle(
                    fontSize: 14,
                    color: c.blueInk,
                    decoration: TextDecoration.underline,
                    decorationColor: c.blueInk,
                  ),
                ),
                Text('${source.org} · ${source.date}', style: TextStyle(fontSize: 12, color: c.sub)),
                const SizedBox(height: 2),
                Text('「${source.quote}」', style: TextStyle(fontSize: 12, color: c.sub, height: 1.5)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
