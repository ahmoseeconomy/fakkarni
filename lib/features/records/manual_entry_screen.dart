import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/db/tables.dart';
import '../../data/repositories/records_repository.dart';
import 'record_kinds.dart';

/// حقول كل نوع — نفس الأعمدة، بكلام مختلف.
class _Fields {
  const _Fields({
    required this.title,
    required this.titleHint,
    this.doctor,
    this.place,
    this.notes,
    this.honesty,
  });

  final String title, titleHint;

  /// null = الحقل مش في الاستمارة دي.
  final String? doctor, place, notes;

  /// سطر بيقول الاستمارة دي **ما بتعملش** إيه.
  final String? honesty;
}

const _fields = <RecordKind, _Fields>{
  RecordKind.imaging: _Fields(
    title: 'نوع الأشعة',
    titleHint: 'مثلاً: أشعة صدر',
    place: 'المركز',
    doctor: 'الدكتور اللي طلبها',
    notes: 'النتيجة أو اللي اتكتب في التقرير',
  ),
  RecordKind.visit: _Fields(
    title: 'التخصص أو سبب الزيارة',
    titleHint: 'مثلاً: باطنة',
    doctor: 'الدكتور',
    place: 'العيادة أو المستشفى',
    notes: 'الدكتور قال إيه',
  ),
  RecordKind.lab: _Fields(
    title: 'اسم التحليل',
    titleHint: 'مثلاً: HbA1c',
    place: 'المعمل',
    doctor: 'الدكتور اللي طلبه',
    notes: 'النتيجة زي ما هي في الورقة',
  ),
  RecordKind.prescription: _Fields(
    title: 'اسمها',
    titleHint: 'مثلاً: روشتة الباطنة',
    doctor: 'الدكتور',
    notes: 'الأدوية اللي فيها',
    honesty: 'ده للتسجيل بس — الأدوية بتتضاف من «ضيف» عشان تتفكّر بيها.',
  ),
  RecordKind.booking: _Fields(
    title: 'الحجز عند مين أو لإيه',
    titleHint: 'مثلاً: كشف عيون',
    doctor: 'الدكتور',
    place: 'المكان',
    notes: 'ملاحظات',
    honesty: 'الحجز ده للتسجيل بس — التطبيق مش هيفكّرك بيه.',
  ),
};

/// «إدخال يدوي» (المخطط ٢٨): خمس استمارات بنفس البدائيات.
///
/// التاريخ شرايح («النهارده»/«امبارح»، أو «بكرة» للحجز) + «تاريخ تاني»
/// بمنتقي تاريخ. الفاضي بيتحفظ فاضي. مفيش مرفقات لسه (D3.6).
class ManualEntryScreen extends StatefulWidget {
  const ManualEntryScreen({this.kind = RecordKind.imaging, this.today, super.key});

  final RecordKind kind;

  /// للاختبارات.
  final DateTime? today;

  @override
  State<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ManualEntryScreenState extends State<ManualEntryScreen> {
  late RecordKind _kind = widget.kind;
  final _title = TextEditingController();
  final _doctor = TextEditingController();
  final _place = TextEditingController();
  final _notes = TextEditingController();
  late DateTime _date = _today;
  String? _patientName;
  bool _saving = false;

  DateTime get _today {
    final n = widget.today ?? DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_patientName != null) return;
    final services = AppScope.of(context);
    services.routines.getPatient(services.patientId).then((p) {
      if (mounted) setState(() => _patientName = p?.name ?? '');
    });
  }

  @override
  void dispose() {
    for (final c in [_title, _doctor, _place, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1950),
      lastDate: DateTime(_today.year + 2, 12, 31),
      locale: const Locale('ar'),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final services = AppScope.of(context);
    final f = _fields[_kind]!;
    await RecordsRepository(services.db).add(
      patientId: services.patientId,
      kind: _kind,
      title: _title.text,
      happenedAt: _date,
      doctor: f.doctor == null ? null : _doctor.text,
      place: f.place == null ? null : _place.text,
      notes: f.notes == null ? null : _notes.text,
    );
    if (mounted) Navigator.of(context).pop(true);
  }

  InputDecoration _decoration(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: TextStyle(fontSize: F.minTextSize, color: F.mutedDark),
        hintStyle: TextStyle(fontSize: F.minTextSize, color: F.mutedDark),
        filled: true,
        fillColor: F.fieldGround,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(F.radiusCard)),
      );

  @override
  Widget build(BuildContext context) {
    final f = _fields[_kind]!;
    final body = TextStyle(fontSize: F.minBodySize, color: F.ink);
    final name = _patientName;
    final yesterday = DateTime(_today.year, _today.month, _today.day - 1);
    final tomorrow = DateTime(_today.year, _today.month, _today.day + 1);
    final quick = _kind == RecordKind.booking
        ? [('النهارده', _today), ('بكرة', tomorrow)]
        : [('النهارده', _today), ('امبارح', yesterday)];
    final onQuick = quick.any((q) => q.$2 == _date);

    Widget field(TextEditingController c, String label, {String? hint, Key? key, int? lines = 1}) => Padding(
          padding: const EdgeInsets.only(bottom: F.s12),
          child: TextField(
            // **حقل متعدد السطور بياخد `newline`** — لو أخد `done` زرار
            // السطر الجديد في الكيبورد بيتحوّل لـ«تم» والواحد ما يقدرش
            // ينزل سطر أصلاً. الباقي `done`: مفيش حقل بعده.
            textInputAction: lines == 1 ? TextInputAction.done : TextInputAction.newline,
            key: key,
            controller: c,
            style: body,
            maxLines: lines,
            decoration: _decoration(label, hint: hint),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('إدخال يدوي')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(F.gap, F.s4, F.gap, F.s30),
        children: [
          Wrap(
            spacing: F.s8,
            runSpacing: F.s8,
            children: [
              for (final k in RecordKind.values)
                AnchorChip(
                  key: ValueKey('kind-${k.name}'),
                  label: k.label,
                  selected: _kind == k,
                  onTap: () => setState(() => _kind = k),
                ),
            ],
          ),
          const SizedBox(height: F.gap),
          Row(
            children: [
              Icon(_kind.icon, size: 30, color: F.green),
              const SizedBox(width: F.s8),
              Text(
                _kind.label,
                style: TextStyle(
                  fontFamily: F.displayFamily,
                  fontSize: F.screenTitleSize,
                  fontWeight: FontWeight.w700,
                  color: F.ink,
                ),
              ),
            ],
          ),
          if (f.honesty != null) ...[
            const SizedBox(height: F.s4),
            Text(f.honesty!, style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5)),
          ],
          const SizedBox(height: F.gap),
          field(_title, f.title, hint: f.titleHint, key: const ValueKey('record-title')),
          if (f.doctor != null) field(_doctor, f.doctor!, key: const ValueKey('record-doctor')),
          if (f.place != null) field(_place, f.place!, key: const ValueKey('record-place')),
          const SectionHead('التاريخ'),
          const SizedBox(height: F.s8),
          Wrap(
            spacing: F.s8,
            runSpacing: F.s8,
            children: [
              for (final (label, day) in quick)
                AnchorChip(label: label, selected: _date == day, onTap: () => setState(() => _date = day)),
              AnchorChip(
                label: onQuick ? 'تاريخ تاني' : arabicDate(_date),
                selected: !onQuick,
                onTap: _pickDate,
              ),
            ],
          ),
          const SizedBox(height: F.gap),
          if (f.notes != null) field(_notes, f.notes!, key: const ValueKey('record-notes'), lines: null),
          const SizedBox(height: F.s8),
          FPrimaryButton(
            label: name == null || name.isEmpty || name == 'أنا' ? 'احفظ في الملف' : 'احفظ في ملف $name',
            onPressed: _saving || _title.text.trim().isEmpty ? null : _save,
          ),
        ],
      ),
    );
  }
}
