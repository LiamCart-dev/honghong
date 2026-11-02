import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/app_clock.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_icon.dart';
import '../../core/widgets/hh_widgets.dart';
import '../../data/db/app_database.dart';
import '../../domain/health/health.dart';
import '../soothe/soothe_widgets.dart';
import 'health_providers.dart';

Future<bool> showMedSheet(BuildContext context, {HealthLog? existing}) async {
  final r = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    useSafeArea: true,
    builder: (_) => MedSheet(existing: existing),
  );
  return r == true;
}

class MedSheet extends ConsumerStatefulWidget {
  const MedSheet({super.key, this.existing});
  final HealthLog? existing;
  @override
  ConsumerState<MedSheet> createState() => _MedSheetState();
}

class _MedSheetState extends ConsumerState<MedSheet> {
  late DateTime _at;
  late MedKind _kind;
  late TextEditingController _name;
  late TextEditingController _dose;
  String? _note;
  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _at = e?.at ?? AppClock.now();
    _kind = e?.medKind != null ? MedKind.values.byName(e!.medKind!) : MedKind.drug;
    _name = TextEditingController(text: e?.medName ?? '');
    _dose = TextEditingController(text: e?.medDose ?? '');
    _note = e?.note;
  }

  @override
  void dispose() {
    _name.dispose();
    _dose.dispose();
    super.dispose();
  }

  String? get _timeError {
    final n = AppClock.now();
    if (_at.isAfter(n)) return '时间不能晚于现在';
    if (_at.isBefore(n.subtract(const Duration(days: 365)))) return '最早可记 365 天前';
    return null;
  }

  bool get _canSave => _name.text.trim().isNotEmpty && _timeError == null && _name.text.trim().length <= 20 && _dose.text.trim().length <= 20;

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

  Future<void> _customName() async {
    final ctl = TextEditingController(text: _name.text);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('药名'),
        content: TextField(controller: ctl, autofocus: true, maxLength: 20),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('确定')),
        ],
      ),
    );
    if (v == null) return;
    setState(() => _name.text = v);
  }

  Future<void> _save() async {
    if (!_canSave) return;
    final baby = await ref.read(currentBabyProvider.future);
    final repo = ref.read(healthLogRepositoryProvider);
    final name = _name.text.trim();
    final dose = _dose.text.trim().isEmpty ? null : _dose.text.trim();
    try {
      if (_editing) {
        await repo.update(
          widget.existing!.id,
          at: _at,
          medKind: _kind,
          medName: name,
          medDose: dose,
          note: _note,
        );
      } else {
        await repo.add(
          babyId: baby.id,
          kind: HealthKind.medication,
          at: _at,
          medKind: _kind,
          medName: name,
          medDose: dose,
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
    final all = ref.watch(allHealthLogsProvider).value ?? const <HealthLog>[];
    final medReadings = [
      for (final h in all)
        if (h.kind == HealthKind.medication.name && h.medKind != null)
          MedReading(at: h.at, kind: MedKind.values.byName(h.medKind!), name: h.medName ?? ''),
    ];
    final recent = recentDrugNames(medReadings);
    // 编辑时若命中的就是自己，不算重复
    HealthLog? dupLog;
    if (_name.text.trim().isNotEmpty) {
      final n = _name.text.trim();
      for (final h in all) {
        if (h.kind != HealthKind.medication.name) continue;
        if (_editing && h.id == widget.existing!.id) continue;
        if (h.medKind != _kind.name) continue;
        if ((h.medName ?? '').trim() != n) continue;
        if (h.at.difference(_at).abs() <= const Duration(minutes: 5)) {
          dupLog = h;
          break;
        }
      }
    }
    final timeErr = _timeError;
    final kb = MediaQuery.viewInsetsOf(context).bottom;
    Widget label(String s) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 10),
          child: Text(s, style: TextStyle(fontSize: 13, color: c.sub)),
        );

    final items = <Widget>[
      const SheetGrab(),
      Row(children: [
        IconTile(AppIcon.healthMed, size: 48, radius: 16, fontSize: 26, bg: c.peachL),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_editing ? '修改用药' : '记用药', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.ink)),
            const SizedBox(height: 2),
            Text(cfg.copy.medSubtitle, style: TextStyle(fontSize: 13, color: c.sub)),
          ]),
        ),
      ]),
      label('类型'),
      HhSegmented<MedKind>(
        values: MedKind.values,
        label: (k) => k == MedKind.drug ? '药品' : '补充剂',
        selected: _kind,
        onChanged: (k) => setState(() => _kind = k),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(cfg.copy.medSupplementHint, style: TextStyle(fontSize: 12, color: c.sub, height: 1.5)),
      ),
      label('药名 · 最近用过的'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final n in recent)
          HhChip(label: n, on: _name.text.trim() == n, onTap: () => setState(() => _name.text = n)),
        HhChip(
          label: _name.text.trim().isNotEmpty && !recent.contains(_name.text.trim()) ? _name.text.trim() : '＋ 填写药名',
          on: _name.text.trim().isNotEmpty && !recent.contains(_name.text.trim()),
          onTap: _customName,
        ),
      ]),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text('不预置药名，只显示你记过的；药名最多 20 字', style: TextStyle(fontSize: 12, color: c.sub)),
      ),
      label('剂量（可选）'),
      TextField(
        key: const Key('med-dose'),
        controller: _dose,
        maxLength: 20,
        decoration: InputDecoration(
          hintText: '例如 5ml',
          counterText: '',
          filled: true,
          fillColor: c.card,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.line, width: 1.5)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c.line, width: 1.5)),
        ),
        onChanged: (_) => setState(() {}),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(cfg.copy.medDoseHint, style: TextStyle(fontSize: 12, color: c.sub)),
      ),
      label('时间'),
      InkWell(
        key: const Key('med-time'),
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
            Text('用药时间', style: TextStyle(fontSize: 14, color: c.sub)),
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
      if (dupLog != null)
        Container(
          key: const Key('med-dup'),
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(color: const Color(0xFFFFF1C9), borderRadius: BorderRadius.circular(12)),
          child: Text(
            '${DateFormat('HH:mm').format(dupLog.at)} 已经记过一次 ${_name.text.trim()}，确认不是重复再保存',
            style: const TextStyle(fontSize: 12, color: Color(0xFF8A6A12)),
          ),
        ),
      label('备注（可选）'),
      Wrap(children: [
        HhChip(label: _note == null ? '添加备注' : _note!, on: _note != null, onTap: _customNote),
      ]),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
        child: Text('只做记录，不提供用药建议，也不计算剂量。', style: TextStyle(fontSize: 12, color: c.sub, height: 1.5)),
      ),
      const SizedBox(height: 8),
    ];

    final big = largeText(context);
    final buttons = <Widget>[
      if (big) ...[
        HhButton(key: const Key('med-save'), label: '保存', onPressed: _canSave ? _save : null),
        const SizedBox(height: 10),
        HhButton(label: '取消', primary: false, onPressed: () => Navigator.pop(context, false)),
      ] else
        Row(children: [
          Expanded(flex: 9, child: HhButton(label: '取消', primary: false, onPressed: () => Navigator.pop(context, false))),
          const SizedBox(width: 12),
          Expanded(flex: 11, child: HhButton(key: const Key('med-save'), label: '保存', onPressed: _canSave ? _save : null)),
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
