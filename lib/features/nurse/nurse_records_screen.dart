import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/format/arabic_time.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/f_sheet.dart';
import '../../core/widgets/primitives.dart';
import '../../data/care/caregiver_remote.dart';
import '../../data/db/tables.dart' show RecordKind;
import '../../domain/care/medication_change.dart';
import '../../domain/health/follow_display.dart';
import '../care/caregiver_status.dart';
import '../care/caregiver_words.dart' show labLineText, labRangeLine, recordKindLabel;
import '../records/health_file_screen.dart' show NewAppointmentBody, NewAppointmentResult;
import '../records/record_kinds.dart' show RecordKindWords;
import 'nurse_controller.dart';
import 'nurse_doctor_screen.dart';
import 'nurse_header.dart';
import 'nurse_widgets.dart';

/// **«السجل» بتاع المريض** — نفس التلات أقسام اللي على موبايله:
/// «مواعيدك الجاية» / «أوراقك» / «للدكتور».
///
/// الإضافة (لو المريض سمح بالتعديل): «ميعاد جديد» و«ورقة جديدة» — طلبات
/// بتتطبّق على موبايله بنفس سكّته (الميعاد بيبقى متابعة بإشعاراتها هناك).
class NurseRecordsScreen extends StatelessWidget {
  const NurseRecordsScreen({required this.controller, this.now, super.key});

  final NurseController controller;
  final DateTime? now;

  Future<void> _newAppointment(BuildContext context, DateTime today) async {
    final result = await FSheet.show<NewAppointmentResult>(
      context,
      title: 'ميعاد جديد',
      children: [NewAppointmentBody(today: today, allowFromPaper: false)],
    );
    if (result == null) return;
    await controller.submit(
      kind: MedicationChangeKind.appointment,
      payload: MedicationChangePayload(name: result.title, followKind: result.kind.name, day: result.day),
    );
  }

  Future<void> _newRecord(BuildContext context, DateTime today) async {
    final result = await FSheet.show<MedicationChangePayload>(
      context,
      title: 'ورقة جديدة',
      children: [_NewRecordBody(today: today)],
    );
    if (result == null) return;
    await controller.submit(kind: MedicationChangeKind.record, payload: result);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([controller, controller.holder]),
        builder: (context, _) {
          final snapshot = controller.holder.snapshot;
          if (snapshot == null) return const SizedBox.shrink();
          final t = now ?? DateTime.now();
          final today = DateTime(t.year, t.month, t.day);
          final upcoming = [
            for (final f in careFollowUps(snapshot, t))
              if (f.stageDate case final at? when !at.isBefore(today)) f,
          ]..sort((a, b) => a.stageDate!.compareTo(b.stageDate!));
          final openUuids = {
            for (final f in careFollowUps(snapshot, t)) f.record.uuid,
          };
          final papers = [
            for (final r in snapshot.records)
              if (!openUuids.contains(r.uuid)) r,
          ]..sort((a, b) => b.happenedAt.compareTo(a.happenedAt));
          final canEdit = controller.canEdit;

          final children = <Widget>[
            const FSectionHead('مواعيدك الجاية'),
            const SizedBox(height: F.s8),
            if (upcoming.isEmpty) const NurseQuietLine('مفيش مواعيد جاية.'),
            for (final f in upcoming)
              Padding(
                padding: const EdgeInsets.only(bottom: F.s10),
                child: FCard(
                  key: ValueKey('nurse-appt-${f.record.uuid}'),
                  padding: const EdgeInsets.all(F.s14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(followDisplayTitle(f.kind, f.record.title),
                          style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink)),
                      Text(followDateFull(f.stageDate, t),
                          style: TextStyle(fontSize: F.minTextSize, color: F.ink, height: 1.4)),
                      Text(f.stage.label, style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark)),
                    ],
                  ),
                ),
              ),
            if (canEdit)
              FSecondaryButton(
                key: const ValueKey('nurse-new-appointment'),
                label: 'ميعاد جديد',
                onPressed: () => _newAppointment(context, today),
              ),
            const SizedBox(height: F.gap),
            const FSectionHead('أوراقك'),
            const SizedBox(height: F.s8),
            if (papers.isEmpty) const NurseQuietLine('لسه مفيش أوراق.'),
          ];
          DateTime? lastDay;
          for (final r in papers) {
            final day = DateTime(r.happenedAt.year, r.happenedAt.month, r.happenedAt.day);
            if (day != lastDay) {
              lastDay = day;
              children.add(Padding(
                padding: const EdgeInsets.only(top: F.s4, bottom: F.s6),
                child: Text(arabicDate(day),
                    style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.mutedDark)),
              ));
            }
            children.add(_PaperRow(record: r, controller: controller));
          }
          children.addAll([
            if (canEdit)
              FSecondaryButton(
                key: const ValueKey('nurse-new-record'),
                label: 'ورقة جديدة',
                onPressed: () => _newRecord(context, today),
              ),
            const SizedBox(height: F.gap),
            const FSectionHead('للدكتور'),
            const SizedBox(height: F.s8),
            FSecondaryButton(
              key: const ValueKey('nurse-doctor-page'),
              label: 'صفحة الدكتور والملف',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => NurseDoctorScreen(holder: controller.holder, now: now),
              )),
            ),
            if (controller.pending.isNotEmpty) ...[
              const SizedBox(height: F.gap),
              for (final c in controller.pending) NurseQuietLine(NurseController.pendingLine(c)),
            ],
            if (controller.error case final e?) ...[
              const SizedBox(height: F.s10),
              GoldNote(e),
            ],
          ]);
          return ListView(
            padding: EdgeInsets.fromLTRB(F.gap, F.s8, F.gap, F.gap + MediaQuery.of(context).padding.bottom),
            children: children,
          );
        },
      );
}

class _PaperRow extends StatelessWidget {
  const _PaperRow({required this.record, required this.controller});

  final CaregiverRecord record;
  final NurseController controller;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: F.s10),
        child: Material(
          color: F.cardGround,
          borderRadius: BorderRadius.circular(F.radiusCard),
          child: InkWell(
            key: ValueKey('nurse-paper-${record.uuid}'),
            borderRadius: BorderRadius.circular(F.radiusCard),
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => NurseRecordScreen(record: record, controller: controller),
            )),
            child: Container(
              constraints: const BoxConstraints(minHeight: F.minTapTarget),
              padding: const EdgeInsets.all(F.s14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(record.title, style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink)),
                  Text(
                    [recordKindLabel(record.kind), ?record.doctor, ?record.place].join(' — '),
                    style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

/// ورقة واحدة: كل حقولها، سطور التحليل بنطاق الورقة، والصورة لو المريض
/// شاركها — وإلا «الصورة على موبايل المريض».
class NurseRecordScreen extends StatelessWidget {
  const NurseRecordScreen({required this.record, required this.controller, super.key});

  final CaregiverRecord record;
  final NurseController controller;

  /// الورق اللي عادةً بيتصوّر — السطر ده بيتقال عليه بس. ورقة اتكتبت بالإيد
  /// غالباً مالهاش صورة، و«الصورة على موبايل المريض» عنها كانت هتبقى كدبة.
  static const _usuallyPhotographed = {'prescription', 'lab', 'imaging'};

  @override
  Widget build(BuildContext context) {
    final holder = controller.holder;
    final shared = holder.snapshot?.sharedPapers.contains(record.uuid) ?? false;
    final photos = holder.remote is PaperPhotos ? holder.remote as PaperPhotos : null;
    Widget field(String label, String? value) => value == null || value.trim().isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: F.s6),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '$label: ', style: TextStyle(color: F.mutedDark, fontWeight: FontWeight.w600)),
                TextSpan(text: value.trim(), style: TextStyle(color: F.ink)),
              ]),
              style: TextStyle(fontSize: F.minTextSize, height: 1.45),
            ),
          );
    return Scaffold(
      appBar: NurseHeader(holder: holder),
      body: ListView(
        padding: const EdgeInsets.all(F.gap),
        children: [
          NurseScreenTitle(record.title),
          field('النوع', recordKindLabel(record.kind)),
          field('التاريخ', arabicDate(record.happenedAt)),
          field('الدكتور', record.doctor),
          field('المكان', record.place),
          if (record.labLines.isEmpty) field('ملاحظات', record.notes),
          for (final l in record.labLines)
            Padding(
              padding: const EdgeInsets.only(bottom: F.s6),
              child: Text('${labLineText(l)}\n${labRangeLine(l)}',
                  style: TextStyle(fontSize: F.minTextSize, color: F.ink, height: 1.45)),
            ),
          const SizedBox(height: F.s12),
          if (shared && photos != null)
            FutureBuilder<List<int>?>(
              future: photos.download(holder.snapshot?.patient.uuid ?? '', record.uuid),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return Center(child: CircularProgressIndicator(color: F.green));
                }
                final bytes = snap.data;
                if (bytes == null) return const NurseQuietLine('الصورة ما نزلتش دلوقتي — جرّب تاني.');
                return InteractiveViewer(
                  maxScale: 5,
                  child: Image.memory(Uint8List.fromList(bytes), key: const ValueKey('nurse-paper-photo')),
                );
              },
            )
          else if (_usuallyPhotographed.contains(record.kind))
            const NurseQuietLine('الصورة على موبايل المريض', key: ValueKey('nurse-photo-on-phone')),
        ],
      ),
    );
  }
}

/// «ورقة جديدة» — النوع والعنوان والتاريخ، والدكتور والملاحظات لو حابب.
class _NewRecordBody extends StatefulWidget {
  const _NewRecordBody({required this.today});

  final DateTime today;

  @override
  State<_NewRecordBody> createState() => _NewRecordBodyState();
}

class _NewRecordBodyState extends State<_NewRecordBody> {
  static const _kinds = [RecordKind.prescription, RecordKind.visit, RecordKind.lab, RecordKind.imaging];
  RecordKind _kind = RecordKind.visit;
  late DateTime _date = widget.today;
  final _title = TextEditingController();
  final _doctor = TextEditingController();
  final _notes = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _doctor.dispose();
    _notes.dispose();
    super.dispose();
  }

  InputDecoration _decoration(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: F.fieldGround,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(F.radiusCard)),
      );

  @override
  Widget build(BuildContext context) {
    final yesterday = DateTime(widget.today.year, widget.today.month, widget.today.day - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: F.s8,
          runSpacing: F.s8,
          children: [
            for (final k in _kinds)
              AnchorChip(
                key: ValueKey('nurse-record-kind-${k.name}'),
                label: k.label,
                selected: _kind == k,
                onTap: () => setState(() => _kind = k),
              ),
          ],
        ),
        const SizedBox(height: F.s12),
        TextField(
          key: const ValueKey('nurse-record-title'),
          controller: _title,
          textInputAction: TextInputAction.next,
          style: TextStyle(fontSize: F.minBodySize, color: F.ink),
          decoration: _decoration('العنوان — زي: كشف القلب'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: F.s8),
        TextField(
          controller: _doctor,
          textInputAction: TextInputAction.next,
          style: TextStyle(fontSize: F.minBodySize, color: F.ink),
          decoration: _decoration('الدكتور (لو حابب)'),
        ),
        const SizedBox(height: F.s8),
        TextField(
          controller: _notes,
          textInputAction: TextInputAction.newline,
          maxLines: 3,
          style: TextStyle(fontSize: F.minBodySize, color: F.ink),
          decoration: _decoration('ملاحظات (لو حابب)'),
        ),
        const SizedBox(height: F.s12),
        Wrap(
          spacing: F.s8,
          runSpacing: F.s8,
          children: [
            AnchorChip(label: 'النهارده', selected: _date == widget.today, onTap: () => setState(() => _date = widget.today)),
            AnchorChip(label: 'امبارح', selected: _date == yesterday, onTap: () => setState(() => _date = yesterday)),
            AnchorChip(
              label: _date != widget.today && _date != yesterday ? arabicDate(_date) : 'يوم تاني',
              selected: _date != widget.today && _date != yesterday,
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(widget.today.year - 20),
                  lastDate: widget.today,
                );
                if (picked != null) setState(() => _date = picked);
              },
            ),
          ],
        ),
        const SizedBox(height: F.gap),
        FPrimaryButton(
          key: const ValueKey('nurse-record-save'),
          label: 'ابعتها لموبايله',
          onPressed: _title.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(MedicationChangePayload(
                    name: _title.text.trim(),
                    recordKind: _kind.name,
                    happenedAt: _date,
                    doctor: _doctor.text.trim().isEmpty ? null : _doctor.text.trim(),
                    notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
                  )),
        ),
      ],
    );
  }
}
