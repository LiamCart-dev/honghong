import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/app_clock.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/hh_widgets.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/health_log_repository.dart';
import '../../domain/health/health.dart';
import '../soothe/soothe_widgets.dart';
import '../stage/stage_tip.dart' show EmergencyLineBox;
import 'health_providers.dart';

const _ordinary = [
  Symptom.cough,
  Symptom.runnyNose,
  Symptom.vomit,
  Symptom.diarrhea,
  Symptom.rash,
  Symptom.other,
];

Future<bool> showSymptomSheet(BuildContext context, {HealthLog? existing}) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    builder: (_) => SymptomSheet(existing: existing),
  );
  return r == true;
}

class SymptomSheet extends ConsumerStatefulWidget {
  const SymptomSheet({super.key, this.existing});
  final HealthLog? existing;
  @override
  ConsumerState<SymptomSheet> createState() => _SymptomSheetState();
}

class _SymptomSheetState extends ConsumerState<SymptomSheet> {
  late DateTime _at;
  late Set<Symptom> _selected;
  late TextEditingController _other;
  String? _note;
  final _alertKey = GlobalKey();
  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _at = e?.at ?? AppClock.now();
    _selected = {...HealthLogRepository.decodeSymptoms(e?.symptoms)};
    _other = TextEditingController(text: e?.symptomOther ?? '');
    _note = e?.note;
  }

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  String? get _timeError {
    final n = AppClock.now();
    if (_at.isAfter(n)) return '时间不能晚于现在';
    if (_at.isBefore(n.subtract(const Duration(days: 365)))) return '最早可记 365 天前';
    return null;
  }

  bool get _canSave {
    if (_timeError != null) return false;
    if (_selected.isEmpty) return false;
    if (_selected.contains(Symptom.other) && _other.text.trim().isEmpty) return false;
    if (_other.text.trim().length > 20) return false;
    return true;
  }

  bool _hasDanger(HealthConfig cfg) => _selected.any(cfg.dangerSymptoms.contains);

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
    setState(() => _at = DateTime(d.year, d.month, d.day, t.hour, t.minute));
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

  Future<void> _editOther() async {
    final ctl = TextEditingController(text: _other.text);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('其他症状'),
        content: TextField(controller: ctl, autofocus: true, maxLength: 20),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('确定')),
        ],
      ),
    );
    if (v == null) return;
    setState(() {
      _other.text = v;
      if (v.isNotEmpty) {
        _selected = {..._selected, Symptom.other};
      }
    });
  }

  void _toggle(Symptom s) {
    setState(() {
      if (_selected.contains(s)) {
        _selected = {..._selected}..remove(s);
        if (s == Symptom.other) _other.clear();
      } else {
        _selected = {..._selected, s};
        if (s == Symptom.other) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _editOther());
        }
      }
    });
    if (_hasDanger(ref.read(healthConfigProvider))) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final ctx = _alertKey.currentContext;
        if (ctx == null || !ctx.mounted) return;
        await Scrollable.ensureVisible(
          ctx,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      });
    }
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final baby = await ref.read(currentBabyProvider.future);
    final repo = ref.read(healthLogRepositoryProvider);
    final other = _selected.contains(Symptom.other) ? _other.text.trim() : null;
    try {
      if (_editing) {
        await repo.update(
          widget.existing!.id,
          at: _at,
          symptoms: _selected,
          symptomOther: other,
          note: _note,
        );
      } else {
        await repo.add(
          babyId: baby.id,
          kind: HealthKind.symptom,
          at: _at,
          symptoms: _selected,
          symptomOther: other,
          note: _note,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('保存失败，请再试')));
      }
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这条记录？'),
        content: const Text('加入家庭时，家人那边也会一起删除。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(key: const Key('confirm-delete'), onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok == true && mounted) {
      await ref.read(healthLogRepositoryProvider).softDelete(widget.existing!.id);
      if (mounted) Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.hh;
    final cfg = ref.watch(healthConfigProvider);
    final danger = cfg.dangerSymptoms.toList();
    final timeErr = _timeError;
    final showEmerg = _hasDanger(cfg);
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    Widget label(String s) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 10),
          child: Text(s, style: TextStyle(fontSize: 13, color: c.sub)),
        );

    Widget chip(Symptom s, {bool emergency = false}) {
      final on = _selected.contains(s);
      final text = s == Symptom.other
          ? (_other.text.trim().isEmpty ? '＋ 其他' : '其他 · ${_other.text.trim()}')
          : (cfg.copy.symptomLabels[s] ?? s.name);
      return Semantics(
        checked: on,
        button: true,
        label: emergency ? '急症：$text' : text,
        child: GestureDetector(
          onTap: () => s == Symptom.other && on ? _editOther() : _toggle(s),
          child: Container(
            key: Key('sym-${s.name}'),
            padding: EdgeInsets.symmetric(horizontal: emergency ? 13 : 14, vertical: emergency ? 6 : 7),
            decoration: BoxDecoration(
              color: on ? c.peachL : c.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: emergency ? c.ink : (on ? c.peach : c.line),
                width: emergency ? 2 : 1,
              ),
            ),
            child: Text(
              on && !emergency ? '✓ $text' : text,
              style: TextStyle(
                fontSize: 13,
                fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                color: on ? c.peachDeep : c.ink,
              ),
            ),
          ),
        ),
      );
    }

    final items = <Widget>[
      const SheetGrab(),
      Row(children: [
        IconTile(AppIcon.healthSymptom, size: 48, radius: 16, fontSize: 26, bg: c.peachL),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_editing ? '修改症状' : '记症状', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: 2),
            Text('可以多选', style: TextStyle(fontSize: 13, color: c.sub)),
          ]),
        ),
      ]),
      label('症状（可以多选）'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final s in _ordinary) chip(s),
      ]),
      const SizedBox(height: 16),
      Text(cfg.copy.dangerGroupTitle, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.ink)),
      Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 8),
        child: Text(cfg.copy.dangerGroupSubtitle, style: TextStyle(fontSize: 12, color: c.sub, height: 1.5)),
      ),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final s in danger) chip(s, emergency: true),
      ]),
      if (showEmerg) ...[
        const SizedBox(height: 12),
        KeyedSubtree(
          key: _alertKey,
          child: const EmergencyLineBox(boxKey: Key('sym-emergency')),
        ),
        const SizedBox(height: 24), // + gap16 → 40dp above button bar
      ],
      label('时间'),
      InkWell(
        key: const Key('sym-time'),
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
            Text('记录时间', style: TextStyle(fontSize: 14, color: c.sub)),
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
      Wrap(children: [
        HhChip(label: _note == null ? '添加备注' : _note!, on: _note != null, onTap: _customNote),
      ]),
      const SizedBox(height: 8),
    ];

    final big = largeText(context);
    final buttons = <Widget>[
      if (big) ...[
        HhButton(key: const Key('sym-save'), label: '保存', onPressed: _canSave ? _save : null),
        const SizedBox(height: 10),
        HhButton(label: '取消', primary: false, onPressed: () => Navigator.pop(context, false)),
      ] else
        Row(children: [
          Expanded(flex: 9, child: HhButton(label: '取消', primary: false, onPressed: () => Navigator.pop(context, false))),
          const SizedBox(width: 12),
          Expanded(flex: 11, child: HhButton(key: const Key('sym-save'), label: '保存', onPressed: _canSave ? _save : null)),
        ]),
      if (_editing)
        Center(
          child: TextButton(
            key: const Key('health-delete'),
            onPressed: _delete,
            child: Text('删除这条记录', style: TextStyle(color: c.peachDeep, fontWeight: FontWeight.w700)),
          ),
        ),
    ];

    final vp = MediaQuery.viewPaddingOf(context);
    return Padding(
      padding: EdgeInsets.only(bottom: kb),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.92 - kb,
        child: Material(
          color: c.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          clipBehavior: Clip.antiAlias,
          child: PinnedBottomLayout(
            fade: true,
            items: items,
            bottom: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                viewPadding: EdgeInsets.fromLTRB(vp.left, vp.top, vp.right, kb > 0 ? 0 : vp.bottom),
              ),
              child: SootheBottomBar(children: buttons),
            ),
          ),
        ),
      ),
    );
  }
}
