import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../core/theme/app_theme.dart';
import '../stage/stage_tip.dart' show EmergencyLineBox;
import 'soothe_copy.dart';

/// 文案里 `**…**` 的部分加粗显示
class CopyText extends StatelessWidget {
  const CopyText(this.text, {super.key, this.style});
  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final parts = text.split('**');
    return Text.rich(
      TextSpan(
        children: [
          for (var i = 0; i < parts.length; i++)
            if (parts[i].isNotEmpty)
              TextSpan(
                text: parts[i],
                style: i.isOdd ? const TextStyle(fontWeight: FontWeight.w700) : null,
              ),
        ],
      ),
      style: style,
    );
  }
}

/// 醒目的红色框（alertBg / alertInk，和 #30 急症提示同一套颜色，日夜都 ≥ 4.5:1）。
/// 读屏读成「重要：…」，不只靠颜色传达。
class AlertBox extends StatelessWidget {
  const AlertBox(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    return Semantics(
      container: true,
      label: '重要：${plainCopy(text)}',
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.alertBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.alertInk, width: 1.5),
        ),
        child: CopyText(
          // 整段都加粗显示
          plainCopy(text),
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.alertInk, height: 1.6),
        ),
      ),
    );
  }
}

/// 小标题
class SootheHeading extends StatelessWidget {
  const SootheHeading(this.text, {super.key, this.size = 15, this.top = 16});
  final String text;
  final double size;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: top, bottom: 6),
    child: Semantics(
      header: true,
      child: Text(
        text,
        style: TextStyle(fontSize: size, fontWeight: FontWeight.w700, color: context.hh.ink),
      ),
    ),
  );
}

/// 正文段落
class SoothePara extends StatelessWidget {
  const SoothePara(this.text, {super.key, this.size = 14, this.bottom = 4});
  final String text;
  final double size;
  final double bottom;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: bottom),
    child: CopyText(
      text,
      style: TextStyle(fontSize: size, color: context.hh.ink, height: 1.6),
    ),
  );
}

/// 必带的安全内容（审定稿 C 段）：安全睡眠 C1、可能生病时 C2、急症提示（复用 #30）、C2 补充、C3。
/// 哄睡页底部、步骤页底部都用这一块；[id] 用来区分测试 key。
class SootheSafetySection extends StatelessWidget {
  const SootheSafetySection({super.key, required this.id, this.showHeading = true});
  final String id;
  final bool showHeading;

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    return Column(
      key: Key('$id-safety'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeading) const SootheHeading(safetyHeading, size: 16, top: 20),
        const SootheHeading(safetySleepHeading),
        for (final l in safeSleepLines) SoothePara(l),
        const SootheHeading(safetySickHeading),
        const SoothePara(sickNoSootheLine, bottom: 10),
        EmergencyLineBox(boxKey: Key('$id-emergency')),
        const SizedBox(height: 10),
        const SoothePara(unusualCryLine, bottom: 8),
        Text(
          disclaimerLine,
          key: Key('$id-disclaimer'),
          style: TextStyle(fontSize: 13, color: c.ink, height: 1.6),
        ),
      ],
    );
  }
}

/// 量出子组件的实际尺寸（布局后回调；尺寸变了才回调）
class MeasureSize extends SingleChildRenderObjectWidget {
  const MeasureSize({super.key, required this.onChange, super.child});
  final ValueChanged<Size> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMeasureSize(onChange);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) => (renderObject as _RenderMeasureSize).onChange = onChange;
}

class _RenderMeasureSize extends RenderProxyBox {
  _RenderMeasureSize(this.onChange);
  ValueChanged<Size> onChange;
  Size? _last;

  @override
  void performLayout() {
    super.performLayout();
    final s = size;
    if (s == _last) return;
    _last = s;
    WidgetsBinding.instance.addPostFrameCallback((_) => onChange(s));
  }
}

/// 底部固定区和上面的滚动内容（#38 终稿修订 6287435046）：
/// - 滚动内容底部 padding = 底部固定区**实测**高度（含底部安全区）+ 16dp，大字体下按钮变高时跟着变；
/// - [fade] 为 true 时，在底部固定区上方加 32dp 渐变（透明 → [fadeColor]），提示下面还有内容；
///   滚到底或内容没超出一屏时隐藏。渐变只是装饰：不读屏、不拦截点击。
class PinnedBottomLayout extends StatefulWidget {
  const PinnedBottomLayout({
    super.key,
    required this.items,
    required this.bottom,
    this.padding = const EdgeInsets.fromLTRB(20, 8, 20, 0),
    this.fade = false,
    this.fadeColor,
    this.scrollKey,
    this.controller,
  });

  final List<Widget> items;
  final Widget bottom;
  final EdgeInsets padding;
  final bool fade;
  final Color? fadeColor;
  final Key? scrollKey;
  final ScrollController? controller;

  /// 滚动内容和底部固定区之间至少留的空白
  static const gap = 16.0;
  static const fadeHeight = 32.0;

  @override
  State<PinnedBottomLayout> createState() => _PinnedBottomLayoutState();
}

class _PinnedBottomLayoutState extends State<PinnedBottomLayout> {
  double _bottomH = 0;
  bool _more = false;
  ScrollController? _own;
  ScrollController get _ctl => widget.controller ?? (_own ??= ScrollController());

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  bool _onMetrics(ScrollMetrics m) {
    final more = m.extentAfter > 0.5;
    if (more != _more) setState(() => _more = more);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final fadeColor = widget.fadeColor ?? context.hh.bg;
    return Stack(
      children: [
        Positioned.fill(
          child: NotificationListener<ScrollMetricsNotification>(
            onNotification: (n) => _onMetrics(n.metrics),
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) => n.depth == 0 && _onMetrics(n.metrics),
              child: ListView(
                key: widget.scrollKey,
                controller: _ctl,
                padding: widget.padding.copyWith(bottom: widget.padding.bottom + _bottomH + PinnedBottomLayout.gap),
                children: widget.items,
              ),
            ),
          ),
        ),
        if (widget.fade)
          Positioned(
            left: 0,
            right: 0,
            bottom: _bottomH,
            height: PinnedBottomLayout.fadeHeight,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: Visibility(
                  visible: _more,
                  child: DecoratedBox(
                    key: const Key('pinned-fade'),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [fadeColor.withValues(alpha: 0), fadeColor]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: MeasureSize(
            onChange: (s) {
              if (mounted && s.height != _bottomH) setState(() => _bottomH = s.height);
            },
            child: widget.bottom,
          ),
        ),
      ],
    );
  }
}

/// 底部固定区的外框：实色底 + 顶部分隔线 + 底部安全区
class SootheBottomBar extends StatelessWidget {
  const SootheBottomBar({super.key, required this.children, this.color, this.divider = true});
  final List<Widget> children;
  final Color? color;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    return Container(
      decoration: BoxDecoration(
        color: color ?? c.bg,
        border: divider ? Border(top: BorderSide(color: c.line)) : null,
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + MediaQuery.viewPaddingOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }
}

/// 大字体（≥1.3 倍）判断，和终稿一致：`textScaler.scale(14) / 14 >= 1.3`
bool largeText(BuildContext context) => MediaQuery.textScalerOf(context).scale(14) / 14 >= 1.3;

bool reduceMotion(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

/// 文字链接按钮（≥48dp 热区，用 ink 色：终稿第 8 条）
class SootheLink extends StatelessWidget {
  const SootheLink({super.key, required this.label, required this.onTap, this.chevron = true});
  final String label;
  final VoidCallback onTap;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(minimumSize: const Size(48, 48), foregroundColor: c.ink),
      child: Text(
        chevron ? '$label ›' : label,
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.ink),
      ),
    );
  }
}
