import '../voice/help_button.dart';
import 'package:flutter/material.dart';

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
import 'checkup_screen.dart';
import 'records_empty.dart';
import 'history_screen.dart';
import 'record_row_card.dart';
import 'records_of_kind_screen.dart';
import 'start_follow_up.dart';
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

  /// اسم الفحص (والدكتور لو معروف) → مرحلة ١ «طلب الطبيب».
  /// **تلات طرق تبدأ بيها متابعة** — من الملف، من صورة جديدة، أو بالإيد.
  Future<void> _startFollowUp(FollowKind kind) async {
    final way = await askStartWay(context, kind);
    if (way == null || !mounted) return;
    switch (way) {
      case StartFollowUpWay.fromFile:
        await _startFromFile(kind);
      case StartFollowUpWay.fromPhoto:
        await _startFromPhoto(kind);
      case StartFollowUpWay.byHand:
        await _startByHand(kind);
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

  Future<void> _startFromPhoto(FollowKind kind) async {
    final recordId = await scanForFollowUp(context, kind, today: widget.today);
    if (recordId == null || !mounted) return;
    await _startFrom(recordId, kind);
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

  Future<void> _startByHand(FollowKind kind) async {
    final services = AppScope.of(context);
    final result = await showDialog<({String title, String doctor})>(
      context: context,
      builder: (_) => _StartCheckupDialog(kind: kind),
    );
    if (result == null || result.title.trim().isEmpty || !mounted) return;
    final id = await services.checkups.start(
      patientId: services.patientId,
      kind: kind,
      title: result.title,
      doctor: result.doctor,
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
  Future<void> _newAppointment() async {
    final today = widget.today ?? DateTime.now();
    final result = await FSheet.show<NewAppointmentResult>(
      context,
      title: 'ميعاد جديد',
      children: [NewAppointmentBody(today: DateTime(today.year, today.month, today.day))],
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
    return Scaffold(
      appBar: AppBar(title: const Text('السجل')),
      body: StreamBuilder<List<RecordRow>>(
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
            padding: EdgeInsets.fromLTRB(F.gap, F.s4, F.gap, F.gap + MediaQuery.of(context).padding.bottom),
            children: [
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
              Row(
                children: [
                  Expanded(
                    child: TextField(
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
                  ),
                  const SizedBox(width: F.s8),
                  _WordButton(
                    key: const ValueKey('records-filter'),
                    label: 'فلتر',
                    onTap: all == null || all.isEmpty ? null : () => _filter(all),
                  ),
                  const SizedBox(width: F.s6),
                  _WordButton(
                    key: const ValueKey('records-calendar'),
                    label: 'التقويم',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(builder: (_) => CalendarScreen(today: widget.today)),
                    ),
                  ),
                ],
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
    );
  }
}

/// نتيجة «ميعاد جديد»: نوعه واسمه ويومه — أو «عندي ورقة» فبنفتح الطرق التلاتة القديمة.
class NewAppointmentResult {
  const NewAppointmentResult({required this.kind, required this.title, required this.day, this.fromPaper = false});

  final FollowKind kind;
  final String title;
  final DateTime day;
  final bool fromPaper;
}

/// جسم شيت «ميعاد جديد»: «دكتور ولا معمل؟» ← الاسم (اختياري) ← اليوم ← «احفظ الميعاد».
class NewAppointmentBody extends StatefulWidget {
  const NewAppointmentBody({required this.today, this.allowFromPaper = true, super.key});

  final DateTime today;

  /// «عندي روشتة — ابدأ منها» — للمريض بس؛ الممرض ما عندوش ورق المريض.
  final bool allowFromPaper;

  @override
  State<NewAppointmentBody> createState() => _NewAppointmentBodyState();
}

class _NewAppointmentBodyState extends State<NewAppointmentBody> {
  FollowKind _kind = FollowKind.visit;
  final _name = TextEditingController();
  late DateTime _day = DateTime(widget.today.year, widget.today.month, widget.today.day + 1);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String get _title {
    final typed = _name.text.trim();
    if (typed.isNotEmpty) return typed;
    return _kind == FollowKind.visit ? 'زيارة دكتور' : 'تحليل';
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
              hintText: _kind == FollowKind.visit ? 'اسم الدكتور أو التخصص (لو حابب)' : 'اسم التحليل (لو حابب)',
              hintStyle: TextStyle(fontSize: F.minTextSize, color: F.mutedDark),
              filled: true,
              fillColor: F.fieldGround,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(F.radiusCard)),
            ),
          ),
          const SizedBox(height: F.s12),
          Text('إمتى؟', style: TextStyle(fontSize: F.minTextSize, fontWeight: FontWeight.w600, color: F.mutedDark)),
          const SizedBox(height: F.s8),
          DayPicker(today: widget.today, value: _day, onChanged: (d) => setState(() => _day = d)),
          const SizedBox(height: F.gap),
          FPrimaryButton(
            key: const ValueKey('new-appt-save'),
            label: 'احفظ الميعاد',
            onPressed: () => Navigator.of(context).pop(NewAppointmentResult(kind: _kind, title: _title, day: _day)),
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
            style: const TextStyle(
                fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.greenDeep, height: 1.4),
          )
        else if (CheckupService.stageOf(r) case final closed?)
          // متابعة خلصت: المرحلة الأخيرة، من غير ميعاد جاي.
          Text(
            'متابعة ${kind.word} — ${closed.label}',
            style: const TextStyle(
                fontSize: F.minTextSize, fontWeight: FontWeight.w700, color: F.greenDeep, height: 1.4),
          ),
      ],
    );
  }
}

class _StartCheckupDialog extends StatefulWidget {
  const _StartCheckupDialog({required this.kind});

  final FollowKind kind;

  @override
  State<_StartCheckupDialog> createState() => _StartCheckupDialogState();
}

class _StartCheckupDialogState extends State<_StartCheckupDialog> {
  final _title = TextEditingController();
  final _doctor = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _doctor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: F.dialogGround,
        title: Text(
          widget.kind == FollowKind.lab ? 'متابعة تحليل جديدة' : 'متابعة زيارة جديدة',
          style: const TextStyle(fontSize: F.subtitleSize, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              textInputAction: TextInputAction.next,
              key: const ValueKey('checkup-title'),
              controller: _title,
              style: const TextStyle(fontSize: F.minBodySize),
              decoration: InputDecoration(
                labelText: widget.kind == FollowKind.lab ? 'اسم الفحص' : 'الزيارة عند مين؟',
                hintText: widget.kind == FollowKind.lab ? 'مثلاً: صورة دم كاملة' : 'مثلاً: د. حسام',
              ),
            ),
            // الزيارة اسمها هو الدكتور نفسه، فمفيش حقل تاني يتكتب مرتين.
            if (widget.kind == FollowKind.lab)
              TextField(
                textInputAction: TextInputAction.done,
                controller: _doctor,
                style: const TextStyle(fontSize: F.minBodySize),
                decoration: const InputDecoration(labelText: 'الدكتور اللي طلبه'),
              ),
          ],
        ),
        actions: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FPrimaryButton(
                key: const ValueKey('checkup-start'),
                label: 'ابدأ',
                onPressed: () => Navigator.of(context).pop((
                  title: _title.text,
                  doctor: widget.kind == FollowKind.lab ? _doctor.text : _title.text,
                )),
              ),
            ],
          ),
        ],
      );
}
