import '../../domain/scheduling/minute_of_day.dart';
import '../medication/dose_editor.dart' show QuickTimeChips;
import '../../core/widgets/f_wheels.dart';
import '../voice/help_button.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../ai/appointment_paper_reader.dart';
import '../../ai/prescription_reader.dart' show PrescriptionReadException;
import '../../core/diagnostics.dart';
import '../../domain/billing/family_plan.dart' show AppFeature;
import '../billing/feature_gate.dart';
import '../scan/scan_prescription_screen.dart' show PickImage, pickWithSystemCamera;

import '../medication/not_bought.dart';

import '../../data/repositories/vitals_repository.dart';
import '../../domain/health/vitals.dart';
import '../health/vitals/vital_entry_sheet.dart';
import '../health/vitals/vital_history.dart';
import '../health/vitals/vital_history_screen.dart';

import '../../app/app_scope.dart';
import '../../core/format/arabic_time.dart';
import '../../core/format/name_direction.dart';
import '../../domain/health/follow_display.dart';
import '../../domain/places/specialty.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/f_sheet.dart';
import '../../core/widgets/primitives.dart';
import '../../data/db/app_database.dart';
import '../../data/db/tables.dart';
import '../../data/repositories/records_repository.dart';
import '../../data/services/appointment_card.dart';
import '../../data/services/checkup_service.dart';
import '../../domain/health/follow_up.dart';
import '../doctor/doctor_page_screen.dart';
import 'calendar_screen.dart';
import 'change_history_screen.dart';
import 'checkup_screen.dart';
import 'records_empty.dart';
import 'history_screen.dart';
import 'manual_entry_screen.dart';
import 'record_row_card.dart';
import 'records_of_kind_screen.dart';
import 'start_follow_up.dart';
import '../adherence/weekly_summary_card.dart';
import 'record_kinds.dart';

/// «الملف الصحي» (المخطط ١٣): بحث بالاسم والدكتور والتاريخ، و«⋯ خيارات»
/// لكل صف → «امسحه» بتأكيد.
///
/// **الشاشة دي بتفرّج وبتتابع، ما بتضيفش.** «صوّر تقرير تحليل» كانت هنا
/// كمان وهي أصلاً في شيت «ضيف» — والإضافة عايشة هناك. بابين لنفس الحاجة
/// بيخلّوا الواحد يسأل هما اتنين ولا واحدة.
///
/// المسح بيمسح: الصف بيختفي من هنا في لحظته. مفيش شاشة
/// «محذوفات» — الكلام ما بيوعدش بيها. «استخراج الملف» بييجي في D3.8،
/// و«نشطة/منتهية» بتاعة التصميم جاية من الأدوية مش السجلات فمش هنا.
/// اختيار صورة ورقة الميعاد — **من غير ما الملف يفضل** (الصورة مش بتتحفظ).
/// متغيّر عشان الاختبارات تبدّله.
PickImage pickAppointmentPaper = (source) => pickWithSystemCamera(source, deleteFile: true);

class HealthFileScreen extends StatefulWidget {
  const HealthFileScreen({this.today, super.key});

  /// للاختبارات.
  final DateTime? today;

  @override
  State<HealthFileScreen> createState() => _HealthFileScreenState();
}

class _HealthFileScreenState extends State<HealthFileScreen> {
  Stream<List<RecordRow>>? _records;
  Stream<List<Vital>>? _vitals;
  final _query = TextEditingController();

  RecordsRepository get _repo => RecordsRepository(AppScope.of(context).db);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _records ??= _repo.watchAll(AppScope.of(context).patientId);
    _vitals ??= VitalsRepository(AppScope.of(context).db).watch(AppScope.of(context).patientId);
  }

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _openCheckup(int id) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => CheckupScreen(recordId: id)),
      );

  /// «عندي روشتة/تقرير — ابدأ منها»: من ورقة في الملف، أو صورة بتتقري
  /// **للميعاد بس**. الكتابة بالإيد مش هنا — هي ورقة «ميعاد جديد» نفسها.
  Future<void> _startFollowUp(FollowKind kind) async {
    final reader = AppScope.of(context).appointmentPaperReader;
    final way = await askStartWay(context, kind, canRead: reader != null);
    if (way == null || !mounted) return;
    switch (way) {
      case StartFollowUpWay.fromFile:
        await _startFromFile(kind);
      case StartFollowUpWay.fromCamera:
        await _appointmentFromPaper(kind, ImageSource.camera);
      case StartFollowUpWay.fromGallery:
        await _appointmentFromPaper(kind, ImageSource.gallery);
    }
  }

  /// السجل اللي في الملف معاه بياناته خلاص — الاسم والدكتور والتاريخ —
  /// فالمتابعة بتشيلهم وما بنسألش عن حاجة إحنا عارفينها.
  Future<void> _startFromFile(FollowKind kind) async {
    final picked = await pickSource(context, kind, today: widget.today);
    if (picked == null || !mounted) return;
    if (picked.alreadyFollowed) {
      // ورقة واحدة بمتابعة واحدة — بنفتح اللي موجودة مش بنبدأ تانية.
      final open = await AppScope.of(context).checkups.openFollowUpFor(picked.recordId);
      if (open != null && mounted) _openCheckup(open.id);
      return;
    }
    await _startFrom(picked.recordId, kind);
  }

  /// صورة الورقة ← اسم الدكتور والميعاد الجاي ← ورقة «ميعاد جديد» **متعبّية**
  /// والحفظ بزرارها (القاعدة ٤). **ولا دوا بيتضاف، ولا الصورة بتتحفظ.**
  /// مفيش ميعاد جاي مكتوب = جملة واحدة و«ضيفه بإيدك».
  Future<void> _appointmentFromPaper(FollowKind kind, ImageSource source) async {
    final reader = AppScope.of(context).appointmentPaperReader;
    if (reader == null) return;
    if (!await ensureFamilyFeature(context, AppFeature.scans) || !mounted) return;
    final image = await pickAppointmentPaper(source);
    if (image == null || !mounted) return;
    final today = widget.today ?? DateTime.now();
    final navigator = Navigator.of(context);
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ReadingPaperDialog(),
    ));
    AppointmentPaperReading? reading;
    String? failure;
    try {
      reading = await reader.read(image);
    } on Exception catch (e) {
      // اللي اتقرا عمره ما يتسجّل — نوع العطل بس
      diag('Appointment: قراية الورقة وقعت — ${e.runtimeType}');
      failure = e is PrescriptionReadException ? e.message : appointmentPaperUnreadable;
    }
    navigator.pop();
    if (!mounted) return;
    final lab = kind == FollowKind.lab;
    if (reading == null || !reading.hasUpcoming(today)) {
      final message = failure ??
          (reading != null && reading.date != null && !reading.highConfidence
              ? appointmentPaperUnreadable
              : noUpcomingAppointment(lab: lab));
      final byHand = await FSheet.show<bool>(
        context,
        title: lab ? 'التقرير' : 'الروشتة',
        children: [
          Text(message,
              key: const ValueKey('paper-no-appointment'),
              style: TextStyle(fontSize: F.minBodySize, color: F.ink, height: 1.5)),
          const SizedBox(height: F.gap),
          FPrimaryButton(
            key: const ValueKey('paper-add-by-hand'),
            label: 'ضيفه بإيدك',
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      );
      if (byHand == true && mounted) await _newAppointment(initialKind: kind, allowFromPaper: false);
      return;
    }
    await _newAppointment(
      initialKind: kind,
      initialName: reading.name,
      initialDay: reading.date,
      initialTime: reading.time,
      allowFromPaper: false,
      title: 'راجع الميعاد',
    );
  }

  Future<void> _startFrom(int sourceId, FollowKind kind) async {
    final services = AppScope.of(context);
    final source = await (services.db.select(services.db.records)
          ..where((t) => t.id.equals(sourceId)))
        .getSingleOrNull();
    if (source == null || !mounted) return;
    final id = await services.checkups.start(
      patientId: services.patientId,
      kind: kind,
      title: followTitleFrom(kind, source),
      doctor: source.doctor,
      place: source.place,
      // **تاريخ الورقة بتاع الورقة.** كان بيتنسخ على صف المتابعة، فزيارة
      // محجوزة بكرة كانت بتتعرض «١٣ سبتمبر ٢٠٢٣» على كل شاشة بتقرا
      // `happenedAt`. المتابعة بتبدأ **النهارده** (الافتراضي في
      // `CheckupService.start`)، والورقة بتتقال كأصل في سطر تاني عن
      // طريق `followSourceId`.
      fromRecordId: sourceId,
      today: widget.today ?? DateTime.now(),
    );
    if (mounted) _openCheckup(id);
  }


  /// مدخل لكل نوع فيه سجلات، بعدده — والدوسة بتفتح «الحالات السابقة»
  /// على النوع ده.
  ///
  /// بنستعمل شاشة الحالات السابقة نفسها لأنها **عندها فلتر النوع أصلاً**؛
  /// قايمة تانية مخصوصة كانت هتبقى مكان تاني لنفس العرض، حرّ يختلف عنه.
  /// «ميعاد جديد» — سؤالين (دكتور ولا معمل؟ وإمتى؟) والتذكير بيتعمل تحت
  /// من نفس سكّة المتابعة. **مفيش سجل «حجز» بيتكتب من غير تذكير** — ده
  /// الباب اللي كان بيوقّع الراجل قبل كده.
  Future<void> _newAppointment({
    FollowKind? initialKind,
    String? initialName,
    DateTime? initialDay,
    MinuteOfDay? initialTime,
    bool allowFromPaper = true,
    String title = 'ميعاد جديد',
  }) async {
    final today = widget.today ?? DateTime.now();
    final result = await FSheet.show<NewAppointmentResult>(
      context,
      title: title,
      children: [
        NewAppointmentBody(
          today: DateTime(today.year, today.month, today.day),
          initialKind: initialKind,
          initialName: initialName,
          initialDay: initialDay,
          initialTime: initialTime,
          allowFromPaper: allowFromPaper,
        ),
      ],
    );
    if (result == null || !mounted) return;
    if (result.fromPaper) {
      await _startFollowUp(result.kind);
      return;
    }
    final services = AppScope.of(context);
    // نفس الدالة اللي تغيير الممرض المعلّق بيعدّي منها (٠٠٢٦)
    await services.checkups.bookAppointment(
      patientId: services.patientId,
      kind: result.kind,
      title: result.title,
      day: result.day,
      today: today,
      time: result.time,
    );
    await services.refreshAppointments(now: today);
  }

  /// حجز قديم (من قبل الجولة دي) بميعاد جاي: «فكّرني بيه» بيعمله متابعة
  /// زيارة بنفس الميعاد — الصف القديم بيفضل ورقة، والمتابعة بتشاور عليه.
  Future<void> _remindLegacyBooking(RecordRow booking) async {
    final today = widget.today ?? DateTime.now();
    final services = AppScope.of(context);
    final id = await services.checkups.start(
      patientId: services.patientId,
      kind: FollowKind.visit,
      title: booking.title,
      doctor: booking.doctor,
      place: booking.place,
      today: today,
      fromRecordId: booking.id,
    );
    await services.checkups.setStageDate(
      id,
      VisitStage.booked,
      day: DateTime(booking.happenedAt.year, booking.happenedAt.month, booking.happenedAt.day),
      now: today,
    );
    await services.refreshAppointments(now: today);
  }

  /// «فلتر»: الأنواع بعددها (كل مدخل بيفتح قايمته)، و«كل الأوراق بالفترة».
  Future<void> _filter(List<RecordRow> all) {
    final counts = <RecordKind, int>{};
    for (final r in all) {
      counts[r.kind] = (counts[r.kind] ?? 0) + 1;
    }
    return FSheet.show<void>(
      context,
      title: 'فلتر',
      children: [
        for (final kind in RecordKind.values)
          if (counts[kind] case final n? when n > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: F.s8),
              child: InkWell(
                key: ValueKey('kind-entry-${kind.name}'),
                borderRadius: BorderRadius.circular(F.radiusCard),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => RecordsOfKindScreen(kind: kind, today: widget.today),
                  ));
                },
                child: Container(
                  constraints: const BoxConstraints(minHeight: F.minTapTarget),
                  padding: const EdgeInsets.symmetric(horizontal: F.s12),
                  decoration: BoxDecoration(color: F.railGround, borderRadius: BorderRadius.circular(F.radiusCard)),
                  child: Row(
                    children: [
                      Icon(kind.icon, size: 22, color: F.green),
                      const SizedBox(width: F.s10),
                      Expanded(
                        child: Text(kind.plural,
                            style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink)),
                      ),
                      Text(arabicNumber(n),
                          style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.mutedDark)),
                    ],
                  ),
                ),
              ),
            ),
        FSecondaryButton(
          key: const ValueKey('filter-history'),
          label: 'كل الأوراق بالفترة',
          onPressed: () {
            Navigator.of(context).pop();
            Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => HistoryScreen(today: widget.today)),
            );
          },
        ),
      ],
    );
  }

  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    final now = widget.today ?? DateTime.now();
    final today = _dayOf(now);
    // **مفيش شريط علوي** (المالك، ٢٨ سبتمبر ٢٠٢٦): العنوان «ملفّي» كبير على
    // اليمين جوّه الصفحة وبيطلع معاها — زي «يومك» و«الأدوية». و«ساعدني» واحد
    // جنبه بيشرح الأقسام بالترتيب؛ زراير الأقسام مستخبية جوّه الشاشة.
    return Scaffold(
      body: HelpQuiet(
        child: StreamBuilder<List<RecordRow>>(
        stream: _records,
        builder: (context, snap) {
          final all = snap.data;
          final rows = all ?? const <RecordRow>[];
          final query = _query.text.trim();
          final shown = [for (final r in rows) if (matchesQuery(r, query)) r]
            ..sort((a, b) {
              final byDate = b.happenedAt.compareTo(a.happenedAt);
              return byDate != 0 ? byDate : b.id.compareTo(a.id);
            });

          // ---- مواعيدك الجاية: مراحل المتابعات اللي ليها ميعاد، والحجوزات
          // القديمة اللي لسه جاية ومحدش عمل لها متابعة.
          final upcoming = upcomingAppointments(rows, now: now);
          final followed = {for (final r in rows) ?r.followSourceId};
          final legacyBookings = [
            for (final r in rows)
              if (r.kind == RecordKind.booking && !followed.contains(r.id) && !_dayOf(r.happenedAt).isBefore(today)) r,
          ]..sort((a, b) => a.happenedAt.compareTo(b.happenedAt));

          return ListView(
            padding: EdgeInsets.fromLTRB(F.gap, MediaQuery.of(context).padding.top + F.gap, F.gap, F.gap + MediaQuery.of(context).padding.bottom),
            children: [
              HelpRow(
                id: 'help_appointments',
                then: const ['help_papers', 'help_vitals', 'help_doctor'],
                always: true,
                child: Text(
                  'ملفّي',
                  key: const ValueKey('health-file-title'),
                  style: TextStyle(
                    fontFamily: F.displayFamily,
                    fontSize: F.screenTitleSize,
                    fontWeight: FontWeight.w700,
                    color: F.ink,
                  ),
                ),
              ),
              const SizedBox(height: F.gap),
              // ملخص الأسبوع (طلب المدير، ٤ أكتوبر ٢٠٢٦) — آخر ٧ أيام كاملة
              PatientWeeklySummary(now: widget.today),
              const SizedBox(height: F.gap),
              // ============================================ مواعيدك الجاية
              const HelpRow(id: 'help_appointments', child: FSectionHead('مواعيدك الجاية')),
              const SizedBox(height: F.s8),
              if (all != null && upcoming.isEmpty && legacyBookings.isEmpty)
                const RecordsEmpty(
                  key: ValueKey('appointments-empty'),
                  title: 'مفيش مواعيد جاية',
                  how: 'لما يكون عندك دكتور أو معمل، دوس «ميعاد جديد» ونفكّرك.',
                ),
              for (final a in upcoming)
                _AppointmentRow(
                  key: ValueKey('upcoming-${a.recordId}-${a.stage.number}'),
                  title: a.displayTitle,
                  line: '${a.headline} — ${countdownWord(now, a.at)} — ${arabicDate(a.at)}',
                  onTap: () => _openCheckup(a.recordId),
                ),
              for (final b in legacyBookings)
                _AppointmentRow(
                  key: ValueKey('legacy-booking-${b.id}'),
                  title: b.title,
                  line: [?b.doctor, ?b.place, '${countdownWord(now, b.happenedAt)} — ${arabicDate(b.happenedAt)}'].join(' — '),
                  actionLabel: 'فكّرني بيه',
                  onAction: () => _remindLegacyBooking(b),
                ),
              const SizedBox(height: F.s10),
              FPrimaryButton(
                key: const ValueKey('new-appointment'),
                label: 'ميعاد جديد',
                onPressed: _newAppointment,
              ),
              const SizedBox(height: F.gap),

              // ============================== أدوية لسه ماتشترتش (لو فيه)
              const NotBoughtSection(),

              // ================================================= أوراقك
              const HelpRow(id: 'help_papers', child: FSectionHead('أوراقك')),
              const SizedBox(height: F.s8),
              // تسجيل زيارة أو تحليل أو أشعة بالإيد — **هنا**، مش في «ضيف»
              // (طلب المالك، ٢٩ سبتمبر ٢٠٢٦). الاستمارة فيها صورة الروشتة أو
              // التقرير (كاميرا أو من الصور) — بتتحفظ وبس.
              FSecondaryButton(
                key: const ValueKey('papers-new'),
                label: 'سجّل زيارة أو تحليل أو أشعة',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => ManualEntryScreen(kind: RecordKind.visit, today: widget.today)),
                ),
              ),
              const SizedBox(height: F.s8),
              _SearchBar(
                search: TextField(
                  textInputAction: TextInputAction.search,
                  key: const ValueKey('records-search'),
                  controller: _query,
                  style: TextStyle(fontSize: F.minBodySize, color: F.ink),
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search, color: F.mutedDark),
                    hintText: 'دوّر',
                    hintStyle: TextStyle(fontSize: F.minTextSize, color: F.mutedDark),
                    filled: true,
                    fillColor: F.railGround,
                    contentPadding: const EdgeInsets.symmetric(horizontal: F.s10, vertical: F.s12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(F.radiusCard),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                filter: _WordButton(
                  key: const ValueKey('records-filter'),
                  label: 'فلتر',
                  onTap: all == null || all.isEmpty ? null : () => _filter(all),
                ),
                calendar: _WordButton(
                  key: const ValueKey('records-calendar'),
                  label: 'التقويم',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => CalendarScreen(today: widget.today)),
                  ),
                ),
              ),
              const SizedBox(height: F.s12),
              if (all == null)
                const SizedBox.shrink()
              else if (all.isEmpty)
                const RecordsEmpty(
                  key: ValueKey('papers-empty'),
                  title: 'لسه مفيش أوراق',
                  how: 'صوّر روشتة أو تحليل من «ضيف»، وهتتحفظ هنا لوحدها.',
                )
              else if (shown.isEmpty)
                const RecordsEmpty(
                  title: 'مفيش حاجة بالكلام ده',
                  how: 'جرّب اسم الدكتور، أو الشهر زي «أغسطس»، أو امسح البحث.',
                )
              else
                // **كل الأنواع مع بعض، الأحدث فوق، وعنوان لكل يوم**: الزيارة
                // والروشتة اللي اتكتبت في نفس اليوم جنب بعض — دي إجابة
                // «وريني كل حاجة من آخر زيارة».
                for (final (i, r) in shown.indexed) ...[
                  if (i == 0 || _dayOf(shown[i - 1].happenedAt) != _dayOf(r.happenedAt))
                    Padding(
                      padding: EdgeInsets.only(top: i == 0 ? 0 : F.s6, bottom: F.s6),
                      child: Text(
                        arabicDate(r.happenedAt),
                        key: ValueKey('day-head-${r.happenedAt.year}-${r.happenedAt.month}-${r.happenedAt.day}'),
                        style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.mutedDark),
                      ),
                    ),
                  RecordRowCard(record: r, today: widget.today),
                ],
              const SizedBox(height: F.gap),

              // ================================================= قياساتك
              // الضغط والنبض والوزن والأكسجين والحرارة: آخر رقم لكل نوع،
              // والدوسة بتفتح تاريخه. أرقام وبس — مفيش حكم ولا لون.
              const HelpRow(id: 'help_vitals', child: FSectionHead('قياساتك')),
              const SizedBox(height: F.s8),
              StreamBuilder<List<Vital>>(
                stream: _vitals,
                builder: (context, snap) {
                  final vitals = snap.data ?? const <Vital>[];
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (vitals.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: F.s8),
                          child: Text('لسه مفيش قياسات — الضغط والنبض والوزن والأكسجين والحرارة بيتسجّلوا من هنا.',
                              style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.5)),
                        )
                      else
                        VitalsSummary(
                          vitals: vitals,
                          onOpen: (kind) => Navigator.of(context).push(MaterialPageRoute<void>(
                            builder: (_) => VitalHistoryScreen(kind: kind, now: widget.today),
                          )),
                        ),
                      FSecondaryButton(
                        key: const ValueKey('records-add-vital'),
                        label: 'سجّل قياس',
                        onPressed: () => showVitalEntrySheet(context, now: widget.today),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: F.gap),

              // ================================================= التعديلات (0035)
              // اللي عيلتك أو ممرضك غيّروه — مين وإيه وإمتى. من غير سحابة مفيش صف.
              if (AppScope.of(context).medChanges case final remote?) ...[
                FSecondaryButton(
                  key: const ValueKey('changes-history-entry'),
                  label: 'التعديلات',
                  onPressed: () async {
                    final services = AppScope.of(context);
                    final patient = await services.patients.getPatient(services.patientId);
                    if (patient == null || !context.mounted) return;
                    await Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => ChangeHistoryScreen(patientUuid: patient.uuid, remote: remote, now: widget.today),
                    ));
                  },
                ),
                const SizedBox(height: F.gap),
              ],

              // ================================================= للدكتور
              const HelpRow(id: 'help_doctor', child: FSectionHead('للدكتور')),
              const SizedBox(height: F.s8),
              FCard(
                key: const ValueKey('for-doctor-entry'),
                child: InkWell(
                  borderRadius: BorderRadius.circular(F.radiusCard),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const DoctorPageScreen()),
                  ),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: F.minTapTarget),
                    alignment: AlignmentDirectional.centerStart,
                    child: Row(
                      children: [
                        Icon(Icons.medical_information_outlined, size: 22, color: F.green),
                        const SizedBox(width: F.s10),
                        Expanded(
                          child: Text(
                            'اللي تورّيه للدكتور: أدويتك وتحاليلك وأسئلتك — واطبع الملف من هناك.',
                            style: TextStyle(fontSize: F.minTextSize, color: F.ink, height: 1.5),
                          ),
                        ),
                        const SizedBox(width: F.s6),
                        Text('افتح',
                            style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.green)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      ),
    );
  }
}

/// اسم الميعاد اللي بيتحفظ — **التخصص جوّه الاسم** (قرار المالك، ٢٩ سبتمبر
/// ٢٠٢٦: مفيش عمود ومفيش هجرة): «د. حسن — باطنة»، «دكتور باطنة» من غير اسم،
/// والاسم لوحده لو فيه التخصص خلاص («عيادة العيون» + عيون). من غير الاتنين:
/// «زيارة دكتور» / «تحليل» زي ما كان.
String bookingTitle(FollowKind kind, String typedName, Specialty? specialty) {
  final name = typedName.trim();
  if (kind == FollowKind.lab) return name.isEmpty ? 'تحليل' : name;
  if (specialty == null) return name.isEmpty ? 'زيارة دكتور' : name;
  if (name.isEmpty) return specialty.doctorWord;
  if (specialtiesOf(name: name).contains(specialty)) return name;
  return '$name — ${specialty.label}';
}

/// نتيجة «ميعاد جديد»: نوعه واسمه ويومه — أو «عندي ورقة» فبنفتح الطرق التلاتة القديمة.
class NewAppointmentResult {
  const NewAppointmentResult({
    required this.kind,
    required this.title,
    required this.day,
    this.time,
    this.fromPaper = false,
    this.name,
    this.specialty,
  });

  final FollowKind kind;

  /// الاسم زي ما اتكتب (من غير التخصص) — null = ما كتبش.
  final String? name;

  /// التخصص اللي اختاره — جوّه [title] كمان.
  final Specialty? specialty;

  /// الساعة لو اختارها — اختيارية. null = من غير ساعة.
  final MinuteOfDay? time;
  final String title;
  final DateTime day;
  final bool fromPaper;
}

/// جسم شيت «ميعاد جديد»: «دكتور ولا معمل؟» ← الاسم (اختياري) ← اليوم ← «احفظ الميعاد».
class NewAppointmentBody extends StatefulWidget {
  const NewAppointmentBody({
    required this.today,
    this.allowFromPaper = true,
    this.initialKind,
    this.initialName,
    this.initialDay,
    this.initialTime,
    this.initialSpecialty,
    this.askTime = true,
    super.key,
  });

  /// التخصص اللي اتقال في «كلّمني» أو اللي المصدر قاله («القريب مني») —
  /// **عمره ما بيتخمّن**: غير كده فاضي لحد ما الشخص يختار.
  final Specialty? initialSpecialty;

  /// «الساعة ٥ العصر» من «كلّمني» — في خانة الساعة، مش في الاسم.
  final MinuteOfDay? initialTime;

  /// الممرض: طلبه المعلّق مالوش خانة ساعة، فالسؤال ما بيظهرش عنده.
  final bool askTime;

  final DateTime today;

  /// «كلّمني»: الورقة بتتفتح **متعبّية** باللي اتفهم — والحفظ بزرارها هي.
  final FollowKind? initialKind;
  final String? initialName;
  final DateTime? initialDay;

  /// «عندي روشتة — ابدأ منها» — للمريض بس؛ الممرض ما عندوش ورق المريض.
  final bool allowFromPaper;

  @override
  State<NewAppointmentBody> createState() => _NewAppointmentBodyState();
}

class _NewAppointmentBodyState extends State<NewAppointmentBody> {
  late FollowKind _kind = widget.initialKind ?? FollowKind.visit;
  late final _name = TextEditingController(text: widget.initialName ?? '');
  late DateTime _day = widget.initialDay ?? DateTime(widget.today.year, widget.today.month, widget.today.day + 1);

  /// اختيارية — null لحد ما يدوس شريحة أو يحرّك البكرة.
  late MinuteOfDay? _time = widget.initialTime;
  static final MinuteOfDay _rest = MinuteOfDay.hm(9);
  late Specialty? _specialty = widget.initialSpecialty;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String get _title => bookingTitle(_kind, _name.text, _kind == FollowKind.visit ? _specialty : null);

  String? get _typedName => _name.text.trim().isEmpty ? null : _name.text.trim();

  Future<void> _pickSpecialty() async {
    final picked = await FSheet.show<({Specialty? value})>(
      context,
      title: 'التخصص',
      children: [
        Wrap(
          spacing: F.s8,
          runSpacing: F.s8,
          children: [
            for (final sp in Specialty.values)
              AnchorChip(
                key: ValueKey('specialty-${sp.name}'),
                label: sp.label,
                selected: _specialty == sp,
                onTap: () => Navigator.of(context).pop((value: sp)),
              ),
          ],
        ),
        FSecondaryButton(
          key: const ValueKey('specialty-none'),
          label: 'من غير تخصص',
          onPressed: () => Navigator.of(context).pop((value: null)),
        ),
      ],
    );
    if (picked != null && mounted) setState(() => _specialty = picked.value);
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('دكتور ولا معمل؟', style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w600, color: F.mutedDark)),
          const SizedBox(height: F.s8),
          Row(
            children: [
              Expanded(
                child: AnchorChip(
                  key: const ValueKey('new-appt-visit'),
                  label: 'دكتور',
                  selected: _kind == FollowKind.visit,
                  onTap: () => setState(() => _kind = FollowKind.visit),
                ),
              ),
              const SizedBox(width: F.s8),
              Expanded(
                child: AnchorChip(
                  key: const ValueKey('new-appt-lab'),
                  label: 'معمل',
                  selected: _kind == FollowKind.lab,
                  onTap: () => setState(() => _kind = FollowKind.lab),
                ),
              ),
            ],
          ),
          const SizedBox(height: F.s12),
          TextField(
            key: const ValueKey('new-appt-name'),
            controller: _name,
            textInputAction: TextInputAction.done,
            style: TextStyle(fontSize: F.minBodySize, color: F.ink),
            decoration: InputDecoration(
              hintText: _kind == FollowKind.visit ? 'اسم الدكتور (لو حابب)' : 'اسم التحليل (لو حابب)',
              hintStyle: TextStyle(fontSize: F.minTextSize, color: F.mutedDark),
              filled: true,
              fillColor: F.fieldGround,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(F.radiusCard)),
            ),
          ),
          // التخصص (طلب المالك، ٢٩ سبتمبر ٢٠٢٦): اختياري، ومن الشخص بس — أو من
          // «كلّمني» أو «القريب مني» لو قالوه. بيتحفظ في اسم الزيارة.
          if (_kind == FollowKind.visit) ...[
            const SizedBox(height: F.s8),
            FSecondaryButton(
              key: const ValueKey('new-appt-specialty'),
              label: _specialty == null ? 'التخصص (لو حابب)' : 'التخصص: ${_specialty!.label}',
              onPressed: _pickSpecialty,
            ),
          ],
          const SizedBox(height: F.s12),
          Text('إمتى؟', style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w600, color: F.mutedDark)),
          const SizedBox(height: F.s8),
          DayPicker(today: widget.today, value: _day, onChanged: (d) => setState(() => _day = d)),
          if (widget.askTime) ...[
            const SizedBox(height: F.s12),
            // نفس ساعة «ضيف دوا»: الشرايح السريعة والبكرة — واختيارية
            Row(
              children: [
                Expanded(
                  child: Text('الساعة كام؟ (لو حابب)',
                      style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w600, color: F.mutedDark)),
                ),
                if (_time != null)
                  SizedBox(
                    height: F.minTapTarget,
                    child: TextButton(
                      key: const ValueKey('new-appt-time-clear'),
                      onPressed: () => setState(() => _time = null),
                      child: Text('من غير ساعة',
                          style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.ink)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: F.s8),
            QuickTimeChips(selected: _time, onPick: (m) => setState(() => _time = m)),
            const SizedBox(height: F.s8),
            FTimeWheel(
              key: const ValueKey('new-appt-time'),
              value: _time ?? _rest,
              onChanged: (m) => setState(() => _time = m),
            ),
            Text(
              _time == null ? 'من غير ساعة' : 'الساعة ${arabicTime(DateTime(2026, 1, 1, 0, _time!.minutes))}',
              key: const ValueKey('new-appt-time-line'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink),
            ),
          ],
          const SizedBox(height: F.gap),
          FPrimaryButton(
            key: const ValueKey('new-appt-save'),
            label: 'احفظ الميعاد',
            onPressed: () => Navigator.of(context).pop(NewAppointmentResult(
              kind: _kind,
              title: _title,
              day: _day,
              time: _time,
              name: _typedName,
              specialty: _kind == FollowKind.visit ? _specialty : null,
            )),
          ),
          // الطرق التلاتة القديمة (من ورقة في الملف / بالصورة / بالإيد) لسه
          // موجودة — من هنا، مش كزرارين على الشاشة الأولى.
          if (widget.allowFromPaper) ...[
          const SizedBox(height: F.s8),
          FSecondaryButton(
            key: ValueKey(_kind == FollowKind.visit ? 'start-follow-visit' : 'start-follow-lab'),
            label: _kind == FollowKind.visit ? 'عندي روشتة — ابدأ منها' : 'عندي تقرير — ابدأ منه',
            onPressed: () => Navigator.of(context).pop(
              NewAppointmentResult(kind: _kind, title: _title, day: _day, fromPaper: true),
            ),
          ),
          ],
        ],
      );
}

class _AppointmentRow extends StatelessWidget {
  const _AppointmentRow({
    required this.title,
    required this.line,
    this.onTap,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String title;
  final String line;
  final VoidCallback? onTap;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: F.s8),
        child: FCard(
          child: InkWell(
            borderRadius: BorderRadius.circular(F.radiusCard),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: F.minTapTarget),
              alignment: AlignmentDirectional.centerStart,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.event_outlined, size: 22, color: F.gold),
                      const SizedBox(width: F.s6),
                      Expanded(
                        child: Text(
                          title,
                          textDirection: nameDirection(title),
                          textAlign: TextAlign.right,
                          style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: F.s4),
                  Text(line, style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.4)),
                  if (actionLabel case final label?) ...[
                    const SizedBox(height: F.s8),
                    FSecondaryButton(label: label, onPressed: onAction),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
}

/// سطر البحث في «أوراقك»: الحقل و«فلتر» و«التقويم». على موبايل ضيق وخط كبير
/// (٣٢٠ ×١٫٣) التلاتة ما بيساعهمش سطر، فالحقل بياخد السطر لوحده والزرارين
/// تحته بالنص. غير كده سطر واحد زي ما كان.
class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.search, required this.filter, required this.calendar});

  final Widget search;
  final Widget filter;
  final Widget calendar;

  static const narrowBelow = 300.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, box) {
          if (box.maxWidth < narrowBelow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                search,
                const SizedBox(height: F.s8),
                Row(
                  children: [
                    Expanded(child: filter),
                    const SizedBox(width: F.s8),
                    Expanded(child: calendar),
                  ],
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: search),
              const SizedBox(width: F.s8),
              filter,
              const SizedBox(width: F.s6),
              calendar,
            ],
          );
        },
      );
}

/// زرار بكلمة، صغير، جنب البحث — «فلتر» و«التقويم».
class _WordButton extends StatelessWidget {
  const _WordButton({required this.label, required this.onTap, super.key});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: F.minTapTarget,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            // الثيم بيدّي الزرار عرض لا نهائي — هنا هو كلمة جنب البحث
            minimumSize: const Size(0, F.minTapTarget),
            foregroundColor: F.ink,
            side: BorderSide(color: F.line, width: 1.5),
            padding: const EdgeInsets.symmetric(horizontal: F.s12),
            textStyle: const TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w700),
          ),
          child: Text(label),
        ),
      );
}

class RecordSummary extends StatelessWidget {
  const RecordSummary({required this.record, super.key})
      : follow = false,
        now = null;

  /// صف متابعة مفتوحة. [now] مطلوبة عشان «بكرة» / «بعد بكرة».
  const RecordSummary.follow({required this.record, required DateTime this.now, super.key})
      : follow = true;

  final RecordRow record;
  final bool follow;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final r = record;
    final stage = follow ? CheckupService.stageOf(r) : null;
    final kind = CheckupService.kindOf(r);
    // **متابعة مفتوحة ما بتعرضش `happenedAt` أبداً.** ده تاريخ بداية
    // المتابعة (أو تاريخ الورقة في الصفوف القديمة)، ومفيش شاشة المفروض
    // تقوله كأنه ميعاد جاي. المصدر واحد للناحيتين: [followDateLine].
    final meta = stage == null
        ? [r.kind.label, ?r.doctor, arabicDate(r.happenedAt)].join(' — ')
        : (r.doctor ?? '');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(r.kind.icon, size: 22, color: F.green),
            const SizedBox(width: F.s6),
            Flexible(
              child: Text(
                follow ? followDisplayTitle(kind, r.title) : r.title,
                textDirection: nameDirection(r.title),
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink),
              ),
            ),
          ],
        ),
        const SizedBox(height: F.s4),
        if (meta.isNotEmpty)
          Text(meta, style: TextStyle(fontSize: F.minTextSize, color: F.mutedDark, height: 1.4)),
        // النوع بيحدد عدد المراحل: التحليل سبعة، والزيارة تلاتة.
        if (stage != null)
          Text(
            'متابعة ${kind.word} — ${arabicNumber(stage.number)} '
            'من ${arabicNumber(kind.stages.length)}: ${stage.label} — '
            '${followDateLine(CheckupService.stageDateOf(r, stage), now!)}',
            style: TextStyle(
                fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.greenStrong, height: 1.4),
          )
        else if (CheckupService.stageOf(r) case final closed?)
          // متابعة خلصت: المرحلة الأخيرة، من غير ميعاد جاي.
          Text(
            'متابعة ${kind.word} — ${closed.label}',
            style: TextStyle(
                fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.greenStrong, height: 1.4),
          ),
      ],
    );
  }
}

/// «بيقرا الورقة…» وإحنا مستنيين الرد — مفيش زرار، الرد بيقفله.
class _ReadingPaperDialog extends StatelessWidget {
  const _ReadingPaperDialog();

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: F.dialogGround,
        content: Row(
          children: [
            const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
            const SizedBox(width: F.s12),
            Expanded(
              child: Text('بيقرا الورقة…',
                  style: TextStyle(fontSize: F.minBodySize, fontWeight: FontWeight.w700, color: F.ink)),
            ),
          ],
        ),
      );
}
