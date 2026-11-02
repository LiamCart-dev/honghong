import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/app_clock.dart';
import '../../core/prefs.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/hh_widgets.dart';
import '../../data/db/app_database.dart';
import '../../domain/health/health_models.dart';
import '../soothe/soothe_widgets.dart';
import '../stage/stage_tip.dart' show EmergencyLineBox;
import 'health_providers.dart';
import 'temp_input.dart';

const _kLastTempSite = 'health_last_temp_site';

/// 打开记体温面板。返回是否已保存。
Future<bool> showTempSheet(
  BuildContext context, {
  HealthLog? existing,
}) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    builder: (_) => TempSheet(existing: existing),
  );
  return r == true;
}

class TempSheet extends ConsumerStatefulWidget {
  const TempSheet({super.key, this.existing});
  final HealthLog? existing;

  @override
  ConsumerState<TempSheet> createState() => _TempSheetState();
}

class _TempSheetState extends ConsumerState<TempSheet> {
  late DateTime _at;
  late TempSite _site;
  late TextEditingController _ctl;
  late FocusNode _focus;
  String? _note;
  bool _editingDigits = false;
  final _alertKey = GlobalKey();
  String? _lastAlertText;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _at = e?.at ?? AppClock.now();
    _site = () {
      if (e?.tempSite != null) {
        return TempSite.values.byName(e!.tempSite!);
      }
      return TempSite.armpit;
    }();
    final initial = e?.tempC;
    _ctl = TextEditingController(text: initial != null ? initial.toStringAsFixed(1) : '');
    _focus = FocusNode()..addListener(() {
      if (mounted) setState(() => _editingDigits = _focus.hasFocus);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || e != null) return;
      try {
        final sp = ref.read(prefsProvider);
        final name = sp.getString(_kLastTempSite);
        if (name != null) {
          final s = TempSite.values.where((x) => x.name == name).firstOrNull;
          if (s != null && mounted) setState(() => _site = s);
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _ctl.dispose();
    _focus.dispose();
    super.dispose();
  }

  TempInputResult get _parsed => parseTempInput(_ctl.text, config: ref.read(healthConfigProvider));

  String? get _timeError {
    final n = AppClock.now();
    if (_at.isAfter(n)) return '时间不能晚于现在';
    if (_at.isBefore(n.subtract(const Duration(days: 365)))) return '最早可记 365 天前';
    return null;
  }

  bool get _canSave => _parsed.canSave && _timeError == null;

  void _adjust(double delta) {
    final cur = _parsed.celsius ?? 36.5;
    final next = double.parse((cur + delta).toStringAsFixed(1));
    final range = ref.read(healthConfigProvider).recordableC;
    if (range != null && (next < range.lo || next > range.hi)) return;
    setState(() {
      _ctl.text = next.toStringAsFixed(1);
      _ctl.selection = TextSelection.collapsed(offset: _ctl.text.length);
    });
    _maybeScrollAlert();
  }

  void _setText(String t) {
    setState(() {
      _ctl.value = TextEditingValue(
        text: t,
        selection: TextSelection.collapsed(offset: t.length),
      );
    });
    _maybeScrollAlert();
  }

  Future<void> _maybeScrollAlert() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;
    final ctx = _alertKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    await Scrollable.ensureVisible(
      ctx,
      alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _pickTime() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _at,
      firstDate: AppClock.now().subtract(const Duration(days: 365)),
      lastDate: AppClock.now(),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_at));
    if (t == null || !mounted) return;
    setState(() {
      _at = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    });
  }

  Future<void> _customNote() async {
    final ctl = TextEditingController(text: _note ?? '');
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('备注'),
        content: TextField(controller: ctl, autofocus: true, maxLength: 40),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('确定')),
        ],
      ),
    );
    if (v == null) return;
    setState(() => _note = v.isEmpty ? null : v);
  }

  Future<void> _save() async {
    final parsed = _parsed;
    if (!parsed.canSave || _timeError != null) return;
    final baby = await ref.read(currentBabyProvider.future);
    final repo = ref.read(healthLogRepositoryProvider);
    final c = parsed.celsius!;
    if (_editing) {
      await repo.update(
        widget.existing!.id,
        at: _at,
        tempC: c,
        tempSite: _site,
        note: _note,
      );
    } else {
      await repo.add(
        babyId: baby.id,
        kind: HealthKind.temperature,
        at: _at,
        tempC: c,
        tempSite: _site,
        note: _note,
      );
    }
    try {
      await ref.read(prefsProvider).setString(_kLastTempSite, _site.name);
    } catch (_) {}
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    final cfg = ref.watch(healthConfigProvider);
    final baby = ref.watch(currentBabyProvider).value;
    final ageDays = baby == null ? 120 : AppClock.now().difference(DateUtils.dateOnly(baby.birthDate)).inDays;
    final parsed = _parsed;
    final issue = parsed.issue;
    final timeErr = _timeError;

    String? alertText;
    var showEmergency = false;
    if (parsed.celsius != null) {
      final a = panelAlertForReading(
        celsius: parsed.celsius!,
        site: _site,
        ageDays: ageDays,
        at: _at,
        config: cfg,
      );
      alertText = a.text;
      showEmergency = a.emergency;
    }

    if (alertText != null && alertText != _lastAlertText) {
      _lastAlertText = alertText;
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeScrollAlert());
    }

    Widget label(String s) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 10),
          child: Text(s, style: TextStyle(fontSize: 13, color: c.sub)),
        );

    final readingBorder = (issue?.kind == TempInputIssueKind.missingDecimal ||
            issue?.kind == TempInputIssueKind.outOfRange)
        ? c.peachDeep
        : Colors.transparent;

    final display = _ctl.text.isEmpty ? '--.-' : _ctl.text;
    final kb = MediaQuery.viewInsetsOf(context).bottom;

    final scrollItems = <Widget>[
      const SheetGrab(),
      Row(children: [
        IconTile(AppIcon.healthTemp, size: 48, radius: 16, fontSize: 26, bg: c.peachL),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_editing ? '修改体温' : '记体温', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: 2),
            Text('量完马上记，精确到 0.1℃', style: TextStyle(fontSize: 13, color: c.sub)),
          ]),
        ),
      ]),
      const SizedBox(height: 18),
      // − 大数字 ＋
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _RoundBtn(
            key: const Key('temp-minus'),
            icon: AppIcon.remove,
            semanticLabel: '减 0.1 度',
            onTap: () => _adjust(-0.1),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () {
                _focus.requestFocus();
                setState(() => _editingDigits = true);
              },
              child: Semantics(
                label: '体温',
                value: parsed.celsius != null ? '${parsed.celsius!.toStringAsFixed(1)} 摄氏度' : '未输入',
                increasedValue: parsed.celsius != null
                    ? '${(parsed.celsius! + 0.1).toStringAsFixed(1)} 摄氏度'
                    : '36.6 摄氏度',
                decreasedValue: parsed.celsius != null
                    ? '${(parsed.celsius! - 0.1).toStringAsFixed(1)} 摄氏度'
                    : '未输入',
                onIncrease: () => _adjust(0.1),
                onDecrease: () => _adjust(-0.1),
                child: Container(
                  key: const Key('temp-reading'),
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: readingBorder, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: _editingDigits
                        ? SizedBox(
                            width: 160,
                            child: TextField(
                              controller: _ctl,
                              focusNode: _focus,
                              autofocus: true,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [
                                TextInputFormatter.withFunction((old, next) {
                                  final f = filterTempInput(next.text);
                                  return TextEditingValue(text: f, selection: TextSelection.collapsed(offset: f.length));
                                }),
                              ],
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 44, fontWeight: FontWeight.w800, color: c.ink, height: 1.1),
                              decoration: const InputDecoration(border: InputBorder.none, isDense: true, contentPadding: EdgeInsets.zero),
                              onChanged: (_) => setState(() {}),
                              onEditingComplete: () => setState(() {
                                _focus.unfocus();
                                _editingDigits = false;
                              }),
                            ),
                          )
                        : Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                text: display,
                                style: TextStyle(fontSize: 44, fontWeight: FontWeight.w800, color: c.ink, height: 1.1),
                              ),
                              TextSpan(
                                text: ' ℃',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.ink),
                              ),
                            ]),
                            textAlign: TextAlign.center,
                          ),
                  ),
                ),
              ),
            ),
          ),
          _RoundBtn(
            key: const Key('temp-plus'),
            icon: AppIcon.add,
            semanticLabel: '加 0.1 度',
            onTap: () => _adjust(0.1),
          ),
        ],
      ),
      const SizedBox(height: 6),
      Text('点数字可以直接输入，± 每次 0.1℃', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: c.sub)),
      if (issue?.kind == TempInputIssueKind.missingDecimal && issue!.suggestionC != null) ...[
        const SizedBox(height: 10),
        Text(issue.message ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.ink)),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: HhChip(
            label: '改成 ${issue.suggestionC!.toStringAsFixed(1)}℃',
            on: false,
            onTap: () => _setText(issue.suggestionC!.toStringAsFixed(1)),
          ),
        ),
      ],
      if (issue?.kind == TempInputIssueKind.fahrenheit && issue!.suggestionC != null) ...[
        const SizedBox(height: 10),
        Text(issue.message ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.ink)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          HhChip(
            label: '按 ${issue.suggestionC!.toStringAsFixed(1)}℃ 记',
            on: true,
            onTap: () => _setText(issue.suggestionC!.toStringAsFixed(1)),
          ),
          HhChip(
            label: '重新输入',
            on: false,
            onTap: () {
              _setText('');
              _focus.requestFocus();
              setState(() => _editingDigits = true);
            },
          ),
        ]),
      ],
      if (issue?.kind == TempInputIssueKind.outOfRange) ...[
        const SizedBox(height: 10),
        Text(issue!.message ?? '', key: const Key('temp-out-of-range'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.ink)),
      ],
      if (alertText != null) ...[
        const SizedBox(height: 12),
        Semantics(
          liveRegion: true,
          child: KeyedSubtree(
            key: _alertKey,
            child: AlertBox(alertText, key: const Key('temp-alert')),
          ),
        ),
        if (showEmergency) ...[
          const SizedBox(height: 8),
          const EmergencyLineBox(boxKey: Key('temp-emergency')),
        ],
        // 额外 24dp：PinnedBottomLayout.gap 已是 16，合计警示框底距按钮区 40dp
        const SizedBox(height: 24),
      ],
      label('测量部位'),
      Semantics(
        explicitChildNodes: true,
        child: HhSegmented<TempSite>(
          values: TempSite.values,
          label: tempSiteLabel,
          selected: _site,
          onChanged: (s) => setState(() => _site = s),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(cfg.copy.siteHint, style: TextStyle(fontSize: 12, color: c.sub, height: 1.5)),
      ),
      label('时间'),
      InkWell(
        key: const Key('temp-time'),
        onTap: _pickTime,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: timeErr != null ? c.peachDeep : c.line, width: 1.5),
          ),
          child: Row(children: [
            Text('测量时间', style: TextStyle(fontSize: 14, color: c.sub)),
            const Spacer(),
            Text(DateFormat('M月d日 HH:mm').format(_at), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.ink)),
          ]),
        ),
      ),
      if (timeErr != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(timeErr, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink)),
        ),
      label('备注（可选）'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        HhChip(
          label: _note == null ? '添加备注' : _note!,
          on: _note != null,
          onTap: _customNote,
        ),
      ]),
      const SizedBox(height: 8),
    ];

    final big = largeText(context);
    final buttons = big
        ? <Widget>[
            HhButton(key: const Key('temp-save'), label: '保存', onPressed: _canSave ? _save : null),
            const SizedBox(height: 10),
            HhButton(label: '取消', primary: false, onPressed: () => Navigator.pop(context, false)),
          ]
        : <Widget>[
            Row(children: [
              Expanded(flex: 9, child: HhButton(label: '取消', primary: false, onPressed: () => Navigator.pop(context, false))),
              const SizedBox(width: 12),
              Expanded(
                flex: 11,
                child: HhButton(key: const Key('temp-save'), label: '保存', onPressed: _canSave ? _save : null),
              ),
            ]),
          ];

    // 键盘弹出时底部不要再叠安全区：SootheBottomBar 内部加了 viewPadding.bottom；
    // 键盘态用 MediaQuery 去掉 bottom padding。
    final vp = MediaQuery.viewPaddingOf(context);
    final bottomBar = MediaQuery(
      data: MediaQuery.of(context).copyWith(
        viewPadding: EdgeInsets.fromLTRB(vp.left, vp.top, vp.right, kb > 0 ? 0 : vp.bottom),
      ),
      child: SootheBottomBar(children: buttons),
    );

    return Padding(
      // 把键盘高度交给外层，PinnedBottom 贴在键盘上方
      padding: EdgeInsets.only(bottom: kb),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.92 - kb,
        child: Material(
          color: c.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          clipBehavior: Clip.antiAlias,
          child: PinnedBottomLayout(
            fade: true,
            items: scrollItems,
            bottom: bottomBar,
          ),
        ),
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({super.key, required this.icon, required this.onTap, required this.semanticLabel});
  final AppIcon icon;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Material(
        color: c.card,
        shape: const CircleBorder(),
        elevation: c.dnd(1, 0),
        shadowColor: const Color(0x22000000),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox.square(dimension: 56, child: Center(child: HhIcon(icon, size: 28))),
        ),
      ),
    );
  }
}
